/// Unit tests for the real [AssetCache] — the on-disk index that maps a Drive
/// asset id to the local image file. Runs against genuine files in a temp dir
/// with `path_provider` mocked, because every interesting bug in this class is
/// about the interaction between the in-memory maps and what's actually on
/// disk, which an in-memory double cannot reproduce.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/asset_cache.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.base);
  final String base;

  /// Simulates a transient platform-channel failure.
  bool fail = false;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    if (fail) throw Exception('transient platform failure');
    return base;
  }
}

void main() {
  late Directory tmp;
  late Directory imagesDir;
  late _FakePathProvider platform;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mario_asset_cache_test');
    imagesDir = Directory('${tmp.path}/mario_images')
      ..createSync(recursive: true);
    platform = _FakePathProvider(tmp.path);
    PathProviderPlatform.instance = platform;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  File seedImage(String name, List<int> bytes) =>
      File('${imagesDir.path}/$name')..writeAsBytesSync(bytes);

  Map<String, dynamic> readIndex() =>
      jsonDecode(File('${imagesDir.path}/index.json').readAsStringSync())
          as Map<String, dynamic>;

  test('registers a file already in the images folder without copying it',
      () async {
    final cache = AssetCache();
    await cache.load();
    final f = seedImage('mario_image_1.png', [1, 2, 3]);

    await cache.register('X', f.path, sha256: 'shaA');

    expect(cache.pathFor('X'), f.path);
    expect(cache.driveIdForHash('shaA'), 'X');
    // Stored relative — an absolute path baked into the index would strand the
    // whole cache if the documents directory ever moved.
    expect(readIndex()['assets'], {'X': 'mario_image_1.png'});
  });

  test('a file deleted behind our back reads as a miss', () async {
    final cache = AssetCache();
    await cache.load();
    final f = seedImage('mario_image_1.png', [1]);
    await cache.register('X', f.path);

    f.deleteSync();

    expect(cache.pathFor('X'), isNull);
  });

  test('re-downloading a deleted asset makes it resolvable again', () async {
    // The regression: pathFor marks a missing id stale, and the deferred
    // cleanup used to run inside the very write that restored it — deleting
    // the entry store() had just added, so the image re-downloaded on every
    // page open, forever.
    final cache = AssetCache();
    await cache.load();
    final f = seedImage('asset_X.png', [1, 2, 3]);
    await cache.register('X', f.path, sha256: 'shaA');

    f.deleteSync();
    expect(cache.pathFor('X'), isNull, reason: 'marks it stale');

    final restored = await cache.store('X', Uint8List.fromList([9, 9]),
        extension: '.png', sha256: 'shaA');

    expect(File(restored).existsSync(), isTrue);
    expect(cache.pathFor('X'), restored);
    expect(readIndex()['assets'], contains('X'));
  });

  test('a genuinely stale entry is dropped from the index on the next write',
      () async {
    final cache = AssetCache();
    await cache.load();
    final gone = seedImage('gone.png', [1]);
    await cache.register('GONE', gone.path);
    gone.deleteSync();
    cache.pathFor('GONE'); // notices, defers the cleanup

    await cache.store('OTHER', Uint8List.fromList([2]), extension: '.png');

    expect(readIndex()['assets'], isNot(contains('GONE')));
    expect(readIndex()['assets'], contains('OTHER'));
  });

  test('a failed directory lookup never clobbers a good index on disk',
      () async {
    File('${imagesDir.path}/asset_OLD.png').writeAsBytesSync([1]);
    File('${imagesDir.path}/index.json').writeAsStringSync(jsonEncode({
      'assets': {'OLD': 'asset_OLD.png'},
      'hashes': {'shaOLD': 'OLD'},
    }));

    final cache = AssetCache();
    platform.fail = true;
    await cache.load(); // startup warm-up hits a transient failure
    platform.fail = false;
    await cache.load(); // any later call must retry rather than stay empty

    expect(cache.pathFor('OLD'), isNotNull,
        reason: 'the retry should have picked the index up');

    await cache.store('NEW', Uint8List.fromList([5]), extension: '.png');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // An empty in-memory index that believed it was loaded would have been
    // written straight over this, losing every asset mapping on the device.
    expect(readIndex()['assets'], containsPair('OLD', 'asset_OLD.png'));
    expect(readIndex()['assets'], contains('NEW'));
  });

  test('a corrupt index behaves as an empty one and is safe to overwrite',
      () async {
    File('${imagesDir.path}/index.json').writeAsStringSync('{not json');

    final cache = AssetCache();
    await cache.load();
    await cache.store('NEW', Uint8List.fromList([5]), extension: '.png');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(readIndex()['assets'], contains('NEW'));
  });

  test('the hash record survives a file that could not be indexed', () async {
    // persistImageFile can fail (permissions, full disk), and the insert path
    // then falls back to the original location. The file itself can't go in
    // the index, which stores names relative to the images folder — but the
    // hash must still be recorded, or the same picture uploads again.
    final cache = AssetCache();
    await cache.load();
    final outside = File('${tmp.path}/elsewhere.png')..writeAsBytesSync([7]);

    await cache.register('id1', outside.path, sha256: 'H');

    expect(cache.driveIdForHash('H'), 'id1');
    expect(readIndex()['assets'], isNot(contains('id1')));
  });

  test('an id survives a reload from disk', () async {
    final first = AssetCache();
    await first.load();
    final f = seedImage('mario_image_1.png', [1]);
    await first.register('X', f.path, sha256: 'shaA');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final second = AssetCache();
    await second.load();

    expect(second.pathFor('X'), f.path);
    expect(second.driveIdForHash('shaA'), 'X');
  });

  test('a malformed id cannot escape the images folder', () async {
    final cache = AssetCache();
    await cache.load();

    final path = await cache.store('../../etc/passwd', Uint8List.fromList([1]),
        extension: '.png');

    expect(path, startsWith(imagesDir.path));
  });
}
