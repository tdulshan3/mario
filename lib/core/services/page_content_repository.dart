/// PageContentRepository — the single choke-point for page content I/O, adding
/// a local cache in front of [DriveService] so page open/create/reload no
/// longer waits on a Google Drive round-trip:
///
///  * [load]   — cache-first (instant open); revalidates against Drive in the
///               background and refreshes the cache for next time.
///  * [save]   — write-through: cache first (so the latest edit survives even
///               if the upload fails or the user navigates away), then Drive.
///  * [create] — uploads to Drive, then seeds the cache so the first open of a
///               brand-new page is a cache hit.
///  * [delete] — removes the Drive file and evicts the cache.
///
/// **Pages that have no Drive file yet** live under a *local key* —
/// `local:<pageId>` — which is a cache entry and nothing else. A page created
/// while Drive is out of reach is seeded there, the editor opens it there,
/// and its saves land there; [promote] later creates the Drive file from it
/// and, for the rest of the session, forwards the local key to the new id so
/// an editor still holding the old key keeps saving to the right place.
///
/// **Saves that failed to upload** are marked dirty in the cache, and
/// [uploadDirty] pushes them when asked — by the sync service, once the
/// server is reachable again — so a save that failed on a train is not lost
/// and not forgotten either.
///
/// Data safety: background revalidation never replaces a cache entry unless the
/// remote copy is *strictly newer* (by the content's `updatedAt` stamp), so it
/// can never overwrite a local edit that hasn't finished uploading.
library;

import 'dart:async';

import 'drive_service.dart';
import 'page_content_cache.dart';

class PageContentRepository {
  PageContentRepository(this._drive, this._cache);

  final DriveService _drive;
  final PageContentCache _cache;

  /// Local keys, forwarded to the Drive id they were promoted to.
  final _promoted = <String, String>{};

  static const localPrefix = 'local:';

  /// The cache key a page lives under before it has a Drive file.
  static String localKeyFor(String pageId) => '$localPrefix$pageId';

  static bool isLocal(String fileId) => fileId.startsWith(localPrefix);

  String _resolve(String fileId) => _promoted[fileId] ?? fileId;

  /// Cache-first load. On a hit, returns cached content immediately and kicks
  /// off a detached background revalidation. On a miss, fetches from Drive,
  /// caches, and returns.
  ///
  /// Set [revalidate] to false for a bulk read — opening one page should check
  /// Drive for a newer copy, but reading forty pages of a section at once must
  /// not fire forty *detached* revalidations in one tick. Those are outside
  /// any caller's concurrency gate (they are `unawaited`), and a burst like
  /// that is exactly what Drive answers with `403 userRateLimitExceeded`. The
  /// pages are still served from cache, and the next single-page open
  /// revalidates them normally.
  Future<Map<String, dynamic>> load(String fileId,
      {bool revalidate = true}) async {
    final id = _resolve(fileId);
    if (isLocal(id)) {
      // Nothing to revalidate against: the cache is the only copy. A page
      // whose Drive create failed before local keys existed has no entry
      // either — it opens blank rather than as a dead end.
      return await _cache.readContent(id) ?? emptyContent();
    }
    final cached = await _cache.readContent(id);
    if (cached != null) {
      if (revalidate) {
        final tag = await _cache.readTag(id);
        unawaited(_revalidate(id, cached, tag));
      }
      return cached;
    }
    final content = await _drive.readPageFile(id);
    await _cache.writeContent(id, content);
    await _cache.writeTag(id, await _markerOrNull(id));
    return content;
  }

  /// Write-through save: persist to the cache first, then upload to Drive.
  /// Rethrows upload failures (the caller surfaces them); the cache already
  /// holds the content, marked dirty, so a reload stays correct and fast and
  /// [uploadDirty] will push it later.
  Future<void> save(String fileId, Map<String, dynamic> content) async {
    final id = _resolve(fileId);
    await _cache.writeContent(id, content);
    await _cache.markDirty(id);
    if (isLocal(id)) return; // no Drive file yet; promote() will carry it up
    await _cache.writeTag(id, null); // locally-dirty until the upload confirms
    final marker = await _drive.updatePageFile(id, content);
    await _cache.writeTag(id, marker);
    await _cache.clearDirty(id);
  }

  /// Creates the Drive file, then seeds the cache with the initial content so
  /// the first open is instant. Returns the new Drive file id.
  Future<String> create(String name, Map<String, dynamic> content) async {
    final fileId = await _drive.createPageFile(name, content);
    await _cache.writeContent(fileId, content);
    await _cache.writeTag(fileId, await _markerOrNull(fileId));
    return fileId;
  }

  /// Seeds a page that has no Drive file yet, under its local key.
  Future<void> seedLocal(String localKey, Map<String, dynamic> content) async {
    await _cache.writeContent(localKey, content);
    await _cache.markDirty(localKey);
  }

  /// Creates the Drive file for a page seeded under [localKey], from whatever
  /// the cache holds for it now — the latest save, if the page was edited in
  /// the meantime. Returns the Drive id, and forwards the local key to it.
  Future<String> promote(String localKey, String name) async {
    final already = _promoted[localKey];
    if (already != null) return already;
    final content = await _cache.readContent(localKey) ?? emptyContent();
    final fileId = await _drive.createPageFile(name, content);
    await _cache.writeContent(fileId, content);
    await _cache.writeTag(fileId, await _markerOrNull(fileId));
    _promoted[localKey] = fileId;
    await _cache.evict(localKey);
    return fileId;
  }

  /// Deletes the Drive file and evicts the cache (cache eviction always runs,
  /// even if the remote delete throws). A local key has nothing on Drive.
  Future<void> delete(String fileId) async {
    final id = _resolve(fileId);
    if (isLocal(id)) {
      await _cache.evict(id);
      return;
    }
    try {
      await _drive.deleteFile(id);
    } finally {
      await _cache.evict(id);
    }
  }

  /// Drops the cached copy only. For a page being deleted while the Drive
  /// delete waits in the outbox.
  Future<void> evict(String fileId) => _cache.evict(_resolve(fileId));

  /// Pushes every save that did not reach Drive. Local keys are skipped:
  /// their upload is the promotion the sync service queues for them.
  /// Returns how many were pushed; stops at the first failure, since the
  /// cause is almost always the same for all of them.
  Future<int> uploadDirty() async {
    var pushed = 0;
    for (final id in await _cache.dirtyIds()) {
      if (isLocal(id)) continue;
      final content = await _cache.readContent(id);
      if (content == null) {
        await _cache.clearDirty(id);
        continue;
      }
      final marker = await _drive.updatePageFile(id, content);
      await _cache.writeTag(id, marker);
      await _cache.clearDirty(id);
      pushed++;
    }
    return pushed;
  }

  /// Whether any save is still waiting for Drive.
  Future<bool> hasDirty() async =>
      (await _cache.dirtyIds()).any((id) => !isLocal(id));

  /// A blank page, in the editor's own JSON: one empty paragraph.
  static Map<String, dynamic> emptyContent() => {
        'document': {
          'type': 'page',
          'children': [
            {
              'type': 'paragraph',
              'data': {'delta': <Object?>[]},
            },
          ],
        },
      };

  Future<String?> _markerOrNull(String fileId) async {
    try {
      return await _drive.remoteModifiedTime(fileId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _revalidate(
    String fileId,
    Map<String, dynamic> cached,
    String? cachedTag,
  ) async {
    try {
      final remoteTag = await _drive.remoteModifiedTime(fileId);
      // Unchanged on Drive since we last synced → nothing to download.
      if (remoteTag != null && cachedTag != null && remoteTag == cachedTag) {
        return;
      }
      final remote = await _drive.readPageFile(fileId);
      if (_remoteIsNewer(remote, cached)) {
        await _cache.writeContent(fileId, remote);
      }
      // Refresh the tag either way: avoids re-downloading an unchanged file on
      // every open, and stops a local-newer entry from looking perpetually
      // dirty.
      await _cache.writeTag(fileId, remoteTag);
    } catch (_) {
      // Offline / transient — keep serving the cache.
    }
  }

  /// True only when the remote copy is provably newer than the cached one (by
  /// `updatedAt`). Ambiguous cases keep the cache, so a local edit mid-upload
  /// is never overwritten.
  bool _remoteIsNewer(
      Map<String, dynamic> remote, Map<String, dynamic> cached) {
    final r = _updatedAt(remote);
    final c = _updatedAt(cached);
    if (r == null) return false; // remote unstamped → don't clobber local
    if (c == null) {
      return true; // cached unstamped, remote stamped → take remote
    }
    return r.isAfter(c);
  }

  DateTime? _updatedAt(Map<String, dynamic> m) {
    final v = m['updatedAt'];
    return v is String ? DateTime.tryParse(v) : null;
  }
}
