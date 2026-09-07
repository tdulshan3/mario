/// SyncService — notebook hierarchy CRUD on top of the [MarioFirestore] facade,
/// local-first.
///
/// Every change is applied here first and sent to the server second. A create
/// gets an id minted on this device, so the sidebar can show it, the editor
/// can open it and a rename can target it before the server has heard of it;
/// the change itself goes into a [SyncOutbox] that tries the server at once
/// and keeps trying, in order, when it is out of reach. What the screens see
/// comes from a [LocalIndex]: the server's last answer, kept on disk, with
/// the outbox's changes laid over it. The upshot is that creating, renaming
/// and deleting work the same on a train as at a desk, and catch up by
/// themselves.
///
/// Page content follows the same rule through [PageContentRepository]: a new
/// page is seeded under a local key and promoted to a Drive file by the
/// outbox, and a save that failed to upload is pushed by [syncNow].
library;

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/foundation.dart' show ValueListenable;

import '../models/note_page.dart';
import '../models/notebook.dart';
import '../models/section.dart';
import 'ai/ai_artifact_store.dart';
import 'ai/json_coercion.dart';
import 'local_index.dart';
import 'mario_firestore.dart';
import 'page_content_repository.dart';
import 'sync_outbox.dart';
import 'sync_store.dart';

class SyncService {
  SyncService(
    this._db,
    this._content, [
    this._aiArtifacts,
    SyncStore? store,
  ]) {
    final s = store ?? MemorySyncStore();
    index = LocalIndex(s);
    _outbox = SyncOutbox(
      store: s,
      perform: _perform,
      classify: classifyFailure,
    );
    _settledSub = _outbox.settled.listen((op) {
      final docId = op.args['docId'];
      if (docId is String) index.settled(docId);
      // The server is reachable: a save that failed earlier can go up now.
      _uploadDirtySoon();
    });
  }

  final MarioFirestore _db;
  final PageContentRepository _content;

  /// Optional so tests can construct a SyncService without the AI layer.
  ///
  /// Deleting a page has to evict what the AI features derived from it —
  /// summaries are keyed by page id, and a quiz about a page that no longer
  /// exists is unanswerable. Without this the artifacts are orphaned in a
  /// per-notebook blob that is downloaded on every notebook load, growing
  /// forever and occasionally handing a stale summary to a section read.
  final AiArtifactStore? _aiArtifacts;

  /// What this device knows of the tree. Public for the tools that need a
  /// synchronous look at it.
  late final LocalIndex index;
  late final SyncOutbox _outbox;
  StreamSubscription<PendingOp>? _settledSub;
  Timer? _dirtyTimer;
  Timer? _dirtyPoll;
  bool _disposed = false;

  /// Changes waiting for the server, for the status line.
  ValueListenable<int> get pendingChanges => _outbox.pendingCount;

  /// The queue, for tests and diagnostics.
  List<PendingOp> get pendingOps => _outbox.ops;

  Future<void> _forgetAiArtifacts(String notebookId, String pageId) async {
    try {
      await _aiArtifacts?.forgetPage(notebookId, pageId);
    } catch (_) {
      // Best-effort, exactly like the Drive content delete above it: failing
      // to tidy derived data must never block deleting the page itself.
    }
  }

  static const _root = 'notebooks';
  String _sectionsPath(String notebookId) => '$_root/$notebookId/sections';
  String _pagesPath(String notebookId) => '$_root/$notebookId/pages';
  String _notebookDoc(String id) => '$_root/$id';
  String _sectionDoc(String notebookId, String id) =>
      '$_root/$notebookId/sections/$id';
  String _pageDoc(String notebookId, String id) =>
      '$_root/$notebookId/pages/$id';

  // ---------- Watches ----------

  Stream<List<Notebook>> watchNotebooks(String uid) {
    // Signed in and looking: the moment to send what waited.
    _outbox.drainSoon();
    _startDirtyPoll();
    return index.notebooks(
      uid,
      () => _db
          .watchCollection(_root,
              where: MarioFilter.contains('memberUids', uid))
          .map((docs) => [
                for (final d in docs) Notebook.fromMap(d.id, d.data),
              ]),
    );
  }

  Stream<List<Section>> watchSections(String notebookId) => index.sections(
        notebookId,
        () => _db
            .watchCollection(_sectionsPath(notebookId), orderBy: 'order')
            .map((docs) => [
                  for (final d in docs) Section.fromMap(d.id, d.data),
                ]),
      );

  Stream<List<NotePage>> watchPages(String notebookId, String sectionId) =>
      index.pages(
        notebookId,
        sectionId,
        () => _db
            .watchCollection(
          _pagesPath(notebookId),
          where: MarioFilter.eq('sectionId', sectionId),
        )
            .map((docs) {
          final pages = [
            for (final d in docs) NotePage.fromMap(d.id, d.data),
          ];
          // Sort client-side to skip the (sectionId, order) composite index.
          // Firestore can serve `where(sectionId)` alone without one.
          pages.sort((a, b) => a.order.compareTo(b.order));
          return List<NotePage>.unmodifiable(pages);
        }),
      );

  // ---------- Notebooks ----------

  /// Creates the notebook and returns its id — at once, whatever the network
  /// is doing. An id given in [nb] is kept; an empty one is minted here.
  Future<String> createNotebook(Notebook nb) async {
    final id = nb.id.isEmpty ? newClientId('nb') : nb.id;
    final saved = Notebook(
      id: id,
      name: nb.name,
      ownerId: nb.ownerId,
      collaboratorUids: nb.collaboratorUids,
      colorIndex: nb.colorIndex,
      createdAt: nb.createdAt,
      updatedAt: nb.updatedAt,
    );
    index.putNotebook(saved);
    await _enqueue(PendingOp(
      id: newClientId('op'),
      kind: 'set',
      args: {
        'docId': id,
        'path': _notebookDoc(id),
        'data': {
          ...saved.toMap(),
          'memberUids': [saved.ownerId, ...saved.collaboratorUids],
        },
      },
    ));
    return id;
  }

  Future<void> updateNotebook(Notebook nb) async {
    index.putNotebook(nb);
    await _enqueue(PendingOp(
      id: newClientId('op'),
      kind: 'update',
      args: {'docId': nb.id, 'path': _notebookDoc(nb.id), 'data': nb.toMap()},
    ));
  }

  Future<void> deleteNotebook(String id) async {
    for (final p in index.knownPagesOfNotebook(id)) {
      await _evictContent(p);
    }
    index.removeNotebook(id);
    // The whole notebook's AI artifacts go with it, in one call rather than
    // per page — the blob is keyed by notebook.
    try {
      await _aiArtifacts?.forgetNotebook(id);
    } catch (_) {}
    await _cancelPendingFor([id]);
    await _enqueue(PendingOp(
      id: newClientId('op'),
      kind: 'deleteNotebook',
      args: {'docId': id, 'notebookId': id},
    ));
  }

  // ---------- Sections ----------

  Future<String> createSection(Section section) async {
    final id = section.id.isEmpty ? newClientId('sec') : section.id;
    final saved = Section(
      id: id,
      notebookId: section.notebookId,
      name: section.name,
      colorIndex: section.colorIndex,
      order: section.order,
    );
    index.putSection(saved);
    await _enqueue(PendingOp(
      id: newClientId('op'),
      kind: 'set',
      args: {
        'docId': id,
        'path': _sectionDoc(section.notebookId, id),
        'data': saved.toMap(),
      },
    ));
    return id;
  }

  Future<void> updateSection(Section section) async {
    index.putSection(section);
    await _enqueue(PendingOp(
      id: newClientId('op'),
      kind: 'update',
      args: {
        'docId': section.id,
        'path': _sectionDoc(section.notebookId, section.id),
        'data': section.toMap(),
      },
    ));
  }

  Future<void> deleteSection(String notebookId, String sectionId) async {
    final pages = index.knownPages(notebookId, sectionId);
    for (final p in pages) {
      await _evictContent(p);
      await _forgetAiArtifacts(notebookId, p.id);
    }
    index.removeSection(notebookId, sectionId);
    await _cancelPendingFor([sectionId, for (final p in pages) p.id]);
    await _enqueue(PendingOp(
      id: newClientId('op'),
      kind: 'deleteSection',
      args: {
        'docId': sectionId,
        'notebookId': notebookId,
        'sectionId': sectionId,
      },
    ));
  }

  // ---------- Pages ----------

  /// Creates the page's index entry and its content — blank, or holding
  /// [document] when the caller already has content for it.
  ///
  /// The content is seeded under the page's local key, so the editor can open
  /// it this instant; the Drive file is made by the outbox, right away when
  /// Drive answers and later when it does not, and the page's `driveFileId`
  /// is filled in then.
  Future<String> createPage(NotePage page, {afe.Document? document}) async {
    final id = page.id.isEmpty ? newClientId('pg') : page.id;
    final localKey = PageContentRepository.localKeyFor(id);
    await _content.seedLocal(
      localKey,
      document == null
          ? _emptyPageContent(page.title)
          : _pageContent(document, page.title),
    );
    final saved = NotePage(
      id: id,
      sectionId: page.sectionId,
      notebookId: page.notebookId,
      title: page.title,
      order: page.order,
      indentLevel: page.indentLevel,
      createdAt: page.createdAt,
      updatedAt: page.updatedAt,
    );
    index.putPage(saved);
    await _enqueue(PendingOp(
      id: newClientId('op'),
      kind: 'set',
      args: {
        'docId': id,
        'path': _pageDoc(page.notebookId, id),
        'data': saved.toMap(),
      },
    ));
    await _enqueue(PendingOp(
      id: newClientId('op'),
      kind: 'promote',
      args: {
        'docId': id,
        'notebookId': page.notebookId,
        'pageId': id,
        'localKey': localKey,
        'name': 'page-${DateTime.now().millisecondsSinceEpoch}',
      },
    ));
    return id;
  }

  Future<void> updatePage(NotePage page) async {
    // The caller's copy of the page may predate its promotion, with no Drive
    // id yet. Writing that null would take the real id off the server.
    final known = index.knownPage(page.notebookId, page.id);
    final fileId = page.driveFileId ?? known?.driveFileId;
    final saved = page.copyWith(driveFileId: fileId);
    index.putPage(saved);
    final data = saved.toMap();
    if (data['driveFileId'] == null) data.remove('driveFileId');
    await _enqueue(PendingOp(
      id: newClientId('op'),
      kind: 'update',
      args: {
        'docId': page.id,
        'path': _pageDoc(page.notebookId, page.id),
        'data': data,
      },
    ));
  }

  Future<void> deletePage(NotePage page) async {
    final known = index.knownPage(page.notebookId, page.id);
    final fileId = page.driveFileId ?? known?.driveFileId;
    index.removePage(page.id);
    await _evictContent(page);
    await _forgetAiArtifacts(page.notebookId, page.id);
    await _cancelPendingFor([page.id]);
    await _enqueue(PendingOp(
      id: newClientId('op'),
      kind: 'deletePage',
      args: {
        'docId': page.id,
        'notebookId': page.notebookId,
        'pageId': page.id,
        if (fileId != null) 'fileId': fileId,
      },
    ));
  }

  // ---------- Sync ----------

  /// Sends everything waiting, then pushes any save that failed to upload.
  Future<void> syncNow() async {
    await _outbox.drain();
    if (_outbox.isEmpty) await _uploadDirty();
  }

  Future<void> _enqueue(PendingOp op) => _outbox.add(op);

  /// Drops queued creates and edits for documents that are now being deleted:
  /// the server never saw them, so there is nothing to undo there. The
  /// delete that follows still runs, in case a create was in flight when its
  /// call timed out and landed after all.
  Future<void> _cancelPendingFor(List<String> docIds) => _outbox.mutate(
        (ops) => ops.removeWhere((o) =>
            docIds.contains(o.args['docId']) &&
            (o.kind == 'set' || o.kind == 'update' || o.kind == 'promote')),
      );

  Future<void> _evictContent(NotePage page) async {
    final fileId = page.driveFileId;
    if (fileId != null) await _content.evict(fileId);
    await _content.evict(PageContentRepository.localKeyFor(page.id));
  }

  /// One op, against the server. Throws to say "not now".
  Future<void> _perform(PendingOp op) async {
    final a = op.args;
    switch (op.kind) {
      case 'set':
        await _db.set(asStringOr(a['path']), asMap(a['data']) ?? const {});
      case 'update':
        await _db.update(asStringOr(a['path']), asMap(a['data']) ?? const {});
      case 'promote':
        final notebookId = asStringOr(a['notebookId']);
        final pageId = asStringOr(a['pageId']);
        final fileId = await _content.promote(
            asStringOr(a['localKey']), asStringOr(a['name']));
        await _db.update(_pageDoc(notebookId, pageId), {'driveFileId': fileId});
        final known = index.knownPage(notebookId, pageId);
        if (known != null) index.putPage(known.copyWith(driveFileId: fileId));
      case 'deletePage':
        final fileId = asString(a['fileId']);
        if (fileId != null) {
          try {
            await _content.delete(fileId);
          } catch (_) {}
        }
        await _db.delete(
            _pageDoc(asStringOr(a['notebookId']), asStringOr(a['pageId'])));
      case 'deleteSection':
        await _deleteSectionOnServer(
            asStringOr(a['notebookId']), asStringOr(a['sectionId']));
      case 'deleteNotebook':
        await _deleteNotebookOnServer(asStringOr(a['notebookId']));
      default:
        // An op from a newer build than this one. Nothing to do with it.
        return;
    }
  }

  Future<void> _deleteSectionOnServer(
      String notebookId, String sectionId) async {
    final pages = await _db.fetchCollection(_pagesPath(notebookId),
        where: MarioFilter.eq('sectionId', sectionId));
    for (final p in pages) {
      final fileId = p.data['driveFileId'] as String?;
      if (fileId != null) {
        try {
          await _content.delete(fileId);
        } catch (_) {}
      }
      await _forgetAiArtifacts(notebookId, p.id);
      await _db.delete(p.path);
    }
    await _db.delete(_sectionDoc(notebookId, sectionId));
  }

  Future<void> _deleteNotebookOnServer(String id) async {
    final pages = await _db.fetchCollection(_pagesPath(id));
    for (final p in pages) {
      final fileId = p.data['driveFileId'] as String?;
      if (fileId != null) {
        try {
          await _content.delete(fileId);
        } catch (_) {}
      }
      await _db.delete(p.path);
    }
    final sections = await _db.fetchCollection(_sectionsPath(id));
    for (final s in sections) {
      await _db.delete(s.path);
    }
    await _db.delete(_notebookDoc(id));
  }

  /// Whether a failure can pass, or never will.
  ///
  /// Read off the message, because the two backends and Drive throw four
  /// unrelated exception types for the same conditions. A rate limit is a
  /// 403 on Drive, so it is checked before "403 means forbidden".
  static OpFailure classifyFailure(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('ratelimit') ||
        text.contains('rate limit') ||
        text.contains('429') ||
        text.contains('quota')) {
      return OpFailure.retry;
    }
    if (text.contains('not_found') ||
        text.contains('not found') ||
        text.contains('404')) {
      return OpFailure.drop; // already gone: as good as done
    }
    if (text.contains('permission_denied') ||
        text.contains('permission denied') ||
        text.contains('403')) {
      return OpFailure.drop;
    }
    return OpFailure.retry;
  }

  void _uploadDirtySoon() {
    if (_disposed) return;
    _dirtyTimer?.cancel();
    _dirtyTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_uploadDirty());
    });
  }

  Future<void> _uploadDirty() async {
    try {
      await _content.uploadDirty();
    } catch (_) {
      // Still offline for Drive; the next settled op or poll tries again.
    }
  }

  /// A save that failed with nothing else queued has no op to ride on, so
  /// dirty pages are also checked on a slow clock while the app is open.
  void _startDirtyPoll() {
    if (_disposed || _dirtyPoll != null) return;
    _dirtyPoll = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (await _content.hasDirty()) await _uploadDirty();
    });
  }

  void dispose() {
    _disposed = true;
    _dirtyTimer?.cancel();
    _dirtyPoll?.cancel();
    _settledSub?.cancel();
    _outbox.dispose();
    index.dispose();
  }

  Map<String, dynamic> _emptyPageContent(String title) =>
      _pageContent(afe.Document.blank(withInitialText: true), title);

  /// The Drive payload for a new page: the document, plus the title and
  /// creation time the editor and the exporters read back.
  Map<String, dynamic> _pageContent(afe.Document document, String title) => {
        ...document.toJson(),
        'title': title,
        'createdAt': DateTime.now().toIso8601String(),
      };
}
