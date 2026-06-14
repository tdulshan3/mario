/// DriveService — Google Drive appDataFolder I/O for note JSON, audio clips, drawings.
import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'auth_service.dart';

class _BearerClient extends http.BaseClient {
  _BearerClient(this._token, this._inner);
  final String _token;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}

class DriveService {
  DriveService(this._auth);

  final AuthService _auth;
  static const _appFolder = 'appDataFolder';

  Future<drive.DriveApi> _api() async {
    final token = await _auth.driveAccessToken();
    if (token == null) {
      throw StateError('Drive: no access token');
    }
    return drive.DriveApi(_BearerClient(token, http.Client()));
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
}
