/// NotebookPanel — left sidebar with the live notebook list, create + context menus.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/notebook.dart';
import '../../ui/colors.dart';
import '../auth/auth_notifier.dart';
import 'dialogs/notebook_dialog.dart';
import 'dialogs/text_input_dialog.dart';
import 'shell_state.dart';

class NotebookPanel extends ConsumerWidget {
  const NotebookPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooksAsync = ref.watch(notebooksStreamProvider);
    final selection = ref.watch(selectionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        isDark ? MarioColors.surfaceVariantDark : MarioColors.surfaceVariant;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Notebooks',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: muted,
              ),
            ),
          ),
          Expanded(
            child: notebooksAsync.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('$e',
                    style: GoogleFonts.inter(fontSize: 12, color: muted)),
              ),
              data: (notebooks) {
                if (notebooks.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No notebooks yet.\nClick + below to create one.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12, color: muted),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: notebooks.length,
                  itemBuilder: (context, i) {
                    final nb = notebooks[i];
                    final selected = nb.id == selection.notebookId;
                    return _NotebookTile(
                      notebook: nb,
                      selected: selected,
                      onTap: () => ref
                          .read(selectionProvider.notifier)
                          .selectNotebook(nb.id),
                      onMenu: (action) =>
                          _handleAction(context, ref, nb, action),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New notebook'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(36),
              ),
            ),
          ),
        ],
      ),
    );
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

class _NotebookTile extends StatelessWidget {
  const _NotebookTile({
    required this.notebook,
    required this.selected,
    required this.onTap,
    required this.onMenu,
  });

  final Notebook notebook;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<_NotebookAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? MarioColors.onSurfaceDark : MarioColors.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? MarioColors.primary.withValues(alpha: isDark ? 0.18 : 0.32)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: notebook.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    notebook.name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _MenuButton(onSelected: onMenu),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final result = await showMenu<_NotebookAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(
            value: _NotebookAction.rename, child: Text('Rename / recolor')),
        PopupMenuItem(
            value: _NotebookAction.delete, child: Text('Delete')),
      ],
    );
    if (result != null) onMenu(result);
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onSelected});
  final ValueChanged<_NotebookAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_NotebookAction>(
      onSelected: onSelected,
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz, size: 16),
      itemBuilder: (_) => const [
        PopupMenuItem(
            value: _NotebookAction.rename, child: Text('Rename / recolor')),
        PopupMenuItem(
            value: _NotebookAction.delete, child: Text('Delete')),
      ],
      padding: EdgeInsets.zero,
      iconSize: 16,
    );
  }
}
