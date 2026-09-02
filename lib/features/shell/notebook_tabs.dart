/// NotebookTabBar — the Simple design's 35px notebook strip.
///
/// This file used to hold `NotebookRail`, a 60px vertical column of coloured
/// notebook avatars. The remodel turns that column on its side and strips the
/// colour out of it: notebooks are now plain text tabs along a 35px strip
/// under the top bar, the live one marked by a 2px accent underline and w600
/// — the same treatment a selected sidebar row gets on its leading edge.
///
/// Giving notebooks the horizontal strip is what frees the sidebar to be one
/// flat tree of sections and pages, with no picker card and no switcher
/// panel above it.
///
/// "Recent" leads the strip and is always present. It is the home screen —
/// selected whenever no page is open — so there is a way back to it from
/// inside a page, which a strip of notebooks alone would not provide.
///
/// The rail's full action set (create, rename, recolor, delete) is carried
/// over: right-click a tab for the menu, and the trailing `+` creates.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/notebook.dart';
import '../../ui/organic.dart';
import '../../ui/theme.dart';
import '../auth/auth_notifier.dart';
import 'dialogs/notebook_dialog.dart';
import 'dialogs/text_input_dialog.dart';
import 'shell_state.dart';

/// The strip's height, including the hairline along its bottom edge.
const double kNotebookTabsHeight = 35;

class NotebookTabBar extends ConsumerWidget {
  const NotebookTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = marioTokens(context);
    final notebooks =
        ref.watch(notebooksStreamProvider).valueOrNull ?? const <Notebook>[];
    final selection = ref.watch(selectionProvider);

    final onHome = selection.home;

    return Container(
      height: kNotebookTabsHeight,
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  MarioTab(
                    label: 'Recent',
                    selected: onHome,
                    onTap: () => ref.read(selectionProvider.notifier).goHome(),
                  ),
                  const SizedBox(width: 2),
                  for (final nb in notebooks) ...[
                    MarioTab(
                      label: nb.name,
                      selected: !onHome && nb.id == selection.notebookId,
                      onTap: () => ref
                          .read(selectionProvider.notifier)
                          .selectNotebook(nb.id),
                      onSecondaryTap: () => _showMenu(context, ref, nb),
                    ),
                    const SizedBox(width: 2),
                  ],
                ],
              ),
            ),
            Tooltip(
              message: 'New notebook',
              child: GestureDetector(
                onTap: () => _create(context, ref),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 28,
                  height: kNotebookTabsHeight - 1,
                  child: Icon(Icons.add, size: 16, color: t.mut),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMenu(
      BuildContext context, WidgetRef ref, Notebook nb) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? Offset.zero
        : box.localToGlobal(Offset(0, box.size.height));
    final result = await showMenu<_NotebookAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy,
        origin.dx,
        origin.dy,
      ),
      items: const [
        PopupMenuItem(
            value: _NotebookAction.rename, child: Text('Rename / recolor')),
        PopupMenuItem(value: _NotebookAction.delete, child: Text('Delete')),
      ],
    );
    if (result != null && context.mounted) {
      await _handleAction(context, ref, nb, result);
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final result = await showNotebookDialog(
      context,
      title: 'New notebook',
      submitLabel: 'Create',
    );
    if (result == null) return;
    final now = DateTime.now();
    final nb = Notebook(
      id: '',
      name: result.name,
      ownerId: user.uid,
      colorIndex: result.colorIndex,
      createdAt: now,
      updatedAt: now,
    );
    final id = await ref.read(syncServiceProvider).createNotebook(nb);
    ref.read(selectionProvider.notifier).selectNotebook(id);
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    Notebook nb,
    _NotebookAction action,
  ) async {
    switch (action) {
      case _NotebookAction.rename:
        final result = await showNotebookDialog(
          context,
          initialName: nb.name,
          initialColorIndex: nb.colorIndex,
          title: 'Edit notebook',
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
      case _NotebookAction.delete:
        final ok = await showConfirmDialog(
          context,
          title: 'Delete "${nb.name}"?',
          message:
              'All sections and pages inside this notebook will be permanently deleted.',
        );
        if (!ok) return;
        await ref.read(syncServiceProvider).deleteNotebook(nb.id);
        ref.read(selectionProvider.notifier).clearForDeletedNotebook(nb.id);
    }
  }
}

enum _NotebookAction { rename, delete }
