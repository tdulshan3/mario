/// Shell providers — Firestore-backed streams + selection state for the 3-panel UI.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../core/models/section.dart';
import '../../core/services/sync_service.dart';
import '../auth/auth_notifier.dart';

final syncServiceProvider = Provider<SyncService>((ref) => GetIt.I<SyncService>());

/// Notebooks owned-by or shared-with the current user.
final notebooksStreamProvider = StreamProvider<List<Notebook>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.watch(syncServiceProvider).watchNotebooks(user.uid);
});

/// Sections inside a notebook.
final sectionsStreamProvider =
    StreamProvider.family<List<Section>, String>((ref, notebookId) {
  return ref.watch(syncServiceProvider).watchSections(notebookId);
});

/// Pages inside a section. Keyed on (notebookId, sectionId).
final pagesStreamProvider = StreamProvider.family<List<NotePage>,
    ({String notebookId, String sectionId})>((ref, key) {
  return ref
      .watch(syncServiceProvider)
      .watchPages(key.notebookId, key.sectionId);
});

class Selection {
  final String? notebookId;
  final String? sectionId;
  final String? pageId;

  const Selection({this.notebookId, this.sectionId, this.pageId});

  Selection copyWith({
    String? notebookId,
    String? sectionId,
    String? pageId,
    bool clearSection = false,
    bool clearPage = false,
  }) =>
      Selection(
        notebookId: notebookId ?? this.notebookId,
        sectionId: clearSection ? null : (sectionId ?? this.sectionId),
        pageId: clearPage ? null : (pageId ?? this.pageId),
      );
}

class SelectionNotifier extends Notifier<Selection> {
  @override
  Selection build() => const Selection();

  void selectNotebook(String id) =>
      state = Selection(notebookId: id);

  void selectSection(String id) =>
      state = state.copyWith(sectionId: id, clearPage: true);

  void selectPage(String id) =>
      state = state.copyWith(pageId: id);

  void clearForDeletedNotebook(String id) {
    if (state.notebookId == id) state = const Selection();
  }

  void clearForDeletedSection(String id) {
    if (state.sectionId == id) {
      state = state.copyWith(clearSection: true, clearPage: true);
    }
  }

  void clearForDeletedPage(String id) {
    if (state.pageId == id) state = state.copyWith(clearPage: true);
  }
}

final selectionProvider =
    NotifierProvider<SelectionNotifier, Selection>(SelectionNotifier.new);
