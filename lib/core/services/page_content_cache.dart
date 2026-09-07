/// PageContentCache — local on-disk cache of page content JSON, keyed by the
/// page's Google Drive file id.
///
/// Backs the read-through / write-through behaviour in [PageContentRepository]
/// so opening, creating and reloading a page no longer blocks on a Drive
/// round-trip.
///
/// Layout: a content file plus a tiny tag sidecar per page, under the app
/// support dir. Two files (rather than one envelope) on purpose — if a crash
/// leaves the tag missing or stale, revalidation just re-checks Drive and the
/// newer-wins guard in the repository prevents clobbering a local edit, so the
/// split is self-healing. All writes are best-effort: a cache failure must
/// never break the caller.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class PageContentCache {
  Future<Directory>? _dirFuture;

  Future<Directory> _cacheDir() {
    return _dirFuture ??= () async {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/page_content_cache');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }();
  }

  // Drive ids are already filesystem-safe ([A-Za-z0-9_-]); sanitise defensively
  // so a malformed id can never escape the cache directory.
  String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  File _contentFile(Directory dir, String id) =>
      File('${dir.path}/${_safe(id)}.json');
  File _tagFile(Directory dir, String id) =>
      File('${dir.path}/${_safe(id)}.tag');
  File _dirtyFile(Directory dir, String id) =>
      File('${dir.path}/${_safe(id)}.dirty');

  Future<Map<String, dynamic>?> readContent(String fileId) async {
    try {
      final f = _contentFile(await _cacheDir(), fileId);
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null; // a corrupt/unreadable entry behaves as a miss
    }
  }

  Future<void> writeContent(String fileId, Map<String, dynamic> content) async {
    try {
      final dir = await _cacheDir();
      await _atomicWrite(_contentFile(dir, fileId), jsonEncode(content));
    } catch (_) {/* best-effort */}
  }

  /// The change marker (Drive `modifiedTime`) the cached content was last known
  /// to match; null when locally-dirty or never synced.
  Future<String?> readTag(String fileId) async {
    try {
      final f = _tagFile(await _cacheDir(), fileId);
      if (!await f.exists()) return null;
      final s = await f.readAsString();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeTag(String fileId, String? tag) async {
    try {
      final dir = await _cacheDir();
      final f = _tagFile(dir, fileId);
      if (tag == null) {
        if (await f.exists()) await f.delete();
      } else {
        await _atomicWrite(f, tag);
      }
    } catch (_) {/* best-effort */}
  }

  Future<void> evict(String fileId) async {
    try {
      final dir = await _cacheDir();
      for (final f in [
        _contentFile(dir, fileId),
        _tagFile(dir, fileId),
        _dirtyFile(dir, fileId),
      ]) {
        if (await f.exists()) await f.delete();
      }
    } catch (_) {/* best-effort */}
  }

  /// Marks content as saved here but not yet on Drive.
  ///
  /// A sidecar of its own rather than "no tag": a missing tag also means
  /// "never checked", which is true of every page opened offline, and
  /// re-uploading all of those would be wrong. This marker is set by a save
  /// and cleared by the upload that follows it, so it means exactly one
  /// thing — and it survives a restart, which is when it is needed.
  Future<void> markDirty(String fileId) async {
    try {
      // The id goes inside: a file name is a sanitised id (a local key's
      // colon becomes an underscore), and the id read back has to be the
      // one the caller uses.
      await _atomicWrite(_dirtyFile(await _cacheDir(), fileId), fileId);
    } catch (_) {/* best-effort */}
  }

  Future<void> clearDirty(String fileId) async {
    try {
      final f = _dirtyFile(await _cacheDir(), fileId);
      if (await f.exists()) await f.delete();
    } catch (_) {/* best-effort */}
  }

  /// Every id whose latest save has not reached Drive.
  Future<List<String>> dirtyIds() async {
    try {
      final dir = await _cacheDir();
      final out = <String>[];
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.dirty')) {
          final id = (await e.readAsString()).trim();
          if (id.isNotEmpty) out.add(id);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // Write to a temp file then rename so a reader never sees a half-written file.
  Future<void> _atomicWrite(File target, String data) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(target.path);
  }
}
