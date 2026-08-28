/// NavTree — single sidebar that combines what used to be the Sections and
/// Pages panels. Each section is an expandable group containing its pages.
///
/// Replaces SectionPanel + PagePanel; the user goes from four columns to
/// rail + tree + editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../core/models/section.dart';
import '../../core/services/asset_sync_service.dart';
import '../../core/services/page_content_repository.dart';
import '../../ui/colors.dart';
import '../../ui/widgets/mario_loader.dart';
import '../export/markdown_exporter.dart';
import '../export/pdf_exporter.dart';
import 'dialogs/notebook_dialog.dart';
import 'dialogs/text_input_dialog.dart';
import 'shell_state.dart';

class NavTree extends ConsumerStatefulWidget {
  const NavTree({super.key, this.onCollapse});

  final VoidCallback? onCollapse;

  @override
  ConsumerState<NavTree> createState() => _NavTreeState();
}

class _NavTreeState extends ConsumerState<NavTree> {
  /// Section IDs that are currently expanded. Sections default to expanded;
  /// flipping the chevron collapses just that section's pages.
  final Set<String> _collapsedSections = {};

  void _toggleSection(String id) {
    setState(() {
      if (_collapsedSections.contains(id)) {
        _collapsedSections.remove(id);
      } else {
        _collapsedSections.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selection = ref.watch(selectionProvider);
    final notebooks =
        ref.watch(notebooksStreamProvider).valueOrNull ?? const [];
    final notebook = notebooks
        .where((n) => n.id == selection.notebookId)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(notebook: notebook, onCollapse: widget.onCollapse),
          Expanded(
            child: notebook == null
                ? _EmptyHint(
                    text: 'Pick a notebook from the rail to see its sections.',
                  )
                : _SectionList(
                    notebookId: notebook.id,
                    collapsedSections: _collapsedSections,
                    onToggleSection: _toggleSection,
                  ),
          ),
          if (notebook != null)
            _Footer(notebookId: notebook.id, sectionId: selection.sectionId),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.notebook, this.onCollapse});
  final Notebook? notebook;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = notebook?.color ?? scheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 10),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notebook?.name ?? 'No notebook',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (onCollapse != null)
            IconButton(
              tooltip: 'Collapse sidebar',
              onPressed: onCollapse,
              icon: const Icon(Icons.chevron_left, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _SectionList extends ConsumerStatefulWidget {
  const _SectionList({
    required this.notebookId,
    required this.collapsedSections,
    required this.onToggleSection,
  });
  final String notebookId;
  final Set<String> collapsedSections;
  final ValueChanged<String> onToggleSection;

  @override
  ConsumerState<_SectionList> createState() => _SectionListState();
}

class _SectionListState extends ConsumerState<_SectionList> {
  @override
  Widget build(BuildContext context) {
    final sectionsAsync =
        ref.watch(sectionsStreamProvider(widget.notebookId));
    final scheme = Theme.of(context).colorScheme;

    return sectionsAsync.when(
      loading: () => const Center(child: MarioLoader(size: 18)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('$e',
            style: GoogleFonts.inter(
                fontSize: 12, color: scheme.onSurfaceVariant)),
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
          return _EmptyHint(
            text:
                'No sections yet.\nUse + below to create your first section.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          itemCount: sections.length,
          itemBuilder: (context, i) {
            final s = sections[i];
            final expanded = !widget.collapsedSections.contains(s.id);
            return _SectionGroup(
              section: s,
              expanded: expanded,
              onToggle: () => widget.onToggleSection(s.id),
              onMenu: (a) => _handleSectionAction(context, s, a),
            );
          },
        );
      },
    );
  }

  Future<void> _handleSectionAction(
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
        ref.read(selectionProvider.notifier).clearForDeletedSection(section.id);
    }
  }
}

enum _SectionAction { rename, delete }

class _SectionGroup extends ConsumerWidget {
  const _SectionGroup({
    required this.section,
    required this.expanded,
    required this.onToggle,
    required this.onMenu,
  });

  final Section section;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<_SectionAction> onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selection = ref.watch(selectionProvider);
    final isActiveSection = section.id == selection.sectionId;
    final color = MarioColors.labelPalette[section.colorIndex.clamp(0, 5)];

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                ref
                    .read(selectionProvider.notifier)
                    .selectSection(section.id);
                if (!expanded) onToggle();
              },
              onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    InkWell(
                      onTap: onToggle,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: AnimatedRotation(
                          duration: const Duration(milliseconds: 150),
                          turns: expanded ? 0.0 : -0.25,
                          child: Icon(
                            Icons.expand_more,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        section.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: isActiveSection
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: scheme.onSurface,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    _MenuButton(
                      onSelected: onMenu,
                      items: const [
                        ('Rename / recolor', _SectionAction.rename),
                        ('Delete', _SectionAction.delete),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _PageList(
              notebookId: section.notebookId,
              sectionId: section.id,
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
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

class _PageList extends ConsumerStatefulWidget {
  const _PageList({required this.notebookId, required this.sectionId});
  final String notebookId;
  final String sectionId;

  @override
  ConsumerState<_PageList> createState() => _PageListState();
}

class _PageListState extends ConsumerState<_PageList> {
  @override
  Widget build(BuildContext context) {
    final pagesAsync = ref.watch(pagesStreamProvider(
        (notebookId: widget.notebookId, sectionId: widget.sectionId)));
    final scheme = Theme.of(context).colorScheme;
    final selection = ref.watch(selectionProvider);

    return pagesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: MarioLoader(size: 18)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 36),
        child: Text('$e',
            style: GoogleFonts.inter(
                fontSize: 11, color: scheme.error)),
      ),
      data: (pages) {
        if (pages.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(36, 2, 8, 6),
            child: Text(
              'No pages yet',
              style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(left: 22, right: 4, bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in pages)
                _PageTile(
                  page: p,
                  selected: p.id == selection.pageId,
                  onTap: () => ref
                      .read(selectionProvider.notifier)
                      .selectPage(
                        p.id,
                        sectionId: p.sectionId,
                        notebookId: p.notebookId,
                      ),
                  onMenu: (a) => _handlePageAction(context, p, a),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handlePageAction(
    BuildContext context,
    NotePage page,
    _PageAction action,
  ) async {
    switch (action) {
      case _PageAction.rename:
        final title = await showTextInputDialog(
          context,
          title: 'Rename page',
          label: 'Title',
          submitLabel: 'Save',
          initialValue: page.title,
        );
        if (title == null) return;
        await ref.read(syncServiceProvider).updatePage(
              page.copyWith(title: title, updatedAt: DateTime.now()),
            );
      case _PageAction.exportMd:
        await MarkdownExporter(
                GetIt.I<PageContentRepository>(), GetIt.I<AssetSyncService>())
            .exportPageToFile(context, page);
      case _PageAction.exportPdf:
        await PdfExporter(
                GetIt.I<PageContentRepository>(), GetIt.I<AssetSyncService>())
            .exportPageToFile(context, page);
      case _PageAction.delete:
        final ok = await showConfirmDialog(
          context,
          title: 'Delete "${page.title}"?',
          message: 'This page will be permanently deleted.',
        );
        if (!ok) return;
        await ref.read(syncServiceProvider).deletePage(page);
        ref.read(selectionProvider.notifier).clearForDeletedPage(page.id);
    }
  }
}

enum _PageAction { rename, exportMd, exportPdf, delete }

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.page,
    required this.selected,
    required this.onTap,
    required this.onMenu,
  });

  final NotePage page;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<_PageAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 13,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    page.title.isEmpty ? 'Untitled' : page.title,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                _MenuButton<_PageAction>(
                  onSelected: onMenu,
                  items: const [
                    ('Rename', _PageAction.rename),
                    ('Export as Markdown', _PageAction.exportMd),
                    ('Export as PDF', _PageAction.exportPdf),
                    ('Delete', _PageAction.delete),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final result = await showMenu<_PageAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: _PageAction.rename, child: Text('Rename')),
        PopupMenuItem(
            value: _PageAction.exportMd, child: Text('Export as Markdown')),
        PopupMenuItem(
            value: _PageAction.exportPdf, child: Text('Export as PDF')),
        PopupMenuItem(value: _PageAction.delete, child: Text('Delete')),
      ],
    );
    if (result != null) onMenu(result);
  }
}

class _MenuButton<T> extends StatelessWidget {
  const _MenuButton({required this.onSelected, required this.items});
  final ValueChanged<T> onSelected;
  final List<(String, T)> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onSelected,
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz, size: 14),
      itemBuilder: (_) => [
        for (final (label, value) in items)
          PopupMenuItem(value: value, child: Text(label)),
      ],
      padding: EdgeInsets.zero,
      iconSize: 14,
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.notebookId, required this.sectionId});
  final String notebookId;
  final String? sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _FooterButton(
              icon: Icons.create_new_folder_outlined,
              label: 'Section',
              onPressed: () => _createSection(context, ref),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _FooterButton(
              icon: Icons.note_add_outlined,
              label: 'Page',
              onPressed:
                  sectionId == null ? null : () => _createPage(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createSection(BuildContext context, WidgetRef ref) async {
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

  Future<void> _createPage(BuildContext context, WidgetRef ref) async {
    final sid = sectionId;
    if (sid == null) return;
    final title = await showTextInputDialog(
      context,
      title: 'New page',
      label: 'Title',
      submitLabel: 'Create',
    );
    if (title == null) return;
    final pages = ref
            .read(pagesStreamProvider(
                (notebookId: notebookId, sectionId: sid)))
            .valueOrNull ??
        const [];
    final order = pages.length;
    final now = DateTime.now();
    final page = NotePage(
      id: '',
      sectionId: sid,
      notebookId: notebookId,
      title: title,
      order: order,
      createdAt: now,
      updatedAt: now,
    );
    final id = await ref.read(syncServiceProvider).createPage(page);
    ref.read(selectionProvider.notifier).selectPage(id);
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Material(
      color: enabled
          ? scheme.primary.withValues(alpha: 0.10)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: enabled
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
