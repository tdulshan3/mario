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
    final cached = await _cache.readContent(fileId);
    if (cached != null) {
      if (revalidate) {
        final tag = await _cache.readTag(fileId);
        unawaited(_revalidate(fileId, cached, tag));
      }
      return cached;
    }
    final content = await _drive.readPageFile(fileId);
    await _cache.writeContent(fileId, content);
    await _cache.writeTag(fileId, await _markerOrNull(fileId));
    return content;
  }

  /// Write-through save: persist to the cache first, then upload to Drive.
  /// Rethrows upload failures (the caller surfaces them); the cache already
  /// holds the content, so a reload stays correct and fast, and a later save
  /// will push it.
  Future<void> save(String fileId, Map<String, dynamic> content) async {
    await _cache.writeContent(fileId, content);
    await _cache.writeTag(fileId, null); // locally-dirty until the upload confirms
    final marker = await _drive.updatePageFile(fileId, content);
    await _cache.writeTag(fileId, marker);
  }

  /// Creates the Drive file, then seeds the cache with the initial content so
  /// the first open is instant. Returns the new Drive file id.
  Future<String> create(String name, Map<String, dynamic> content) async {
    final fileId = await _drive.createPageFile(name, content);
    await _cache.writeContent(fileId, content);
    await _cache.writeTag(fileId, await _markerOrNull(fileId));
    return fileId;
  }

  /// Deletes the Drive file and evicts the cache (cache eviction always runs,
  /// even if the remote delete throws).
  Future<void> delete(String fileId) async {
    try {
      await _drive.deleteFile(fileId);
    } finally {
      await _cache.evict(fileId);
    }
  }

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
    if (c == null) return true; // cached unstamped, remote stamped → take remote
    return r.isAfter(c);
  }

  DateTime? _updatedAt(Map<String, dynamic> m) {
    final v = m['updatedAt'];
    return v is String ? DateTime.tryParse(v) : null;
  }
}
