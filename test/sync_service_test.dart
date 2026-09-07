/// Creating, renaming and deleting work the same on a train as at a desk.
///
/// Every change lands locally first — the sidebar shows it, the editor opens
/// it — and reaches the server when the server can be reached, in order, by
/// itself. These drive the real SyncService against in-memory doubles of
/// Firestore, Drive and the content cache, flipping them offline and back.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/models/note_page.dart';
import 'package:mario/core/models/notebook.dart';
import 'package:mario/core/models/section.dart';
import 'package:mario/core/services/auth_service.dart';
import 'package:mario/core/services/drive_service.dart';
import 'package:mario/core/services/mario_firestore.dart';
import 'package:mario/core/services/page_content_cache.dart';
import 'package:mario/core/services/page_content_repository.dart';
import 'package:mario/core/services/sync_outbox.dart';
import 'package:mario/core/services/sync_service.dart';
import 'package:mario/core/services/sync_store.dart';

void main() {
  late _FakeFirestore db;
  late _FakeDrive drive;
  late _FakeCache cache;
  late PageContentRepository content;
  late MemorySyncStore store;
  late SyncService sync;

  final now = DateTime(2026, 9, 7);
  Notebook notebook([String id = '']) => Notebook(
      id: id, name: 'Biology', ownerId: 'u1', createdAt: now, updatedAt: now);
  Section section(String notebookId, [String id = '']) =>
      Section(id: id, notebookId: notebookId, name: 'Cells', order: 0);
  NotePage page(String notebookId, String sectionId,
          {String id = '', String title = 'Photosynthesis'}) =>
      NotePage(
        id: id,
        sectionId: sectionId,
        notebookId: notebookId,
        title: title,
        order: 0,
        createdAt: now,
        updatedAt: now,
      );

  setUp(() {
    db = _FakeFirestore();
    drive = _FakeDrive();
    cache = _FakeCache();
    content = PageContentRepository(drive, cache);
    store = MemorySyncStore();
    sync = SyncService(db, content, null, store);
    sync.index.settleGrace = const Duration(milliseconds: 50);
  });

  tearDown(() => sync.dispose());

  Future<List<T>> first<T>(Stream<List<T>> s) => s.first;
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  group('online, a change is on the server before the next frame', () {
    test('a created notebook has an id at once and lands on the server',
        () async {
      final id = await sync.createNotebook(notebook());
      expect(id, startsWith('nb_'));
      await sync.syncNow();
      expect(db.docs['notebooks/$id']?['name'], 'Biology');
      expect(db.docs['notebooks/$id']?['memberUids'], ['u1']);
      expect(sync.pendingOps, isEmpty);
    });

    test('a created page gets its Drive file and the id is written back',
        () async {
      final nb = await sync.createNotebook(notebook());
      final sec = await sync.createSection(section(nb));
      final id = await sync.createPage(page(nb, sec));
      await sync.syncNow();

      final doc = db.docs['notebooks/$nb/pages/$id']!;
      expect(doc['driveFileId'], startsWith('file-'));
      expect(drive.remote[doc['driveFileId']]?['title'], 'Photosynthesis');
      // The local seed is gone, the Drive copy is cached, nothing is dirty.
      expect(cache.content.containsKey('local:$id'), isFalse);
      expect(cache.content.containsKey(doc['driveFileId']), isTrue);
      expect(cache.dirty, isEmpty);
    });
  });

  group('offline, everything still happens locally', () {
    test('a notebook, section and page made offline show up at once', () async {
      db.offline = true;
      drive.offline = true;
      final nb = await sync.createNotebook(notebook());
      final sec = await sync.createSection(section(nb));
      final pg = await sync.createPage(page(nb, sec));

      expect((await first(sync.watchNotebooks('u1'))).map((n) => n.id), [nb]);
      expect((await first(sync.watchSections(nb))).map((s) => s.id), [sec]);
      final pages = await first(sync.watchPages(nb, sec));
      expect(pages.map((p) => p.id), [pg]);
      expect(pages.single.driveFileId, isNull);
      // The editor can open it: its content is under the local key.
      final local = await content.load('local:$pg');
      expect(local['title'], 'Photosynthesis');
      expect(db.docs, isEmpty, reason: 'nothing reached the server');
      expect(sync.pendingOps, hasLength(4));
    });

    test('back online, the queue drains in order and the page is promoted',
        () async {
      db.offline = true;
      drive.offline = true;
      final nb = await sync.createNotebook(notebook());
      final sec = await sync.createSection(section(nb));
      final pg = await sync.createPage(page(nb, sec));
      await sync.updatePage(page(nb, sec, id: pg, title: 'Renamed'));
      await sync.syncNow();
      expect(db.docs, isEmpty);

      db.offline = false;
      drive.offline = false;
      await sync.syncNow();

      expect(sync.pendingOps, isEmpty);
      expect(db.docs['notebooks/$nb']?['name'], 'Biology');
      expect(db.docs['notebooks/$nb/sections/$sec']?['name'], 'Cells');
      final doc = db.docs['notebooks/$nb/pages/$pg']!;
      expect(doc['title'], 'Renamed');
      expect(doc['driveFileId'], startsWith('file-'));
      expect(drive.remote[doc['driveFileId']]?['title'], 'Photosynthesis');
    });

    test('a rename never writes a missing Drive id over a real one', () async {
      final nb = await sync.createNotebook(notebook());
      final sec = await sync.createSection(section(nb));
      final pg = await sync.createPage(page(nb, sec));
      await sync.syncNow();
      final fileId = db.docs['notebooks/$nb/pages/$pg']!['driveFileId'];
      expect(fileId, isNotNull);

      // The sidebar's copy of the page predates the promotion.
      await sync.updatePage(page(nb, sec, id: pg, title: 'Renamed'));
      await sync.syncNow();
      expect(db.docs['notebooks/$nb/pages/$pg']!['driveFileId'], fileId);
      expect(db.docs['notebooks/$nb/pages/$pg']!['title'], 'Renamed');
    });

    test('a page created and deleted offline never reaches the server',
        () async {
      db.offline = true;
      drive.offline = true;
      final nb = await sync.createNotebook(notebook());
      final sec = await sync.createSection(section(nb));
      final pg = await sync.createPage(page(nb, sec));
      await sync.deletePage(page(nb, sec, id: pg));

      expect(await first(sync.watchPages(nb, sec)), isEmpty);
      expect(cache.content.containsKey('local:$pg'), isFalse);
      // Only the delete is left for the page; the create was cancelled.
      final kinds = sync.pendingOps.map((o) => o.kind).toList();
      expect(kinds, ['set', 'set', 'deletePage']);

      db.offline = false;
      drive.offline = false;
      await sync.syncNow();
      expect(db.docs.keys.where((k) => k.contains('/pages/')), isEmpty);
      expect(drive.creates, 0);
    });

    test('deleting a page offline takes its Drive file down later', () async {
      final nb = await sync.createNotebook(notebook());
      final sec = await sync.createSection(section(nb));
      final pg = await sync.createPage(page(nb, sec));
      await sync.syncNow();
      final fileId =
          db.docs['notebooks/$nb/pages/$pg']!['driveFileId'] as String;

      db.offline = true;
      drive.offline = true;
      await sync.deletePage(page(nb, sec, id: pg));
      expect(await first(sync.watchPages(nb, sec)), isEmpty,
          reason: 'hidden at once');
      expect(drive.remote.containsKey(fileId), isTrue,
          reason: 'not yet on Drive');

      db.offline = false;
      drive.offline = false;
      await sync.syncNow();
      expect(drive.remote.containsKey(fileId), isFalse);
      expect(db.docs.containsKey('notebooks/$nb/pages/$pg'), isFalse);
    });

    test('deleting a section offline hides its pages and cascades later',
        () async {
      final nb = await sync.createNotebook(notebook());
      final sec = await sync.createSection(section(nb));
      final pg = await sync.createPage(page(nb, sec));
      await sync.syncNow();
      // The pages stream has to have been seen once for the cascade to know
      // them locally — as it always has by the time a section is deleted.
      await first(sync.watchPages(nb, sec));

      db.offline = true;
      drive.offline = true;
      await sync.deleteSection(nb, sec);
      expect(await first(sync.watchSections(nb)), isEmpty);
      expect(await first(sync.watchPages(nb, sec)), isEmpty);

      db.offline = false;
      drive.offline = false;
      await sync.syncNow();
      expect(db.docs.containsKey('notebooks/$nb/sections/$sec'), isFalse);
      expect(db.docs.containsKey('notebooks/$nb/pages/$pg'), isFalse);
    });
  });

  group('the tree is there without the server', () {
    test('what the server last sent is served when it is unreachable',
        () async {
      final nb = await sync.createNotebook(notebook());
      await sync.syncNow();
      // Seen once online: the snapshot is on disk.
      expect((await first(sync.watchNotebooks('u1'))).map((n) => n.id), [nb]);
      await settle();

      // A fresh service on the same store, with the server down.
      sync.dispose();
      await settle();
      db.offline = true;
      sync = SyncService(db, content, null, store);
      final seen = await first(sync.watchNotebooks('u1'));
      expect(seen.map((n) => n.id), [nb]);
    });

    test('the queue survives a restart', () async {
      db.offline = true;
      drive.offline = true;
      final nb = await sync.createNotebook(notebook());
      sync.dispose();

      sync = SyncService(db, content, null, store);
      db.offline = false;
      drive.offline = false;
      await sync.syncNow();
      expect(db.docs['notebooks/$nb']?['name'], 'Biology');
    });

    test('a save that failed to upload is pushed once the server is back',
        () async {
      final nb = await sync.createNotebook(notebook());
      final sec = await sync.createSection(section(nb));
      final pg = await sync.createPage(page(nb, sec));
      await sync.syncNow();
      final fileId =
          db.docs['notebooks/$nb/pages/$pg']!['driveFileId'] as String;

      drive.offline = true;
      await expectLater(
        content.save(fileId, {'document': {}, 'updatedAt': 'later'}),
        throwsA(anything),
      );
      expect(cache.dirty, contains(fileId));

      drive.offline = false;
      await sync.syncNow();
      expect(drive.remote[fileId]?['updatedAt'], 'later');
      expect(cache.dirty, isEmpty);
    });
  });

  group('what cannot succeed is dropped, what can is retried', () {
    test('a document already gone is as good as deleted', () {
      expect(SyncService.classifyFailure(Exception('NOT_FOUND: no document')),
          OpFailure.drop);
      expect(SyncService.classifyFailure(Exception('404 file not found')),
          OpFailure.drop);
    });

    test('no network, no token and a rate limit all wait', () {
      expect(SyncService.classifyFailure(const SocketException('down')),
          OpFailure.retry);
      expect(SyncService.classifyFailure(StateError('Drive: no access token')),
          OpFailure.retry);
      expect(
          SyncService.classifyFailure(Exception('403 userRateLimitExceeded')),
          OpFailure.retry);
    });
  });
}

// ------------------------------------------------------------------ doubles

/// In-memory Firestore: documents by path, watchers re-emit on every change,
/// and `offline` makes every call throw the way firedart does.
class _FakeFirestore implements MarioFirestore {
  final docs = <String, Map<String, dynamic>>{};
  final _changes = StreamController<void>.broadcast();
  bool offline = false;

  void _check() {
    if (offline) throw const SocketException('offline');
  }

  List<MarioDoc> _query(String collectionPath, MarioFilter? where) {
    final prefix = '$collectionPath/';
    final out = <MarioDoc>[];
    for (final e in docs.entries) {
      if (!e.key.startsWith(prefix)) continue;
      if (e.key.substring(prefix.length).contains('/')) continue;
      final data = e.value;
      if (where != null) {
        if (where.isEqualTo != null && data[where.field] != where.isEqualTo) {
          continue;
        }
        if (where.arrayContains != null &&
            !((data[where.field] as List?)?.contains(where.arrayContains) ??
                false)) {
          continue;
        }
      }
      out.add(MarioDoc(
          id: e.key.substring(prefix.length), path: e.key, data: Map.of(data)));
    }
    return out;
  }

  @override
  Stream<List<MarioDoc>> watchCollection(String collectionPath,
      {MarioFilter? where, String? orderBy, bool descending = false}) {
    if (offline) return Stream.error(const SocketException('offline'));
    late StreamController<List<MarioDoc>> c;
    StreamSubscription? sub;
    c = StreamController(
        onListen: () {
          c.add(_query(collectionPath, where));
          sub = _changes.stream.listen((_) {
            if (offline) {
              c.addError(const SocketException('offline'));
            } else {
              c.add(_query(collectionPath, where));
            }
          });
        },
        onCancel: () => sub?.cancel());
    return c.stream;
  }

  @override
  Future<List<MarioDoc>> fetchCollection(String collectionPath,
      {MarioFilter? where}) async {
    _check();
    return _query(collectionPath, where);
  }

  @override
  Future<String> add(String collectionPath, Map<String, dynamic> data) async {
    _check();
    final id = 'srv${docs.length}';
    docs['$collectionPath/$id'] = Map.of(data);
    _changes.add(null);
    return id;
  }

  @override
  Future<void> set(String docPath, Map<String, dynamic> data,
      {bool merge = false}) async {
    _check();
    docs[docPath] = merge ? {...?docs[docPath], ...data} : Map.of(data);
    _changes.add(null);
  }

  @override
  Future<void> update(String docPath, Map<String, dynamic> data) async {
    _check();
    final existing = docs[docPath];
    if (existing == null) throw Exception('NOT_FOUND: $docPath');
    existing.addAll(data);
    _changes.add(null);
  }

  @override
  Future<void> delete(String docPath) async {
    _check();
    docs.remove(docPath);
    _changes.add(null);
  }

  @override
  Future<void> arrayUnion(
      String docPath, String field, List<Object?> items) async {
    _check();
    final existing = docs[docPath] ??= {};
    final current = List<Object?>.from(existing[field] as List? ?? const []);
    for (final i in items) {
      if (!current.contains(i)) current.add(i);
    }
    existing[field] = current;
    _changes.add(null);
  }
}

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

class _FakeDrive extends DriveService {
  _FakeDrive() : super(_FakeAuth());

  final remote = <String, Map<String, dynamic>>{};
  bool offline = false;
  int creates = 0;
  int _seq = 0;

  void _check() {
    if (offline) throw StateError('Drive: no access token');
  }

  @override
  Future<String> createPageFile(
      String name, Map<String, dynamic> content) async {
    _check();
    creates++;
    final id = 'file-${_seq++}';
    remote[id] = Map.of(content);
    return id;
  }

  @override
  Future<Map<String, dynamic>> readPageFile(String fileId) async {
    _check();
    return Map.of(remote[fileId] ?? const {});
  }

  @override
  Future<String?> updatePageFile(
      String fileId, Map<String, dynamic> content) async {
    _check();
    if (!remote.containsKey(fileId)) throw Exception('404 not found');
    remote[fileId] = Map.of(content);
    return 'm${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Future<String?> remoteModifiedTime(String fileId) async {
    _check();
    return remote.containsKey(fileId) ? 'm0' : null;
  }

  @override
  Future<void> deleteFile(String fileId) async {
    _check();
    remote.remove(fileId);
  }
}

class _FakeCache extends PageContentCache {
  final content = <String, Map<String, dynamic>>{};
  final tags = <String, String?>{};
  final dirty = <String>{};

  @override
  Future<Map<String, dynamic>?> readContent(String fileId) async =>
      content[fileId] == null ? null : Map.of(content[fileId]!);
  @override
  Future<void> writeContent(String fileId, Map<String, dynamic> c) async =>
      content[fileId] = Map.of(c);
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

  @override
  Future<void> markDirty(String fileId) async => dirty.add(fileId);
  @override
  Future<void> clearDirty(String fileId) async => dirty.remove(fileId);
  @override
  Future<List<String>> dirtyIds() async => dirty.toList();
}
