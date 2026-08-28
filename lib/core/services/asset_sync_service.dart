/// AssetSyncService — makes an image in a note mean the same thing on every
/// machine you sign in from.
///
/// Before this, an image block stored the absolute path of a file under
/// `~/…/mario_images/`. The path travelled to Drive inside the page JSON and
/// was meaningless anywhere else, so notes synced and their pictures did not:
/// a second device rendered "Image missing: /home/…".
///
/// The fix is to give every image a device-independent name — its id in the
/// same Drive appDataFolder the page JSON already lives in — and to keep the
/// bytes in a local folder on each device so the common path never touches the
/// network:
///
///   insert   copy into the images folder, show it immediately, upload in the
///            background, then stamp the returned id onto the node
///   render   id -> local file if cached (synchronous, no flicker), otherwise
///            download once and cache it
///
/// Same read-through shape as [PageContentRepository] over [PageContentCache],
/// one layer down: [AssetCache] owns the disk, this owns the network and the
/// in-flight bookkeeping.
///
/// Everything here reports failure as a value rather than an exception,
/// because none of it is worth interrupting an edit for. Retries are the
/// caller's business — `AssetSweeper` owns the backoff — so nothing in here
/// loops or reschedules on its own.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'asset_cache.dart';
import 'concurrency_gate.dart';
import 'drive_service.dart';

/// Why an asset operation didn't complete. The distinctions matter because the
/// right response differs: quota is permanent and worth telling the user
/// about, rate limiting wants backoff, offline wants a quiet retry later.
enum AssetError { offline, unauthorized, quota, rateLimited, notFound, unknown }

class AssetSyncService {
  AssetSyncService(this._drive, this._cache);

  final DriveService _drive;
  final AssetCache _cache;

  /// Drive answers a burst of parallel requests with `403 userRateLimitExceeded`,
  /// so a page holding forty uncached images must not open forty connections.
  /// Separate gates per direction: a long upload shouldn't stall the downloads
  /// that decide whether the user sees anything at all.
  final _downloadGate = ConcurrencyGate(3);
  final _uploadGate = ConcurrencyGate(3);

  /// Bounds on how long one request may hang. Without these a half-open
  /// connection leaves a future that never settles, which in the UI is a
  /// spinner that never resolves and never offers a retry.
  static const _metadataTimeout = Duration(seconds: 15);
  static const _downloadTimeout = Duration(minutes: 2);
  static const _uploadTimeout = Duration(minutes: 5);

  /// Collapses concurrent work on one asset. Several blocks can reference the
  /// same picture — without this, opening such a page fires N identical
  /// downloads. Uploads are keyed by content digest rather than by path,
  /// because every clipboard paste writes a *new* `mario_paste_<micros>` file:
  /// keyed by path, twenty pastes of one screenshot would collapse nothing and
  /// mint twenty Drive files.
  final Map<String, Future<String?>> _downloads = {};
  final Map<String, Future<String?>> _uploads = {};

  /// The failure behind the most recent null, per asset key, so callers can
  /// say "Drive is full" rather than give the same shrug for everything.
  final Map<String, AssetError> _lastError = {};

  /// Must complete before [cachedPath] can answer. Cheap: one small JSON read.
  Future<void> warmUp() => _cache.load();

  /// Local path for an already-cached asset, or null. Synchronous so a cache
  /// hit paints on the first frame.
  String? cachedPath(String driveId) => _cache.pathFor(driveId);

  /// Why the last [ensureLocal] or [uploadLocal] for this key returned null.
  AssetError? lastErrorFor(String key) => _lastError[key];

  /// Local path for [driveId], downloading it if this device has never seen
  /// it. Null when the asset can't be fetched (offline, signed out, deleted
  /// from Drive) — callers show a placeholder and try again later.
  ///
  /// [extensionHint] is the extension from the node's own `url`, which syncs
  /// across devices and is therefore known before any request. Supplying it
  /// skips the metadata round-trip, halving the request count on exactly the
  /// cold-open case the rate limiter cares about.
  Future<String?> ensureLocal(String driveId, {String? extensionHint}) {
    final existing = _downloads[driveId];
    if (existing != null) return existing;

    final future = () async {
      await _cache.load();
      final hit = _cache.pathFor(driveId);
      if (hit != null) return hit;
      return _downloadGate.run(() async {
        try {
          // Without a hint, ask for the stored name: it carries the extension
          // given at upload time, which keeps the cached copy openable by
          // anything that sniffs by suffix (tesseract for OCR, the PDF
          // exporter).
          var ext = _extensionOf(extensionHint ?? '');
          if (ext.isEmpty) {
            final name =
                await _drive.remoteFileName(driveId).timeout(_metadataTimeout);
            ext = _extensionOf(name ?? '');
          }
          final bytes =
              await _drive.readBinaryFile(driveId).timeout(_downloadTimeout);
          _lastError.remove(driveId);
          // Record the digest alongside the bytes. Without it a picture
          // downloaded here could never dedupe against the same picture later
          // pasted from this machine's own filesystem — we'd upload a second
          // identical copy.
          return await _cache.store(
            driveId,
            bytes,
            extension: ext,
            sha256: sha256.convert(bytes).toString(),
          );
        } catch (e) {
          _lastError[driveId] = _classify(e);
          return null;
        }
      });
    }();

    _downloads[driveId] = future;
    // Drop the entry once settled so a failed fetch can be retried later
    // instead of the failure being memoised forever.
    future.whenComplete(() => _downloads.remove(driveId));
    return future;
  }

  /// Uploads a local image and returns its Drive id, or null if the upload
  /// couldn't happen. Re-uploading identical bytes is skipped — the content
  /// hash resolves to the id already on Drive, so pasting the same screenshot
  /// twenty times costs one upload.
  Future<String?> uploadLocal(String localPath) async {
    await _cache.load();

    final String digest;
    try {
      digest = await _digestOf(localPath);
    } catch (e) {
      _lastError[localPath] = _classify(e);
      return null; // unreadable, or already deleted
    }

    final known = _cache.driveIdForHash(digest);
    if (known != null) return known;

    final existing = _uploads[digest];
    if (existing != null) return existing;

    final future = _uploadGate.run(() async {
      // Re-check inside the gate: a queued duplicate may have completed while
      // this one waited its turn.
      final settled = _cache.driveIdForHash(digest);
      if (settled != null) return settled;

      final String driveId;
      try {
        final bytes = await File(localPath).readAsBytes();
        final ext = _extensionOf(localPath);
        driveId = await _drive
            .createBinaryFile(
              'mario-asset-${digest.substring(0, 16)}$ext',
              bytes,
              contentType: _mimeOf(ext),
            )
            .timeout(_uploadTimeout);
      } catch (e) {
        _lastError[localPath] = _classify(e);
        return null;
      }
      _lastError.remove(localPath);
      // Bookkeeping deliberately sits outside the try above. The bytes are on
      // Drive now; dropping the id because the local index failed to write
      // would orphan them and make every later attempt upload the very same
      // picture again.
      try {
        await _cache.register(driveId, localPath, sha256: digest);
      } catch (_) {/* index is best-effort */}
      return driveId;
    });

    _uploads[digest] = future;
    future.whenComplete(() => _uploads.remove(digest));
    return future;
  }

  /// Record that [driveId]'s bytes are already sitting at [localPath] on this
  /// machine, without a round-trip. Repairs the case where the note carries an
  /// id but the local index has lost the mapping — a corrupt index, or an
  /// upload that finished after the app was killed mid-stamp.
  Future<void> adoptLocal(String driveId, String localPath) async {
    await _cache.load();
    if (_cache.pathFor(driveId) != null) return;
    await _cache.register(driveId, localPath);
  }

  /// Digest of the file's contents, hashed from a stream rather than one
  /// `readAsBytes` + `convert`. Both run on this isolate, but the streaming
  /// form yields between chunks instead of blocking it for the tens of
  /// milliseconds a phone photo costs — long enough to drop frames mid-typing.
  Future<String> _digestOf(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const FileSystemException('image file is gone');
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  AssetError _classify(Object e) {
    if (e is TimeoutException || e is SocketException) return AssetError.offline;
    if (e is StateError) return AssetError.unauthorized; // no access token
    // googleapis reports HTTP failures as DetailedApiRequestError; matching on
    // the rendered message rather than importing the Drive API here keeps this
    // file free of that dependency. Misclassifying is harmless — it only
    // changes the wording the user sees.
    final text = e.toString();
    if (text.contains('401')) return AssetError.unauthorized;
    if (text.contains('storageQuotaExceeded') || text.contains('quota')) {
      return AssetError.quota;
    }
    if (text.contains('rateLimit') || text.contains('429')) {
      return AssetError.rateLimited;
    }
    if (text.contains('404')) return AssetError.notFound;
    return AssetError.unknown;
  }

  String _extensionOf(String pathOrName) {
    final slash = pathOrName.lastIndexOf('/');
    final base = slash >= 0 ? pathOrName.substring(slash + 1) : pathOrName;
    final dot = base.lastIndexOf('.');
    if (dot <= 0) return '';
    final ext = base.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(ext) ? ext : '';
  }

  String _mimeOf(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.svg':
        return 'image/svg+xml';
      case '.heic':
        return 'image/heic';
      case '.heif':
        return 'image/heif';
      default:
        return 'application/octet-stream';
    }
  }
}
