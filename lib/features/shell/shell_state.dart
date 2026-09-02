/// Shell providers — Firestore-backed streams + selection state for the 3-panel UI.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../core/models/section.dart';
import '../../core/services/sync_service.dart';
import '../auth/auth_notifier.dart';

// Selection state lives in its own service-free file so it stays unit-testable;
// re-exported here so existing `import 'shell_state.dart'` call sites are
// unaffected.
export 'selection_state.dart';

final syncServiceProvider =
    Provider<SyncService>((ref) => GetIt.I<SyncService>());

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

/// Whether the sidebar is collapsed to its strip.
///
/// Shell state rather than `_ShellScreenState`, because the artboard gives the
/// sidebar header no collapse control — it is search and `+`, nothing else —
/// so the only way in is Ctrl+\\, which is bound up in [GlobalShortcuts] well
/// above the widget that does the collapsing.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

/// One row of the recents home: a page, plus where it lives.
class RecentPage {
  const RecentPage({
    required this.page,
    required this.notebookName,
    required this.sectionId,
    required this.sectionName,
  });

  final NotePage page;
  final String notebookName;
  final String sectionId;
  final String sectionName;

  /// "2/4 · Entro" — the meta line under the title.
  String get breadcrumb => '$sectionName · $notebookName';
}

/// Every page the shell can see, newest edit first.
///
/// Assembled from the per-section streams rather than from a query of its
/// own: pages live under `notebooks/{id}/pages`, so "most recent across
/// everything" is a collection-group query with an index behind it, and this
/// composes what is already subscribed. Watching (not reading) each stream is
/// what keeps the list live — the same approach the command palette takes.
final recentPagesProvider = Provider<List<RecentPage>>((ref) {
  final notebooks = ref.watch(notebooksStreamProvider).valueOrNull ?? const [];
  final out = <RecentPage>[];

  for (final nb in notebooks) {
    final sections = ref.watch(sectionsStreamProvider(nb.id)).valueOrNull;
    if (sections == null) continue;
    for (final s in sections) {
      final pages = ref
          .watch(pagesStreamProvider((notebookId: nb.id, sectionId: s.id)))
          .valueOrNull;
      if (pages == null) continue;
      for (final p in pages) {
        out.add(RecentPage(
          page: p,
          notebookName: nb.name,
          sectionId: s.id,
          sectionName: s.name,
        ));
      }
    }
  }

  out.sort((a, b) => b.page.updatedAt.compareTo(a.page.updatedAt));
  return List<RecentPage>.unmodifiable(out);
});
