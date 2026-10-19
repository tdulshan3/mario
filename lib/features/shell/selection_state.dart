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

  /// Whether the shell is on the recents home rather than in a notebook.
  ///
  /// Its own flag, not `pageId == null`. The design gives home a different
  /// *layout* — full width, no sidebar — and "a notebook is open but no page
  /// is" is a real third state that still needs the sidebar to pick one from.
  /// Starts true: the app opens on recents.
  final bool home;

  const Selection({
    this.notebookId,
    this.sectionId,
    this.pageId,
    this.home = true,
  });

  Selection copyWith({
    String? notebookId,
    String? sectionId,
    String? pageId,
    bool? home,
    bool clearSection = false,
    bool clearPage = false,
  }) =>
      Selection(
        notebookId: notebookId ?? this.notebookId,
        sectionId: clearSection ? null : (sectionId ?? this.sectionId),
        pageId: clearPage ? null : (pageId ?? this.pageId),
        home: home ?? this.home,
      );
}

class SelectionNotifier extends Notifier<Selection> {
  @override
  Selection build() => const Selection();

  void selectNotebook(String id) =>
      state = Selection(notebookId: id, home: false);

  /// [notebookId] moves the notebook along with it, for a section picked from
  /// a tree that shows every notebook at once (the desktop sidebar).
  void selectSection(String id, {String? notebookId}) => state = state.copyWith(
      sectionId: id, notebookId: notebookId, home: false, clearPage: true);

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
        home: false,
      );

  /// Back to the recents home. The notebook and section stay selected, so the
  /// strip can return to exactly where it was.
  void goHome() => state = state.copyWith(home: true);

  void clearForDeletedNotebook(String id) {
    if (state.notebookId == id) state = const Selection();
  }

  /// The page that was open is gone; fall back to home rather than to an
  /// empty editor.
  void closePage() => state = state.copyWith(clearPage: true, home: true);

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
