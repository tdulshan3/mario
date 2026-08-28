/// DriveService — Google Drive appDataFolder I/O for note JSON and for the
/// binary assets those notes reference (images today).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'auth_service.dart';

/// Attaches a fresh bearer token to every request.
///
/// The token is fetched per request rather than captured once at [DriveApi]
/// construction. A resumable upload of a phone photo can easily outlive the
/// remaining life of a token that looked valid when the request started, and
/// the commons uploader only retries 5xx — a 401 mid-upload would otherwise be
/// a silent, permanent loss of that image.
class _BearerClient extends http.BaseClient {
  _BearerClient(this._auth, this._inner);
  final AuthService _auth;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _auth.driveAccessToken();
    if (token == null) throw StateError('Drive: no access token');
    request.headers['Authorization'] = 'Bearer $token';
    return _inner.send(request);
  }
}

class DriveService {
  DriveService(this._auth);

  final AuthService _auth;
  static const _appFolder = 'appDataFolder';

  Future<drive.DriveApi> _api() async {
    // Fail fast when signed out, so callers get the same StateError they
    // always did rather than discovering it inside a stream.
    if (await _auth.driveAccessToken() == null) {
      throw StateError('Drive: no access token');
    }
    return drive.DriveApi(_BearerClient(_auth, http.Client()));
  }

  Future<String> createPageFile(String name, Map<String, dynamic> content) async {
    final api = await _api();
    final media = drive.Media(
      Stream.value(utf8.encode(jsonEncode(content))),
      utf8.encode(jsonEncode(content)).length,
      contentType: 'application/json',
    );
    final file = drive.File(name: '$name.json', parents: [_appFolder]);
    final created = await api.files.create(file, uploadMedia: media);
    return created.id!;
  }

  Future<Map<String, dynamic>> readPageFile(String fileId) async {
    final api = await _api();
    final media = await api.files
        .get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  /// Uploads new content and returns the file's resulting `modifiedTime` (ISO
  /// 8601, UTC) so callers can use it as a cache-revalidation marker. Null if
  /// Drive didn't return one.
  Future<String?> updatePageFile(
      String fileId, Map<String, dynamic> content) async {
    final api = await _api();
    final body = utf8.encode(jsonEncode(content));
    final media = drive.Media(Stream.value(body), body.length,
        contentType: 'application/json');
    final updated = await api.files.update(drive.File(), fileId,
        uploadMedia: media, $fields: 'modifiedTime');
    return updated.modifiedTime?.toUtc().toIso8601String();
  }

  /// Cheap metadata fetch of the file's last-modified time — used as a change
  /// marker so the content cache can skip re-downloading unchanged files.
  Future<String?> remoteModifiedTime(String fileId) async {
    final api = await _api();
    final file =
        await api.files.get(fileId, $fields: 'modifiedTime') as drive.File;
    return file.modifiedTime?.toUtc().toIso8601String();
  }

  Future<void> deleteFile(String fileId) async {
    final api = await _api();
    await api.files.delete(fileId);
  }

  // ---------- Binary assets ----------
  //
  // Same appDataFolder as the page JSON, so an asset is covered by the
  // `drive.appdata` scope the app already requests and is invisible in the
  // user's normal Drive listing. Assets are content-addressed by the caller
  // (see AssetSyncService): [name] carries a sha-256 prefix plus the original
  // extension, which is what lets a download reconstruct the right filename.

  /// Anything at or above this goes up as a chunked, retrying resumable
  /// upload; below it a single multipart POST is one round-trip cheaper and
  /// small enough that retrying the whole thing is no hardship. Pasted
  /// screenshots sit well under the line; phone photos sit well over it.
  static const _resumableThresholdBytes = 4 * 1024 * 1024;

  /// Uploads [bytes] as a new appDataFolder file and returns its Drive id.
  Future<String> createBinaryFile(
    String name,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
  }) async {
    final api = await _api();
    final media = drive.Media(
      Stream<List<int>>.value(bytes),
      bytes.length,
      contentType: contentType,
    );
    final created = await api.files.create(
      drive.File(name: name, parents: [_appFolder]),
      uploadMedia: media,
      uploadOptions: bytes.length >= _resumableThresholdBytes
          ? drive.ResumableUploadOptions()
          : drive.UploadOptions.defaultOptions,
      $fields: 'id',
    );
    return created.id!;
  }

  /// Downloads an appDataFolder file's full contents.
  Future<Uint8List> readBinaryFile(String fileId) async {
    final api = await _api();
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  // ---------- Named lookup ----------
  //
  // Page files are found through the id stored on the NotePage index entry,
  // but the AI artifact files have no index row to hang an id on. Rather than
  // add a column to every model, they are found by their well-known name.
  // appDataFolder is private to this app, so a name collision can only be one
  // of our own files.

  /// Escapes a value for a Drive `q` string literal.
  static String _escapeQuery(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  /// Id of the appDataFolder file called [name], or null if there is none.
  ///
  /// Returns the most recently modified match when a crash or a race has left
  /// duplicates, so the newest data wins rather than an arbitrary one.
  Future<String?> findFileByName(String name) async {
    final api = await _api();
    final result = await api.files.list(
      q: "name = '${_escapeQuery(name)}' and trashed = false",
      spaces: _appFolder,
      orderBy: 'modifiedTime desc',
      $fields: 'files(id)',
    );
    final files = result.files;
    return (files == null || files.isEmpty) ? null : files.first.id;
  }

  /// The stored filename of an asset, used to recover its extension when
  /// seeding the local cache. Null if the file is gone or unreadable.
  Future<String?> remoteFileName(String fileId) async {
    final api = await _api();
    final file = await api.files.get(fileId, $fields: 'name') as drive.File;
    return file.name;
  }
}
