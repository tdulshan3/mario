/// SectionPanel — list of sections inside the selected notebook, styled to
/// match NotebookPanel. Auto-selects the first section so the page list is
/// never left dangling.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/section.dart';
import '../../ui/colors.dart';
import '../../ui/widgets/panel_header.dart';
import 'dialogs/notebook_dialog.dart';
import 'dialogs/text_input_dialog.dart';
import 'shell_state.dart';

class SectionPanel extends ConsumerStatefulWidget {
  const SectionPanel({super.key, this.onCollapse});

  final VoidCallback? onCollapse;

  @override
  ConsumerState<SectionPanel> createState() => _SectionPanelState();
}

class _SectionPanelState extends ConsumerState<SectionPanel> {
  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        isDark ? MarioColors.surfaceVariantDark : MarioColors.surfaceVariant;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;

    final notebookId = selection.notebookId;

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(title: 'Sections', onCollapse: widget.onCollapse),
          Expanded(
            child: notebookId == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Select a notebook',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12, color: muted),
                      ),
                    ),
                  )
                : _SectionList(notebookId: notebookId),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: TextButton.icon(
              onPressed: notebookId == null
                  ? null
                  : () => _create(context, notebookId),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New section'),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(36),
                padding:
                    const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, String notebookId) async {
    final result = await showNotebookDialog(
      context,
      title: 'New section',
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
    ref.read(selectionProvider.notifier).selectSection(id);
  }
}

class _SectionList extends ConsumerStatefulWidget {
  const _SectionList({required this.notebookId});
  final String notebookId;

  @override
  ConsumerState<_SectionList> createState() => _SectionListState();
}

class _SectionListState extends ConsumerState<_SectionList> {
  @override
  Widget build(BuildContext context) {
    final sectionsAsync = ref.watch(sectionsStreamProvider(widget.notebookId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    final selection = ref.watch(selectionProvider);

    return sectionsAsync.when(
      loading: () => const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child:
            Text('$e', style: GoogleFonts.inter(fontSize: 12, color: muted)),
      ),
      data: (sections) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final ids = sections.map((s) => s.id).toSet();
          final current = ref.read(selectionProvider).sectionId;
          if (current == null || !ids.contains(current)) {
            if (sections.isNotEmpty) {
              ref
                  .read(selectionProvider.notifier)
                  .selectSection(sections.first.id);
            }
          }
        });
        if (sections.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No sections yet.\nClick + below to create one.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: muted),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: sections.length,
          itemBuilder: (context, i) {
            final s = sections[i];
            final selected = s.id == selection.sectionId;
            return _SectionTile(
              section: s,
              selected: selected,
              onTap: () =>
                  ref.read(selectionProvider.notifier).selectSection(s.id),
              onMenu: (action) => _handleAction(context, s, action),
            );
          },
        );
      },
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    Section section,
    _SectionAction action,
  ) async {
    switch (action) {
      case _SectionAction.rename:
        final result = await showNotebookDialog(
          context,
          title: 'Edit section',
          submitLabel: 'Save',
          initialName: section.name,
          initialColorIndex: section.colorIndex,
        );
        if (result == null) return;
        await ref.read(syncServiceProvider).updateSection(
              section.copyWith(
                name: result.name,
                colorIndex: result.colorIndex,
              ),
            );
      case _SectionAction.delete:
        final ok = await showConfirmDialog(
          context,
          title: 'Delete "${section.name}"?',
          message: 'All pages inside this section will be deleted.',
        );
        if (!ok) return;
        await ref
            .read(syncServiceProvider)
            .deleteSection(section.notebookId, section.id);
        ref
            .read(selectionProvider.notifier)
            .clearForDeletedSection(section.id);
    }
  }
}

enum _SectionAction { rename, delete }

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.selected,
    required this.onTap,
    required this.onMenu,
  });

  final Section section;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<_SectionAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? MarioColors.onSurfaceDark : MarioColors.onSurface;
    final color =
        MarioColors.labelPalette[section.colorIndex.clamp(0, 5)];
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
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Container(
                  height: 24,
                  width: 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    section.name,
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
    final result = await showMenu<_SectionAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(
            value: _SectionAction.rename, child: Text('Rename / recolor')),
        PopupMenuItem(value: _SectionAction.delete, child: Text('Delete')),
      ],
    );
    if (result != null) onMenu(result);
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onSelected});
  final ValueChanged<_SectionAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SectionAction>(
      onSelected: onSelected,
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz, size: 16),
      itemBuilder: (_) => const [
        PopupMenuItem(
            value: _SectionAction.rename, child: Text('Rename / recolor')),
        PopupMenuItem(value: _SectionAction.delete, child: Text('Delete')),
      ],
      padding: EdgeInsets.zero,
      iconSize: 16,
    );
  }
}
