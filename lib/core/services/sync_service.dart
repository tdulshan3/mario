/// SyncService — notebook hierarchy CRUD on top of the [MarioFirestore] facade.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;

import '../models/note_page.dart';
import '../models/notebook.dart';
import '../models/section.dart';
import 'mario_firestore.dart';
import 'page_content_repository.dart';

class SyncService {
  SyncService(this._db, this._content);
  final MarioFirestore _db;
  final PageContentRepository _content;

  static const _root = 'notebooks';
  String _sectionsPath(String notebookId) => '$_root/$notebookId/sections';
  String _pagesPath(String notebookId) => '$_root/$notebookId/pages';
  String _notebookDoc(String id) => '$_root/$id';
  String _sectionDoc(String notebookId, String id) =>
      '$_root/$notebookId/sections/$id';
  String _pageDoc(String notebookId, String id) =>
      '$_root/$notebookId/pages/$id';

  // ---------- Watches ----------

  Stream<List<Notebook>> watchNotebooks(String uid) => _db
      .watchCollection(_root,
          where: MarioFilter.contains('memberUids', uid))
      .map((docs) => docs
          .map((d) => Notebook.fromMap(d.id, d.data))
          .toList(growable: false));

  Stream<List<Section>> watchSections(String notebookId) => _db
      .watchCollection(_sectionsPath(notebookId), orderBy: 'order')
      .map((docs) => docs
          .map((d) => Section.fromMap(d.id, d.data))
          .toList(growable: false));

  Stream<List<NotePage>> watchPages(String notebookId, String sectionId) => _db
      .watchCollection(
        _pagesPath(notebookId),
        where: MarioFilter.eq('sectionId', sectionId),
      )
      .map((docs) {
        final pages = docs
            .map((d) => NotePage.fromMap(d.id, d.data))
            .toList(growable: true);
        // Sort client-side to skip the (sectionId, order) composite index.
        // Firestore can serve `where(sectionId)` alone without one.
        pages.sort((a, b) => a.order.compareTo(b.order));
        return List<NotePage>.unmodifiable(pages);
      });

  // ---------- Notebooks ----------

  Future<String> createNotebook(Notebook nb) => _db.add(_root, {
        ...nb.toMap(),
        'memberUids': [nb.ownerId, ...nb.collaboratorUids],
      });

  Future<void> updateNotebook(Notebook nb) =>
      _db.update(_notebookDoc(nb.id), nb.toMap());

  Future<void> deleteNotebook(String id) async {
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

  // ---------- Sections ----------

  Future<String> createSection(Section section) =>
      _db.add(_sectionsPath(section.notebookId), section.toMap());

  Future<void> updateSection(Section section) => _db.update(
      _sectionDoc(section.notebookId, section.id), section.toMap());

  Future<void> deleteSection(String notebookId, String sectionId) async {
    final pages = await _db.fetchCollection(_pagesPath(notebookId),
        where: MarioFilter.eq('sectionId', sectionId));
    for (final p in pages) {
      final fileId = p.data['driveFileId'] as String?;
      if (fileId != null) {
        try {
          await _content.delete(fileId);
        } catch (_) {}
      }
      await _db.delete(p.path);
    }
    await _db.delete(_sectionDoc(notebookId, sectionId));
  }

  // ---------- Pages ----------

  Future<String> createPage(NotePage page) async {
    String? driveFileId;
    try {
      driveFileId = await _content.create(
        'page-${DateTime.now().millisecondsSinceEpoch}',
        _emptyPageContent(page.title),
      );
    } catch (_) {}
    final pageWithFile = page.copyWith(driveFileId: driveFileId);
    return _db.add(_pagesPath(page.notebookId), pageWithFile.toMap());
  }

  Future<void> updatePage(NotePage page) =>
      _db.update(_pageDoc(page.notebookId, page.id), page.toMap());

  Future<void> deletePage(NotePage page) async {
    if (page.driveFileId != null) {
      try {
        await _content.delete(page.driveFileId!);
      } catch (_) {}
    }
    await _db.delete(_pageDoc(page.notebookId, page.id));
  }

  Map<String, dynamic> _emptyPageContent(String title) {
    final doc = afe.Document.blank(withInitialText: true).toJson();
    return {
      ...doc,
      'title': title,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }
}
