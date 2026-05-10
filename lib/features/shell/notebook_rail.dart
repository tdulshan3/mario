/// NotebookRail — slim vertical strip of notebook avatars (Discord / Linear
/// style). Replaces the old wide "Notebooks" sidebar panel. Selected notebook
/// gets a left-edge accent bar; bottom slot has a "+" to create a new one.
///
/// Right-click an avatar for rename / recolor / delete.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/notebook.dart';
import '../auth/auth_notifier.dart';
import 'dialogs/notebook_dialog.dart';
import 'dialogs/text_input_dialog.dart';
import 'shell_state.dart';

const double kRailWidth = 60;

class NotebookRail extends ConsumerWidget {
  const NotebookRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final notebooks =
        ref.watch(notebooksStreamProvider).valueOrNull ?? const [];
    final selectedId = ref.watch(selectionProvider).notebookId;

    return Container(
      width: kRailWidth,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: notebooks.length,
              itemBuilder: (context, i) {
                final nb = notebooks[i];
                return _NotebookAvatar(
                  notebook: nb,
                  selected: nb.id == selectedId,
                  onTap: () => ref
                      .read(selectionProvider.notifier)
                      .selectNotebook(nb.id),
                  onMenu: (action) =>
                      _handleAction(context, ref, nb, action),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _RailIconButton(
              icon: Icons.add,
              tooltip: 'New notebook',
              onPressed: () => _create(context, ref),
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

class _NotebookAvatar extends StatelessWidget {
  const _NotebookAvatar({
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
    final scheme = Theme.of(context).colorScheme;
    final initial = notebook.name.trim().isEmpty
        ? '·'
        : notebook.name.trim()[0].toUpperCase();
    // Active state: subtle background tint + thin accent bar on the left.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Stack(
        children: [
          if (selected)
            Positioned(
              left: 0,
              top: 6,
              bottom: 6,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
              ),
            ),
          Center(
            child: Tooltip(
              message: notebook.name,
              waitDuration: const Duration(milliseconds: 400),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  onSecondaryTapDown: (d) =>
                      _showMenu(context, d.globalPosition),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: notebook.color.withValues(
                          alpha: selected ? 0.95 : 0.75),
                      borderRadius:
                          BorderRadius.circular(selected ? 12 : 20),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: notebook.color.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
        PopupMenuItem(value: _NotebookAction.delete, child: Text('Delete')),
      ],
    );
    if (result != null) onMenu(result);
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
