/// AssetCache — the on-disk half of image sync: the local folder that holds
/// every image the notes reference, plus a small index that maps a Drive asset
/// id to the file in that folder.
///
/// Sibling of [PageContentCache], which does the same job for page JSON. The
/// difference is the key. Page content is keyed by the page's own Drive file
/// id, so a filename convention is enough. An image can arrive two ways —
/// dropped in by the user (already sitting in the images folder under its
/// original name) or downloaded from Drive on a second device — and re-copying
/// a 5 MB photo just to rename it would be wasteful, so the mapping lives in an
/// index instead:
///
///   assets: driveId  -> filename, relative to the images folder
///   hashes: sha256   -> driveId, so re-pasting the same picture re-uses the
///                       asset already on Drive instead of uploading a copy
///
/// Filenames are stored relative, never absolute: the app-documents directory
/// differs between machines and can move under a user, and an absolute path
/// baked into the index would strand the whole cache the moment it did.
///
/// Every write is best-effort — a cache failure degrades sync, it must never
/// break editing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class AssetCache {
  Directory? _dir;
  Future<Directory>? _dirFuture;

  /// driveId -> filename (relative to [_dir]).
  final Map<String, String> _assets = {};

  /// sha-256 of the bytes -> driveId.
  final Map<String, String> _hashes = {};

  bool _loaded = false;
  Future<void>? _loadFuture;

  /// Serialises index writes. Uploads and downloads finish concurrently, and
  /// two overlapping read-modify-write cycles would lose one of the entries.
  Future<void> _writeQueue = Future.value();

  /// The same folder [persistImageFile] has always copied dropped/pasted images
  /// into, so images from before this feature existed are already in place and
  /// only need an index entry.
  Future<Directory> _imagesDir() {
    final pending = _dirFuture;
    if (pending != null) return pending;
    final future = () async {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/mario_images');
      if (!await dir.exists()) await dir.create(recursive: true);
      return _dir = dir;
    }();
    // Only remember the future once it succeeds. Memoising it unconditionally
    // means one transient platform-channel failure disables the cache for the
    // rest of the session — and a disabled cache turns every successful upload
    // into an orphan, because the id can no longer be recorded.
    _dirFuture = future;
    // then(onError:) rather than catchError: the latter returns a future that
    // completes with the error and that nobody awaits, which Dart reports as
    // an unhandled async error. The caller gets the real failure from `future`.
    unawaited(future.then((_) {}, onError: (Object _) {
      if (identical(_dirFuture, future)) _dirFuture = null;
    }));
    return future;
  }

  File _indexFile(Directory dir) => File('${dir.path}/index.json');

  /// Reads the index into memory. Safe to call repeatedly — the work happens
  /// once and later callers await the same future.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loadFuture ??= () async {
      try {
        final dir = await _imagesDir();
        final f = _indexFile(dir);
        if (await f.exists()) {
          final decoded = jsonDecode(await f.readAsString());
          if (decoded is Map<String, dynamic>) {
            final assets = decoded['assets'];
            if (assets is Map) {
              assets.forEach((k, v) {
                if (k is String && v is String) _assets[k] = v;
              });
            }
            final hashes = decoded['hashes'];
            if (hashes is Map) {
              hashes.forEach((k, v) {
                if (k is String && v is String) _hashes[k] = v;
              });
            }
          }
        }
        _loaded = true;
      } on FormatException {
        // A corrupt index behaves as an empty one and is safe to overwrite;
        // nothing is lost that can't be re-derived, since the ids that matter
        // live in the page JSON.
        _loaded = true;
      } catch (_) {
        // Couldn't even reach the file (the documents directory lookup failed).
        // Do NOT latch: an empty in-memory index that believes it is loaded
        // gets written straight over a perfectly good index.json on the next
        // upload, losing every asset mapping on the device.
        _loadFuture = null;
      }
    }();
  }

  /// Absolute path of the cached file for [driveId], or null if it isn't
  /// cached (or the file has since been deleted from under us).
  ///
  /// Synchronous on purpose: the overwhelmingly common case is a hit, and a
  /// synchronous hit lets the image block paint the picture on its first frame
  /// instead of flashing a spinner. Requires [load] to have completed.
  String? pathFor(String driveId) {
    final dir = _dir;
    if (dir == null) return null;
    final name = _assets[driveId];
    if (name == null) return null;
    final path = '${dir.path}/$name';
    if (!File(path).existsSync()) {
      // Gone behind our back (the user cleaned the folder, another machine's
      // copy never arrived). Note it for the next write to clean up, but stay
      // pure: this runs inside `build`, where mutating state or kicking off a
      // disk write would mean one stale entry rewrites the index on every
      // keystroke.
      _staleIds.add(driveId);
      return null;
    }
    return path;
  }

  /// Ids whose files [pathFor] found missing. Folded into the index the next
  /// time something writes it, rather than on the read that noticed.
  ///
  /// An id is cleared from here the moment it is written again — a re-download
  /// of a file the user had deleted goes `pathFor` (marks stale) → `store`
  /// (writes it back), and without the clear the deferred cleanup would delete
  /// the entry `store` had just added, leaving that image re-downloading on
  /// every single page open.
  final Set<String> _staleIds = {};

  void _dropStale() {
    if (_staleIds.isEmpty) return;
    for (final id in _staleIds) {
      _assets.remove(id);
    }
    _staleIds.clear();
  }

  /// The Drive id previously minted for content with this hash. Used to skip a
  /// redundant upload.
  ///
  /// Deliberately not conditioned on holding a local copy: the question is
  /// "are these bytes already on Drive?", and that stays true after the local
  /// file is deleted — or when it was never indexable in the first place,
  /// which is the case for an image whose copy into the images folder failed.
  String? driveIdForHash(String sha256) => _hashes[sha256];

  /// Record that [driveId]'s content lives at [absolutePath] — the case after
  /// uploading a file the user just dropped in. No bytes are copied.
  ///
  /// The path is only added to the id index if it is inside the images folder,
  /// since the index stores names relative to that folder. A path outside it
  /// (the fallback when copying into the folder failed) still gets its hash
  /// recorded: the hash is what stops a second upload of the same picture, and
  /// that is worth keeping even when the file itself can't be indexed.
  Future<void> register(String driveId, String absolutePath,
      {String? sha256}) async {
    final dir = await _imagesDir();
    _staleIds.remove(driveId);
    if (absolutePath.startsWith('${dir.path}/')) {
      _assets[driveId] = absolutePath.substring(dir.path.length + 1);
    }
    if (sha256 != null) _hashes[sha256] = driveId;
    await _persist();
  }

  /// Write freshly downloaded bytes into the cache under a canonical name and
  /// record them. Returns the absolute path.
  Future<String> store(
    String driveId,
    Uint8List bytes, {
    String extension = '',
    String? sha256,
  }) async {
    final dir = await _imagesDir();
    final name = 'asset_${_safe(driveId)}${_safeExtension(extension)}';
    final target = File('${dir.path}/$name');
    // Temp-then-rename so a concurrent reader never decodes a half-written
    // file — the same guarantee PageContentCache gives page JSON.
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
    _staleIds.remove(driveId);
    _assets[driveId] = name;
    if (sha256 != null) _hashes[sha256] = driveId;
    await _persist();
    return target.path;
  }

  /// Drive ids are `[A-Za-z0-9_-]` already; sanitise anyway so a malformed id
  /// can never walk out of the images folder.
  String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  String _safeExtension(String ext) {
    if (ext.isEmpty) return '';
    final e = ext.startsWith('.') ? ext : '.$ext';
    return RegExp(r'^\.[A-Za-z0-9]{1,8}$').hasMatch(e) ? e.toLowerCase() : '';
  }

  Future<void> _persist() {
    // Guard against the same clobber from the other side: if load() never
    // succeeded, whatever is on disk is strictly better than what's in memory.
    if (!_loaded) return Future.value();
    _dropStale();
    // Chain onto the queue so overlapping callers serialise rather than
    // interleaving read-modify-write on the same file.
    return _writeQueue = _writeQueue.then((_) async {
      try {
        final dir = await _imagesDir();
        final data = jsonEncode({'assets': _assets, 'hashes': _hashes});
        final target = _indexFile(dir);
        final tmp = File('${target.path}.tmp');
        await tmp.writeAsString(data, flush: true);
        await tmp.rename(target.path);
      } catch (_) {/* best-effort */}
    });
  }
}
