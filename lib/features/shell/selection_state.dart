/// Selection state — which notebook / section / page is active in the shell.
///
/// Deliberately kept free of service/editor imports: the sync service pulls in
/// `appflowy_editor`, so depending on it here would make this trivial state
/// expensive to import and impossible to unit-test in isolation.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  void selectNotebook(String id) => state = Selection(notebookId: id);

  void selectSection(String id) =>
      state = state.copyWith(sectionId: id, clearPage: true);

  /// Selecting a page also aligns its owning section (and notebook) so the
  /// editor — which looks the page up within `sectionId`'s page stream — can
  /// resolve it. Without this, clicking a page in a section other than the
  /// active one sets `pageId` but leaves `sectionId` stale, so the page never
  /// opens. Args default to the current selection, keeping older call sites
  /// (where the section is already set) unchanged.
  void selectPage(String id, {String? sectionId, String? notebookId}) =>
      state = state.copyWith(
        pageId: id,
        sectionId: sectionId,
        notebookId: notebookId,
      );

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
