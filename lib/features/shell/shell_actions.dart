/// What the desktop shell does to notebooks, sections and pages.
///
/// The desktop window offers each of these from several places at once — the
/// sidebar's context menus, the toolbar, the page browser — so they live here
/// once instead of in each of them. They are the same flows the Material
/// shell runs (`nav_tree.dart`, `notebook_tabs.dart`, `shell_screen.dart`):
/// the same dialogs, the same sync-service writes, the same selection moves.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../core/models/section.dart';
import '../../core/services/asset_sync_service.dart';
import '../../core/services/page_content_repository.dart';
import '../auth/auth_notifier.dart';
import '../export/markdown_exporter.dart';
import '../export/pdf_exporter.dart';
import 'dialogs/notebook_dialog.dart';
import 'dialogs/text_input_dialog.dart';
import 'shell_state.dart';
import 'tree_order.dart';

// ── Create ────────────────────────────────────────────────────────────────

Future<void> createNotebook(BuildContext context, WidgetRef ref) async {
  final user = ref.read(authStateProvider).valueOrNull;
  if (user == null) return;
  final result = await showNotebookDialog(
    context,
    title: 'New Notebook',
    submitLabel: 'Create',
  );
  if (result == null) return;
  final now = DateTime.now();
  final id = await ref.read(syncServiceProvider).createNotebook(
        Notebook(
          id: '',
          name: result.name,
          ownerId: user.uid,
          colorIndex: result.colorIndex,
          createdAt: now,
          updatedAt: now,
        ),
      );
  ref.read(selectionProvider.notifier).selectNotebook(id);
}

Future<void> createSection(
  BuildContext context,
  WidgetRef ref,
  String notebookId,
) async {
  final result = await showNotebookDialog(
    context,
    title: 'New Section',
    submitLabel: 'Create',
  );
  if (result == null) return;
  final sections =
      ref.read(sectionsStreamProvider(notebookId)).valueOrNull ?? const [];
  final id = await ref.read(syncServiceProvider).createSection(
        Section(
          id: '',
          notebookId: notebookId,
          name: result.name,
          colorIndex: result.colorIndex,
          order: sections.length,
        ),
      );
  ref
      .read(selectionProvider.notifier)
      .selectSection(id, notebookId: notebookId);
}

Future<void> createPage(
  BuildContext context,
  WidgetRef ref, {
  required String notebookId,
  required String sectionId,
}) async {
  final title = await showTextInputDialog(
    context,
    title: 'New Page',
    label: 'Title',
    submitLabel: 'Create',
  );
  if (title == null) return;
  final pages = ref
          .read(pagesStreamProvider(
              (notebookId: notebookId, sectionId: sectionId)))
          .valueOrNull ??
      const [];
  final now = DateTime.now();
  final id = await ref.read(syncServiceProvider).createPage(
        NotePage(
          id: '',
          sectionId: sectionId,
          notebookId: notebookId,
          title: title,
          order: pages.length,
          createdAt: now,
          updatedAt: now,
        ),
      );
  ref
      .read(selectionProvider.notifier)
      .selectPage(id, sectionId: sectionId, notebookId: notebookId);
}

// ── Edit ──────────────────────────────────────────────────────────────────

Future<void> editNotebook(
  BuildContext context,
  WidgetRef ref,
  Notebook nb,
) async {
  final result = await showNotebookDialog(
    context,
    initialName: nb.name,
    initialColorIndex: nb.colorIndex,
    title: 'Edit Notebook',
    submitLabel: 'Save',
  );
  if (result == null) return;
  await ref.read(syncServiceProvider).updateNotebook(
        nb.copyWith(
          name: result.name,
          colorIndex: result.colorIndex,
          updatedAt: DateTime.now(),
        ),
      );
}

Future<void> editSection(
  BuildContext context,
  WidgetRef ref,
  Section section,
) async {
  final result = await showNotebookDialog(
    context,
    title: 'Edit Section',
    submitLabel: 'Save',
    initialName: section.name,
    initialColorIndex: section.colorIndex,
  );
  if (result == null) return;
  await ref.read(syncServiceProvider).updateSection(
        section.copyWith(name: result.name, colorIndex: result.colorIndex),
      );
}

Future<void> renamePage(
  BuildContext context,
  WidgetRef ref,
  NotePage page,
) async {
  final title = await showTextInputDialog(
    context,
    title: 'Rename Page',
    label: 'Title',
    submitLabel: 'Rename',
    initialValue: page.title,
  );
  if (title == null) return;
  await ref
      .read(syncServiceProvider)
      .updatePage(page.copyWith(title: title, updatedAt: DateTime.now()));
}

Future<void> exportPageAsMarkdown(BuildContext context, NotePage page) =>
    MarkdownExporter(
            GetIt.I<PageContentRepository>(), GetIt.I<AssetSyncService>())
        .exportPageToFile(context, page);

Future<void> exportPageAsPdf(BuildContext context, NotePage page) =>
    PdfExporter(GetIt.I<PageContentRepository>(), GetIt.I<AssetSyncService>())
        .exportPageToFile(context, page);

// ── Delete ────────────────────────────────────────────────────────────────

String _named(String name, String fallback) =>
    name.trim().isEmpty ? fallback : name.trim();

Future<void> deleteNotebook(
  BuildContext context,
  WidgetRef ref,
  Notebook nb,
) async {
  final ok = await showConfirmDialog(
    context,
    title: 'Delete “${_named(nb.name, 'Untitled')}”?',
    message: 'All sections and pages inside this notebook will be '
        'permanently deleted. You can’t undo this action.',
  );
  if (!ok) return;
  await ref.read(syncServiceProvider).deleteNotebook(nb.id);
  ref.read(selectionProvider.notifier).clearForDeletedNotebook(nb.id);
}

Future<void> deleteSection(
  BuildContext context,
  WidgetRef ref,
  Section section,
) async {
  final ok = await showConfirmDialog(
    context,
    title: 'Delete “${_named(section.name, 'Untitled')}”?',
    message: 'All pages inside this section will be permanently deleted. '
        'You can’t undo this action.',
  );
  if (!ok) return;
  await ref
      .read(syncServiceProvider)
      .deleteSection(section.notebookId, section.id);
  ref.read(selectionProvider.notifier).clearForDeletedSection(section.id);
}

Future<void> deletePage(
  BuildContext context,
  WidgetRef ref,
  NotePage page,
) async {
  final ok = await showConfirmDialog(
    context,
    title: 'Delete “${_named(page.title, 'Untitled')}”?',
    message: 'This page will be permanently deleted. '
        'You can’t undo this action.',
  );
  if (!ok) return;
  await ref.read(syncServiceProvider).deletePage(page);
  ref.read(selectionProvider.notifier).clearForDeletedPage(page.id);
}

// ── Reorder ───────────────────────────────────────────────────────────────

/// [dragged] moved to sit before or after [target]. Only the sections whose
/// place changed are written.
Future<void> reorderSections(
  WidgetRef ref,
  List<Section> sections,
  Section dragged,
  Section target, {
  required bool before,
}) async {
  final order = reorderedIds(
    [for (final s in sections) s.id],
    dragged.id,
    target.id,
    before: before,
  );
  final byId = {for (final s in sections) s.id: s};
  final writes =
      ordersToWrite(order, {for (final s in sections) s.id: s.order});
  final sync = ref.read(syncServiceProvider);
  for (final e in writes.entries) {
    await sync.updateSection(byId[e.key]!.copyWith(order: e.value));
  }
}

/// A page dropped on a section goes to the end of that section.
Future<void> movePageInto(WidgetRef ref, NotePage page, Section target) {
  final pages = ref
          .read(pagesStreamProvider(
              (notebookId: target.notebookId, sectionId: target.id)))
          .valueOrNull ??
      const <NotePage>[];
  return writePageOrder(
    ref,
    appendedIds([for (final p in pages) p.id], page.id),
    {for (final p in pages) p.id: p, page.id: page},
    sectionId: target.id,
    notebookId: target.notebookId,
  );
}

/// [dragged] dropped before or after [target], in [target]'s section.
Future<void> dropPageOnPage(
  WidgetRef ref,
  NotePage dragged,
  NotePage target, {
  required bool before,
  required List<NotePage> sectionPages,
}) async {
  if (dragged.id == target.id) return;
  final order = reorderedIds(
    [for (final p in sectionPages) p.id],
    dragged.id,
    target.id,
    before: before,
  );
  await writePageOrder(
    ref,
    order,
    {for (final p in sectionPages) p.id: p, dragged.id: dragged},
    sectionId: target.sectionId,
    notebookId: target.notebookId,
  );
}

/// Writes the orders that changed once [order] became the order of the pages
/// in [sectionId], moving any page that came from another section. The open
/// page can be the one that moved, so the selection follows it across.
Future<void> writePageOrder(
  WidgetRef ref,
  List<String> order,
  Map<String, NotePage> byId, {
  required String sectionId,
  required String notebookId,
}) async {
  final sync = ref.read(syncServiceProvider);
  final selection = ref.read(selectionProvider);
  for (var i = 0; i < order.length; i++) {
    final p = byId[order[i]];
    if (p == null) continue;
    if (p.order == i && p.sectionId == sectionId) continue;
    await sync.updatePage(p.copyWith(order: i, sectionId: sectionId));
    if (p.sectionId != sectionId && selection.pageId == p.id) {
      ref.read(selectionProvider.notifier).selectPage(
            p.id,
            sectionId: sectionId,
            notebookId: notebookId,
          );
    }
  }
}
