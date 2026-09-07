/// Unit tests for PageContentRepository's caching behaviour: cache-first load,
/// write-through save, create-seeds-cache, delete-evicts, and the newer-wins
/// revalidation guard that protects a local edit that hasn't finished
/// uploading. Uses in-memory fakes — no path_provider, network, or appflowy.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/auth_service.dart';
import 'package:mario/core/services/drive_service.dart';
import 'package:mario/core/services/page_content_cache.dart';
import 'package:mario/core/services/page_content_repository.dart';

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

/// In-memory DriveService double: records call counts, serves canned data.
class _FakeDrive extends DriveService {
  _FakeDrive() : super(_FakeAuth());

  final Map<String, Map<String, dynamic>> remote = {};
  final Map<String, String?> modified = {};
  int reads = 0, updates = 0, creates = 0, deletes = 0;
  int _idSeq = 0;

  @override
  Future<Map<String, dynamic>> readPageFile(String fileId) async {
    reads++;
    return Map<String, dynamic>.from(remote[fileId] ?? const {});
  }

  /// When set, uploads fail — Drive is out of reach.
  bool failUpdates = false;

  @override
  Future<String?> updatePageFile(
      String fileId, Map<String, dynamic> content) async {
    if (failUpdates) throw StateError('Drive: no access token');
    updates++;
    remote[fileId] = Map<String, dynamic>.from(content);
    return modified[fileId] = 'm$updates';
  }

  @override
  Future<String> createPageFile(
      String name, Map<String, dynamic> content) async {
    creates++;
    final id = 'file-${_idSeq++}';
    remote[id] = Map<String, dynamic>.from(content);
    modified[id] = 'm0';
    return id;
  }

  @override
  Future<void> deleteFile(String fileId) async {
    deletes++;
    remote.remove(fileId);
    modified.remove(fileId);
  }

  @override
  Future<String?> remoteModifiedTime(String fileId) async => modified[fileId];
}

/// In-memory PageContentCache double — bypasses path_provider / file I/O.
class _FakeCache extends PageContentCache {
  final Map<String, Map<String, dynamic>> content = {};
  final Map<String, String?> tags = {};

  @override
  Future<Map<String, dynamic>?> readContent(String fileId) async =>
      content[fileId] == null
          ? null
          : Map<String, dynamic>.from(content[fileId]!);
  @override
  Future<void> writeContent(String fileId, Map<String, dynamic> c) async =>
      content[fileId] = Map<String, dynamic>.from(c);
  @override
  Future<String?> readTag(String fileId) async => tags[fileId];
  @override
  Future<void> writeTag(String fileId, String? tag) async => tags[fileId] = tag;
  @override
  Future<void> evict(String fileId) async {
    content.remove(fileId);
    tags.remove(fileId);
    dirty.remove(fileId);
  }

  final dirty = <String>{};
  @override
  Future<void> markDirty(String fileId) async => dirty.add(fileId);
  @override
  Future<void> clearDirty(String fileId) async => dirty.remove(fileId);
  @override
  Future<List<String>> dirtyIds() async => dirty.toList();
}

void main() {
  late _FakeDrive drive;
  late _FakeCache cache;
  late PageContentRepository repo;

  setUp(() {
    drive = _FakeDrive();
    cache = _FakeCache();
    repo = PageContentRepository(drive, cache);
  });

  // Let the detached background revalidation kicked off by load() settle.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('load on a cache miss fetches from Drive and populates the cache',
      () async {
    drive.remote['f1'] = {'document': 'X', 'updatedAt': '2026-01-01T00:00:00Z'};
    drive.modified['f1'] = 'm-init';

    final got = await repo.load('f1');

    expect(got['document'], 'X');
    expect(drive.reads, 1);
    expect(cache.content['f1']!['document'], 'X');
    expect(cache.tags['f1'], 'm-init');
  });

  test('load on a cache hit returns instantly without downloading', () async {
    cache.content['f1'] = {'document': 'cached'};
    cache.tags['f1'] = 'm-1';
    drive.modified['f1'] = 'm-1'; // unchanged on Drive

    final got = await repo.load('f1');
    expect(got['document'], 'cached');
    expect(drive.reads, 0); // served from cache, no full download

    await settle();
    expect(drive.reads, 0); // revalidation saw a matching marker → no download
    expect(cache.content['f1']!['document'], 'cached');
  });

  test('save writes through to cache first, then Drive, recording the marker',
      () async {
    await repo
        .save('f1', {'document': 'new', 'updatedAt': '2026-02-02T00:00:00Z'});

    expect(cache.content['f1']!['document'], 'new');
    expect(drive.updates, 1);
    expect(drive.remote['f1']!['document'], 'new');
    expect(cache.tags['f1'], drive.modified['f1']); // marker synced post-upload
  });

  test('create uploads then seeds the cache for an instant first open',
      () async {
    final id = await repo.create('page-x', {'document': 'init'});
    expect(drive.creates, 1);
    expect(cache.content[id]!['document'], 'init');
  });

  test('delete removes the Drive file and evicts the cache', () async {
    cache.content['f1'] = {'document': 'x'};
    cache.tags['f1'] = 'm';
    drive.remote['f1'] = {'document': 'x'};

    await repo.delete('f1');

    expect(drive.deletes, 1);
    expect(cache.content.containsKey('f1'), isFalse);
    expect(cache.tags.containsKey('f1'), isFalse);
  });

  test('revalidation adopts the remote copy when it is strictly newer',
      () async {
    cache.content['f1'] = {
      'document': 'old',
      'updatedAt': '2026-01-01T00:00:00Z'
    };
    cache.tags['f1'] = 'm-old';
    drive.remote['f1'] = {
      'document': 'newer',
      'updatedAt': '2026-03-03T00:00:00Z'
    };
    drive.modified['f1'] = 'm-new'; // changed remotely

    final got = await repo.load('f1');
    expect(got['document'], 'old'); // first paint serves the cache
    await settle();
    expect(cache.content['f1']!['document'], 'newer'); // adopted on revalidate
    expect(cache.tags['f1'], 'm-new');
  });

  test('revalidation never clobbers a local edit newer than remote', () async {
    cache.content['f1'] = {
      'document': 'local-edit',
      'updatedAt': '2026-05-05T00:00:00Z'
    };
    cache.tags['f1'] = null; // locally-dirty (upload pending/failed)
    drive.remote['f1'] = {
      'document': 'stale-remote',
      'updatedAt': '2026-01-01T00:00:00Z'
    };
    drive.modified['f1'] = 'm-remote';

    final got = await repo.load('f1');
    expect(got['document'], 'local-edit');
    await settle();
    // Remote is older → keep the local edit; only refresh the marker.
    expect(cache.content['f1']!['document'], 'local-edit');
    expect(cache.tags['f1'], 'm-remote');
  });

  group('a page with no Drive file yet', () {
    test('lives under its local key, off Drive entirely', () async {
      final key = PageContentRepository.localKeyFor('pg1');
      expect(PageContentRepository.isLocal(key), isTrue);
      await repo.seedLocal(key, {'document': {}, 'title': 'New'});
      expect((await repo.load(key))['title'], 'New');
      await repo.save(key, {'document': {}, 'title': 'Edited'});
      expect((await repo.load(key))['title'], 'Edited');
      expect(drive.reads + drive.updates + drive.creates, 0);
      expect(cache.dirty, contains(key));
    });

    test('opens blank rather than as a dead end when never seeded', () async {
      final raw = await repo.load(PageContentRepository.localKeyFor('old'));
      expect(raw['document'], isNotNull);
      expect(drive.reads, 0);
    });

    test('promotion makes the Drive file from the latest save', () async {
      final key = PageContentRepository.localKeyFor('pg1');
      await repo.seedLocal(key, {'document': {}, 'title': 'New'});
      await repo.save(key, {'document': {}, 'title': 'Edited'});

      final fileId = await repo.promote(key, 'page-1');
      expect(drive.remote[fileId]?['title'], 'Edited');
      expect(cache.content.containsKey(key), isFalse);
      expect(cache.content[fileId]?['title'], 'Edited');
      // Promoting twice is the same file.
      expect(await repo.promote(key, 'page-1'), fileId);
      expect(drive.creates, 1);
    });

    test(
        'an editor still holding the local key keeps saving to the right '
        'place', () async {
      final key = PageContentRepository.localKeyFor('pg1');
      await repo.seedLocal(key, {'document': {}, 'title': 'New'});
      final fileId = await repo.promote(key, 'page-1');

      await repo.save(key, {'document': {}, 'title': 'After'});
      expect(drive.remote[fileId]?['title'], 'After');
      expect((await repo.load(key))['title'], 'After');
      expect(cache.dirty, isEmpty);
    });
  });

  group('a save that could not upload', () {
    test('is marked dirty and pushed by uploadDirty', () async {
      final fileId = await repo.create('page-1', {'document': {}});
      drive.failUpdates = true;
      await expectLater(
        repo.save(fileId, {'document': {}, 'title': 'Offline edit'}),
        throwsA(anything),
      );
      expect(cache.dirty, contains(fileId));
      expect(await repo.hasDirty(), isTrue);

      drive.failUpdates = false;
      expect(await repo.uploadDirty(), 1);
      expect(drive.remote[fileId]?['title'], 'Offline edit');
      expect(cache.dirty, isEmpty);
      expect(cache.tags[fileId], isNotNull);
    });

    test('local keys are not uploaded by the dirty sweep', () async {
      await repo.seedLocal(PageContentRepository.localKeyFor('pg1'), {});
      expect(await repo.uploadDirty(), 0);
      expect(await repo.hasDirty(), isFalse);
      expect(drive.updates, 0);
    });
  });
}
