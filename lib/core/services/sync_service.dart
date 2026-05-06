/// SyncService — Firestore listeners + Drive content I/O for the notebook hierarchy.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/note_page.dart';
import '../models/notebook.dart';
import '../models/section.dart';
import 'drive_service.dart';

class SyncService {
  SyncService(this._db, this._drive);
  final FirebaseFirestore _db;
  final DriveService _drive;

  CollectionReference<Map<String, dynamic>> get _notebooks =>
      _db.collection('notebooks');

  // ---------- Watches ----------

  Stream<List<Notebook>> watchNotebooks(String uid) => _notebooks
      .where('memberUids', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs
          .map((d) => Notebook.fromMap(d.id, d.data()))
          .toList(growable: false));

  Stream<List<Section>> watchSections(String notebookId) => _notebooks
      .doc(notebookId)
      .collection('sections')
      .orderBy('order')
      .snapshots()
      .map((s) => s.docs
          .map((d) => Section.fromMap(d.id, d.data()))
          .toList(growable: false));

  Stream<List<NotePage>> watchPages(String notebookId, String sectionId) =>
      _notebooks
          .doc(notebookId)
          .collection('pages')
          .where('sectionId', isEqualTo: sectionId)
          .orderBy('order')
          .snapshots()
          .map((s) => s.docs
              .map((d) => NotePage.fromMap(d.id, d.data()))
              .toList(growable: false));

  // ---------- Notebooks ----------

  Future<String> createNotebook(Notebook nb) async {
    final ref = await _notebooks.add({
      ...nb.toMap(),
      'memberUids': [nb.ownerId, ...nb.collaboratorUids],
    });
    return ref.id;
  }

  Future<void> updateNotebook(Notebook nb) =>
      _notebooks.doc(nb.id).update(nb.toMap());

  Future<void> deleteNotebook(String id) async {
    final pagesSnap =
        await _notebooks.doc(id).collection('pages').get();
    for (final p in pagesSnap.docs) {
      final fileId = p.data()['driveFileId'] as String?;
      if (fileId != null) {
        try {
          await _drive.deleteFile(fileId);
        } catch (_) {}
      }
      await p.reference.delete();
    }
    final sectionsSnap = await _notebooks.doc(id).collection('sections').get();
    for (final s in sectionsSnap.docs) {
      await s.reference.delete();
    }
    await _notebooks.doc(id).delete();
  }

  // ---------- Sections ----------

  Future<String> createSection(Section section) async {
    final ref = await _notebooks
        .doc(section.notebookId)
        .collection('sections')
        .add(section.toMap());
    return ref.id;
  }

  Future<void> updateSection(Section section) => _notebooks
      .doc(section.notebookId)
      .collection('sections')
      .doc(section.id)
      .update(section.toMap());

  Future<void> deleteSection(String notebookId, String sectionId) async {
    final pagesSnap = await _notebooks
        .doc(notebookId)
        .collection('pages')
        .where('sectionId', isEqualTo: sectionId)
        .get();
    for (final p in pagesSnap.docs) {
      final fileId = p.data()['driveFileId'] as String?;
      if (fileId != null) {
        try {
          await _drive.deleteFile(fileId);
        } catch (_) {}
      }
      await p.reference.delete();
    }
    await _notebooks
        .doc(notebookId)
        .collection('sections')
        .doc(sectionId)
        .delete();
  }

  // ---------- Pages ----------

  Future<String> createPage(NotePage page) async {
    String? driveFileId;
    try {
      driveFileId = await _drive.createPageFile(
        'page-${DateTime.now().millisecondsSinceEpoch}',
        _emptyPageContent(page.title),
      );
    } catch (_) {
      // Drive may be unavailable (e.g. tests); page is still created.
    }
    final pageWithFile = page.copyWith(driveFileId: driveFileId);
    final ref = await _notebooks
        .doc(page.notebookId)
        .collection('pages')
        .add(pageWithFile.toMap());
    return ref.id;
  }

  Future<void> updatePage(NotePage page) => _notebooks
      .doc(page.notebookId)
      .collection('pages')
      .doc(page.id)
      .update(page.toMap());

  Future<void> deletePage(NotePage page) async {
    if (page.driveFileId != null) {
      try {
        await _drive.deleteFile(page.driveFileId!);
      } catch (_) {}
    }
    await _notebooks
        .doc(page.notebookId)
        .collection('pages')
        .doc(page.id)
        .delete();
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
