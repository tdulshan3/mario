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
