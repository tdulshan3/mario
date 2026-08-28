/// Unit tests for AssetSyncService — the layer that makes an image in a note
/// resolve on every device: upload-once (content-hash dedupe), download-once
/// (in-flight collapsing), retry-after-failure, and the index-repair path.
/// Uses in-memory fakes for the cache and Drive; only the source images the
/// upload path reads are real files, in a temp dir.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/asset_cache.dart';
import 'package:mario/core/services/asset_sync_service.dart';
import 'package:mario/core/services/auth_service.dart';
import 'package:mario/core/services/drive_service.dart';
import 'package:mario/features/editor/asset_sweeper.dart';
import 'package:mario/features/editor/blocks/mario_image_block.dart';
import 'package:mario/features/editor/image_asset_resolver.dart';

class _FakeAuth implements AuthService {
  @override
  Stream<MarioUser?> authStateChanges() => const Stream.empty();
  @override
  MarioUser? get currentUser => null;
  @override
  Future<MarioUser?> signInWithGoogle() async => null;
  @override
  Future<void> signOut() async {}
  @override
  Future<String?> driveAccessToken() async => null;
}

/// In-memory DriveService double for the binary-asset surface.
class _FakeDrive extends DriveService {
  _FakeDrive() : super(_FakeAuth());

  final Map<String, Uint8List> blobs = {};
  final Map<String, String> names = {};
  int uploads = 0, downloads = 0, nameLookups = 0;
  int _idSeq = 0;

  /// Highest number of requests in flight at once — how the concurrency gate
  /// is observed from outside.
  int inFlight = 0, concurrentPeak = 0;

  /// When set, every call throws — stands in for offline / signed out.
  bool offline = false;

  /// Completes before an upload or download returns, so a test can hold work
  /// open and fire a second concurrent call at it.
  Completer<void>? gate;


  @override
  Future<String> createBinaryFile(String name, Uint8List bytes,
      {String contentType = 'application/octet-stream'}) async {
    if (gate != null) await gate!.future;
    if (offline) throw StateError('Drive: no access token');
    uploads++;
    final id = 'asset-${_idSeq++}';
    blobs[id] = bytes;
    names[id] = name;
    return id;
  }

  @override
  Future<Uint8List> readBinaryFile(String fileId) async {
    inFlight++;
    concurrentPeak = inFlight > concurrentPeak ? inFlight : concurrentPeak;
    try {
      if (gate != null) await gate!.future;
      if (offline) throw StateError('Drive: no access token');
      downloads++;
      final b = blobs[fileId];
      if (b == null) throw StateError('not found');
      return b;
    } finally {
      inFlight--;
    }
  }

  @override
  Future<String?> remoteFileName(String fileId) async {
    if (offline) throw StateError('Drive: no access token');
    nameLookups++;
    return names[fileId];
  }
}

/// In-memory AssetCache double. Deliberately mirrors the real cache's
/// *semantics*, not just its signatures — the `existsSync` check on read and
/// the images-dir guard on register are exactly where the interesting bugs
/// live, so a fake without them would pass tests the real thing fails.
class _FakeCache extends AssetCache {
  _FakeCache(this.dir);

  /// Stands in for the real `<documents>/mario_images`.
  final String dir;

  final Map<String, String> assets = {}; // driveId -> absolute path
  final Map<String, String> hashes = {}; // sha256  -> driveId
  final Map<String, Uint8List> stored = {};

  /// Set to make register() throw, standing in for an unwritable index.
  bool registerThrows = false;

  @override
  Future<void> load() async {}

  @override
  String? pathFor(String driveId) {
    final path = assets[driveId];
    if (path == null) return null;
    // The real cache treats a vanished file as a miss.
    if (!stored.containsKey(path) && !File(path).existsSync()) return null;
    return path;
  }

  @override
  String? driveIdForHash(String sha256) {
    final id = hashes[sha256];
    return (id != null && assets.containsKey(id)) ? id : null;
  }

  @override
  Future<void> register(String driveId, String absolutePath,
      {String? sha256}) async {
    if (registerThrows) throw const FileSystemException('index unwritable');
    // The real cache only indexes paths inside the images folder, since the
    // index stores names relative to it.
    if (absolutePath.startsWith('$dir/')) assets[driveId] = absolutePath;
    if (sha256 != null) hashes[sha256] = driveId;
  }

  @override
  Future<String> store(String driveId, Uint8List bytes,
      {String extension = '', String? sha256}) async {
    final path = '$dir/asset_$driveId$extension';
    stored[path] = bytes;
    assets[driveId] = path;
    if (sha256 != null) hashes[sha256] = driveId;
    return path;
  }
}

void main() {
  late Directory tmp;
  late _FakeDrive drive;
  late _FakeCache cache;
  late AssetSyncService assets;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mario_assets_test');
    drive = _FakeDrive();
    cache = _FakeCache(tmp.path);
    assets = AssetSyncService(drive, cache);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> writeImage(String name, List<int> bytes) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  // ---------- upload ----------

  test('uploadLocal pushes the bytes and reports the Drive id', () async {
    final path = await writeImage('shot.png', [1, 2, 3]);

    final id = await assets.uploadLocal(path);

    expect(id, isNotNull);
    expect(drive.uploads, 1);
    expect(drive.blobs[id!], [1, 2, 3]);
    // The stored name carries the extension, which is what lets a download on
    // another device reconstruct a suffix that tesseract and the PDF exporter
    // can sniff.
    expect(drive.names[id], endsWith('.png'));
    expect(cache.pathFor(id), path);
  });

  test('the same picture inserted twice uploads once', () async {
    final a = await writeImage('a.png', [9, 9, 9]);
    final b = await writeImage('b.png', [9, 9, 9]); // identical bytes

    final first = await assets.uploadLocal(a);
    final second = await assets.uploadLocal(b);

    expect(second, first);
    expect(drive.uploads, 1, reason: 'content hash should short-circuit');
  });

  test('two concurrent uploads of one file collapse into a single request',
      () async {
    final path = await writeImage('shot.png', [4, 5, 6]);
    drive.gate = Completer<void>();

    final a = assets.uploadLocal(path);
    final b = assets.uploadLocal(path);
    drive.gate!.complete();

    expect(await a, await b);
    expect(drive.uploads, 1);
  });

  test('uploadLocal reports failure rather than throwing, and stays retryable',
      () async {
    final path = await writeImage('shot.png', [7]);
    drive.offline = true;

    expect(await assets.uploadLocal(path), isNull);

    // The failure must not be memoised — coming back online has to work
    // without restarting the app.
    drive.offline = false;
    expect(await assets.uploadLocal(path), isNotNull);
    expect(drive.uploads, 1);
  });

  test('uploadLocal returns null for a file that is no longer there', () async {
    expect(await assets.uploadLocal('${tmp.path}/gone.png'), isNull);
    expect(drive.uploads, 0);
  });

  // ---------- download ----------

  test('ensureLocal serves a cached asset without touching the network',
      () async {
    final path = await writeImage('already-here.png', [1]);
    cache.assets['asset-x'] = path;

    expect(await assets.ensureLocal('asset-x'), path);
    expect(drive.downloads, 0);
  });

  test('ensureLocal re-downloads when the cached file has been deleted',
      () async {
    final path = await writeImage('gone.png', [1]);
    cache.assets['asset-x'] = path;
    await File(path).delete();
    drive.blobs['asset-x'] = Uint8List.fromList([2]);
    drive.names['asset-x'] = 'mario-asset-deadbeef.png';

    expect(await assets.ensureLocal('asset-x'), isNotNull);
    expect(drive.downloads, 1);
  });

  test('ensureLocal records the digest, so a later local paste of the same '
      'picture does not upload a duplicate', () async {
    drive.blobs['asset-x'] = Uint8List.fromList([5, 5, 5]);
    drive.names['asset-x'] = 'mario-asset-deadbeef.png';
    await assets.ensureLocal('asset-x');

    // Same picture, now arriving from this machine's own filesystem.
    final local = await writeImage('same.png', [5, 5, 5]);
    expect(await assets.uploadLocal(local), 'asset-x');
    expect(drive.uploads, 0);
  });

  test('an extension hint skips the metadata round-trip', () async {
    drive.blobs['asset-x'] = Uint8List.fromList([1]);
    drive.names['asset-x'] = 'mario-asset-deadbeef.png';

    final path = await assets.ensureLocal('asset-x',
        extensionHint: '/home/other-device/mario_images/photo.jpg');

    expect(path, endsWith('.jpg'), reason: 'hint wins over remote metadata');
    expect(drive.nameLookups, 0);
  });

  test('ensureLocal downloads a never-seen asset and caches it under its '
      'original extension', () async {
    drive.blobs['asset-x'] = Uint8List.fromList([1, 1, 2, 3]);
    drive.names['asset-x'] = 'mario-asset-deadbeef.jpg';

    final path = await assets.ensureLocal('asset-x');

    expect(path, endsWith('.jpg'));
    expect(cache.stored[path!], [1, 1, 2, 3]);
    expect(drive.downloads, 1);
    // Second read is a cache hit.
    expect(await assets.ensureLocal('asset-x'), path);
    expect(drive.downloads, 1);
  });

  test('a page with the same image in several blocks downloads it once',
      () async {
    drive.blobs['asset-x'] = Uint8List.fromList([1]);
    drive.names['asset-x'] = 'mario-asset-deadbeef.png';
    drive.gate = Completer<void>();

    final futures =
        List.generate(5, (_) => assets.ensureLocal('asset-x')).toList();
    drive.gate!.complete();
    final paths = await Future.wait(futures);

    expect(paths.toSet(), hasLength(1));
    expect(drive.downloads, 1);
  });

  test('a failed download returns null and is retried later, not memoised',
      () async {
    drive.blobs['asset-x'] = Uint8List.fromList([1]);
    drive.names['asset-x'] = 'a.png';
    drive.offline = true;

    expect(await assets.ensureLocal('asset-x'), isNull);

    drive.offline = false;
    expect(await assets.ensureLocal('asset-x'), isNotNull);
  });

  // ---------- index repair ----------

  test('adoptLocal re-points a lost index entry without downloading', () async {
    final path = await writeImage('shot.png', [1]);

    await assets.adoptLocal('asset-x', path);

    expect(assets.cachedPath('asset-x'), path);
    expect(drive.downloads, 0);
  });

  test('adoptLocal leaves an already-cached asset alone', () async {
    final canonical = await writeImage('canonical.png', [1]);
    cache.assets['asset-x'] = canonical;

    await assets.adoptLocal('asset-x', '${tmp.path}/other.png');

    expect(assets.cachedPath('asset-x'), canonical);
  });

  // ---------- the orphan guard ----------

  test('a successful upload reports its id even when the local index fails '
      'to record it', () async {
    final path = await writeImage('shot.png', [1, 2]);
    cache.registerThrows = true;

    final id = await assets.uploadLocal(path);

    // The bytes are on Drive. Dropping the id here would orphan them and make
    // every later attempt upload the very same picture again.
    expect(id, isNotNull);
    expect(drive.uploads, 1);
  });

  test('two different files holding identical bytes upload once, even '
      'concurrently', () async {
    // The real shape of repeated clipboard pastes: each writes a new
    // mario_paste_<micros>.png, so de-duplicating by path would catch nothing.
    final a = await writeImage('paste_1.png', [3, 3, 3]);
    final b = await writeImage('paste_2.png', [3, 3, 3]);
    drive.gate = Completer<void>();

    final futures = [assets.uploadLocal(a), assets.uploadLocal(b)];
    drive.gate!.complete();
    final ids = await Future.wait(futures);

    expect(ids.toSet(), hasLength(1));
    expect(drive.uploads, 1);
  });

  test('concurrent downloads are capped', () async {
    for (var i = 0; i < 10; i++) {
      drive.blobs['asset-$i'] = Uint8List.fromList([i]);
      drive.names['asset-$i'] = 'a$i.png';
    }
    drive.gate = Completer<void>();

    final futures = [
      for (var i = 0; i < 10; i++) assets.ensureLocal('asset-$i'),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Everything past the gate limit must still be queued, not in flight.
    expect(drive.concurrentPeak, lessThanOrEqualTo(3));
    drive.gate!.complete();
    await Future.wait(futures);
    expect(drive.downloads, 10);
  });

  // ---------- the document-level sweep ----------

  group('AssetSweeper', () {
    afe.Node imageNode(String url, {String? driveId}) => afe.Node(
          type: MarioImageKeys.type,
          attributes: {
            MarioImageKeys.url: url,
            if (driveId != null) MarioImageKeys.driveId: driveId,
          },
        );

    /// A document whose top level is [nodes], plus a paragraph so the editor
    /// never sees an empty root.
    afe.EditorState editorWith(List<afe.Node> nodes) {
      final doc = afe.Document.blank(withInitialText: true);
      doc.insert([1], nodes);
      return afe.EditorState(document: doc);
    }

    String idOf(afe.EditorState e, int index) =>
        e.document.nodeAtPath([index])!.attributes[MarioImageKeys.driveId]
            as String;

    test('uploads every local image and stamps the ids onto the nodes',
        () async {
      final a = await writeImage('a.png', [1]);
      final b = await writeImage('b.png', [2]);
      final editor = editorWith([imageNode(a), imageNode(b)]);

      await AssetSweeper(editor, assets).sweep();

      expect(drive.uploads, 2);
      expect(idOf(editor, 1), isNotEmpty);
      expect(idOf(editor, 2), isNotEmpty);
    });

    test('reaches images the editor never renders', () async {
      // The editor lays blocks out lazily, so anything below the fold is never
      // built. This is the case a block-driven upload would silently skip, and
      // the whole reason the sweep walks the document instead.
      final deep = await writeImage('deep.png', [7]);
      final editor = editorWith([
        for (var i = 0; i < 200; i++) afe.paragraphNode(text: 'line $i'),
        imageNode(deep),
      ]);

      await AssetSweeper(editor, assets).sweep();

      expect(drive.uploads, 1);
      expect(idOf(editor, 201), isNotEmpty);
    });

    test('all the stamps from one pass land in a single transaction', () async {
      final editor = editorWith([
        for (var i = 0; i < 5; i++) imageNode(await writeImage('i$i.png', [i])),
      ]);
      var transactions = 0;
      editor.transactionStream.listen((e) {
        if (e.$1 == afe.TransactionTime.after) transactions++;
      });

      await AssetSweeper(editor, assets).sweep();
      await Future<void>.delayed(Duration.zero);

      // Five separate stamps would mark the page dirty five times and schedule
      // five autosaves.
      expect(transactions, 1);
      expect(drive.uploads, 5);
    });

    test('leaves already-synced images alone', () async {
      final editor =
          editorWith([imageNode(await writeImage('a.png', [1]), driveId: 'x')]);

      await AssetSweeper(editor, assets).sweep();

      expect(drive.uploads, 0);
      expect(idOf(editor, 1), 'x');
    });

    test('ignores remote urls and paths that no longer exist', () async {
      final editor = editorWith([
        imageNode('https://example.com/cat.png'),
        imageNode('${tmp.path}/never-existed.png'),
      ]);

      await AssetSweeper(editor, assets).sweep();

      expect(drive.uploads, 0);
    });

    test('backs off after a failure instead of retrying on every save',
        () async {
      final editor = editorWith([imageNode(await writeImage('a.png', [1]))]);
      final sweeper = AssetSweeper(editor, assets);
      drive.offline = true;

      await sweeper.sweep();
      expect(sweeper.pendingCount.value, 1);

      // A save a moment later must not re-read and re-hash the same file.
      drive.offline = false;
      await sweeper.sweep();
      expect(drive.uploads, 0, reason: 'still inside the backoff window');
    });

    test('assetIds reports every id the page references', () async {
      final editor = editorWith([
        imageNode('/a.png', driveId: 'one'),
        imageNode('/b.png', driveId: 'two'),
        imageNode('/c.png'), // not yet uploaded
      ]);

      expect(AssetSweeper(editor, assets).assetIds(), ['one', 'two']);
    });

    test('skips a node the user deleted while its upload was in flight',
        () async {
      final editor = editorWith([imageNode(await writeImage('a.png', [1]))]);
      final sweeper = AssetSweeper(editor, assets);
      drive.gate = Completer<void>();

      final pass = sweeper.sweep();
      final node = editor.document.nodeAtPath([1])!;
      await editor.apply(editor.transaction..deleteNode(node));
      drive.gate!.complete();

      // The upload still happens — the bytes were already on their way — but
      // stamping a detached node would write onto the document root.
      await expectLater(pass, completes);
      expect(editor.document.root.children.length, 1);
    });
  });

  // ---------- serialization rewrites ----------

  group('export/preview src rewriting', () {
    const subs = {'/home/a/mario_images/x.png': '/home/b/mario_images/y.png'};

    test('rewrites the src attribute in both quote styles', () {
      expect(
        rewriteHtmlImageSources('<img src="/home/a/mario_images/x.png">', subs),
        '<img src="file:///home/b/mario_images/y.png">',
      );
      expect(
        rewriteHtmlImageSources("<img src='/home/a/mario_images/x.png'>", subs),
        "<img src='file:///home/b/mario_images/y.png'>",
      );
    });

    test('leaves the same path alone when it appears in prose', () {
      const html = '<p>saved to /home/a/mario_images/x.png</p>';
      expect(rewriteHtmlImageSources(html, subs), html);
    });

    test('rewrites a markdown image target', () {
      expect(
        rewriteMarkdownImageSources('![](/home/a/mario_images/x.png)', subs),
        '![](/home/b/mario_images/y.png)',
      );
    });

    test('an empty substitution map is a no-op', () {
      expect(rewriteHtmlImageSources('<img src="a">', const {}),
          '<img src="a">');
      expect(rewriteMarkdownImageSources('![](a)', const {}), '![](a)');
    });
  });
}
