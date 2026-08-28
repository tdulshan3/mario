/// AssetSweeper — walks the open page and makes sure every image in it has
/// been pushed to Drive, then stamps the returned ids back onto the nodes.
///
/// Uploading from inside the image block itself looks natural and is wrong in
/// both directions:
///
///  * **It misses images.** The editor lays blocks out in a
///    `ScrollablePositionedList` (see the vendored
///    `entry/page_block_component.dart`), so a picture below the fold is never
///    built and never uploads. The user scrolls to the bottom on their laptop,
///    sees every image, and on the desktop the ones they never scrolled past
///    are missing — the exact failure this feature exists to fix, hiding.
///  * **It fires far too often.** Every transaction rebuilds the mounted
///    blocks, so a failed upload retried from `didUpdateWidget` would re-read
///    and re-hash the file on every keystroke.
///
/// The document is the right unit of work: it holds every image whether or not
/// it is on screen, and it changes on a schedule we control. So the block owns
/// only the download half (it renders, so it's the natural place to ask for
/// bytes) and this owns the upload half for the whole page.
///
/// All the stamps from one pass land in a single transaction, so a page of
/// twenty migrating images marks the document dirty once rather than twenty
/// times.
library;

import 'dart:async';
import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/foundation.dart';

import '../../core/services/asset_sync_service.dart';
import 'blocks/_safe_transaction.dart';
import 'blocks/mario_image_block.dart';

class AssetSweeper {
  AssetSweeper(this._editorState, this._assets);

  final afe.EditorState _editorState;
  final AssetSyncService _assets;

  bool _running = false;
  bool _disposed = false;

  /// Per-source backoff, so an offline session doesn't re-read and re-hash the
  /// same files every couple of seconds for as long as the page is open.
  final Map<String, _Attempt> _attempts = {};

  /// Set while at least one image is known to be un-uploaded, so the editor
  /// can tell the user their pictures aren't safe on another device yet.
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  static const _backoffs = [
    Duration(seconds: 5),
    Duration(seconds: 20),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  void dispose() {
    _disposed = true;
    pendingCount.dispose();
  }

  /// Every Drive asset id the page currently references.
  ///
  /// Written into the saved page JSON so that a future cleanup pass can tell
  /// which assets are still live. Recording it now is what keeps that option
  /// open: deleting a page destroys its JSON, and with it the only record of
  /// which images belonged to it — after that the bytes are unreachable
  /// orphans in the user's Drive quota with no way to identify them.
  List<String> assetIds() {
    final ids = <String>{};
    for (final n in _imageNodes()) {
      final id = n.attributes[MarioImageKeys.driveId];
      if (id is String && id.isNotEmpty) ids.add(id);
    }
    return ids.toList(growable: false);
  }

  /// Upload every image that doesn't have a Drive id yet, then stamp the ids
  /// onto their nodes in one transaction. Safe to call often — it no-ops while
  /// a pass is in flight, when nothing is pending, and while a source is in
  /// backoff after a recent failure.
  Future<void> sweep() async {
    if (kIsWeb || _running || _disposed) return;
    _running = true;
    try {
      final pending = await _pending();
      _setPending(pending.length);
      if (pending.isEmpty) return;

      final now = DateTime.now();
      final due = pending.where((p) {
        final attempt = _attempts[p.url];
        return attempt == null || !attempt.nextAt.isAfter(now);
      }).toList(growable: false);
      if (due.isEmpty) return;

      final stamped = <_Pending, String>{};
      await Future.wait(due.map((p) async {
        // uploadLocal is itself gated and de-duplicated, so firing the whole
        // batch at once is bounded work, not a thundering herd.
        final id = await _assets.uploadLocal(p.url);
        if (id == null) {
          _recordFailure(p.url);
        } else {
          _attempts.remove(p.url);
          stamped[p] = id;
        }
      }));

      if (stamped.isEmpty || _disposed || _editorState.isDisposed) return;

      await safeApply(_editorState, (tx) {
        stamped.forEach((p, id) {
          // Re-resolve by path and confirm it's still the same node. Between
          // collection and here the user may have deleted the image or moved
          // it; a detached node's path is empty, and updating that would write
          // attributes onto the document root.
          final current = _editorState.document.nodeAtPath(p.node.path);
          if (!identical(current, p.node)) return;
          tx.updateNode(p.node, {MarioImageKeys.driveId: id});
        });
      }, background: true);

      _setPending(pending.length - stamped.length);
    } finally {
      _running = false;
    }
  }

  /// The page can be closed while a pass is still awaiting uploads, and
  /// [dispose] disposes the notifier — writing to it after that throws.
  void _setPending(int n) {
    if (_disposed) return;
    pendingCount.value = n < 0 ? 0 : n;
  }

  void _recordFailure(String url) {
    final prev = _attempts[url];
    final n = (prev?.count ?? 0) + 1;
    final wait = _backoffs[(n - 1).clamp(0, _backoffs.length - 1)];
    _attempts[url] = _Attempt(n, DateTime.now().add(wait));
  }

  Iterable<afe.Node> _imageNodes() sync* {
    Iterable<afe.Node> walk(afe.Node n) sync* {
      if (n.type == MarioImageKeys.type) yield n;
      for (final c in n.children) {
        yield* walk(c);
      }
    }

    for (final n in _editorState.document.root.children) {
      yield* walk(n);
    }
  }

  /// Image nodes that have local bytes but no Drive id yet — the ones this
  /// device still owes the cloud.
  Future<List<_Pending>> _pending() async {
    final out = <_Pending>[];
    for (final n in _imageNodes()) {
      final id = n.attributes[MarioImageKeys.driveId];
      if (id is String && id.isNotEmpty) continue;
      final url = n.attributes[MarioImageKeys.url];
      if (url is! String || url.isEmpty) continue;
      // Only local files sync. A pasted https image is already addressable
      // from anywhere and doesn't need a copy in the user's Drive.
      final uri = Uri.tryParse(url);
      if (uri != null && uri.scheme.isNotEmpty && uri.scheme != 'file') {
        continue;
      }
      if (!await File(url).exists()) continue;
      out.add(_Pending(n, url));
    }
    return out;
  }
}

class _Pending {
  const _Pending(this.node, this.url);
  final afe.Node node;
  final String url;
}

class _Attempt {
  const _Attempt(this.count, this.nextAt);
  final int count;
  final DateTime nextAt;
}
