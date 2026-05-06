/// PagePanel — section tabs + page list, both backed by Firestore streams.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:get_it/get_it.dart';

import '../../core/models/note_page.dart';
import '../../core/models/section.dart';
import '../../core/services/drive_service.dart';
import '../../ui/colors.dart';
import '../export/markdown_exporter.dart';
import '../export/pdf_exporter.dart';
import 'dialogs/notebook_dialog.dart';
import 'dialogs/text_input_dialog.dart';
import 'shell_state.dart';

class PagePanel extends ConsumerWidget {
  const PagePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? MarioColors.surfaceDark : MarioColors.surface;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;

    final notebookId = selection.notebookId;
    if (notebookId == null) {
      return Container(
        color: bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Select a notebook',
              style: GoogleFonts.inter(fontSize: 13, color: muted),
            ),
          ),
        ),
      );
    }

    final sectionsAsync = ref.watch(sectionsStreamProvider(notebookId));

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: sectionsAsync.when(
              loading: () => const SizedBox(height: 40),
              error: (e, _) => SizedBox(
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('$e',
                        style:
                            GoogleFonts.inter(fontSize: 12, color: muted)),
                  ),
                ),
              ),
              data: (sections) => _SectionTabs(
                notebookId: notebookId,
                sections: sections,
              ),
            ),
          ),
          Expanded(
            child: _PageList(
              notebookId: notebookId,
              sectionId: selection.sectionId,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              onPressed: selection.sectionId == null
                  ? null
                  : () => _createPage(
                        context,
                        ref,
                        notebookId,
                        selection.sectionId!,
                      ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add page'),
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

  Future<void> _createPage(
    BuildContext context,
    WidgetRef ref,
    String notebookId,
    String sectionId,
  ) async {
    final title = await showTextInputDialog(
      context,
      title: 'New page',
      label: 'Title',
      submitLabel: 'Create',
    );
    if (title == null) return;
    final pages = ref
            .read(pagesStreamProvider(
                (notebookId: notebookId, sectionId: sectionId)))
            .valueOrNull ??
        const [];
    final order = pages.length;
    final now = DateTime.now();
    final page = NotePage(
      id: '',
      sectionId: sectionId,
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

class _SectionTabs extends ConsumerStatefulWidget {
  const _SectionTabs({required this.notebookId, required this.sections});
  final String notebookId;
  final List<Section> sections;

  @override
  ConsumerState<_SectionTabs> createState() => _SectionTabsState();
}

class _SectionTabsState extends ConsumerState<_SectionTabs> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelection());
  }

  @override
  void didUpdateWidget(covariant _SectionTabs old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelection());
  }

  void _ensureSelection() {
    if (!mounted) return;
    final selection = ref.read(selectionProvider);
    final ids = widget.sections.map((s) => s.id).toSet();
    if (selection.sectionId == null || !ids.contains(selection.sectionId)) {
      if (widget.sections.isNotEmpty) {
        ref
            .read(selectionProvider.notifier)
            .selectSection(widget.sections.first.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    if (widget.sections.isEmpty) {
      return SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                tooltip: 'New section',
                onPressed: () => _create(context),
                icon: const Icon(Icons.add, size: 16),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: widget.sections.length,
              itemBuilder: (context, i) {
                final s = widget.sections[i];
                final isSelected = s.id == selection.sectionId;
                return _SectionTab(
                  section: s,
                  selected: isSelected,
                  onTap: () => ref
                      .read(selectionProvider.notifier)
                      .selectSection(s.id),
                  onMenu: (action) => _handleAction(context, s, action),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'New section',
            onPressed: () => _create(context),
            icon: const Icon(Icons.add, size: 16),
          ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final result = await showNotebookDialog(
      context,
      title: 'New section',
      submitLabel: 'Create',
    );
    if (result == null) return;
    final order = widget.sections.length;
    final id = await ref.read(syncServiceProvider).createSection(
          Section(
            id: '',
            notebookId: widget.notebookId,
            name: result.name,
            colorIndex: result.colorIndex,
            order: order,
          ),
        );
    ref.read(selectionProvider.notifier).selectSection(id);
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
        ref.read(selectionProvider.notifier).clearForDeletedSection(section.id);
    }
  }
}

enum _SectionAction { rename, delete }

class _SectionTab extends StatelessWidget {
  const _SectionTab({
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
    final color =
        MarioColors.labelPalette[section.colorIndex.clamp(0, 5)];
    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? MarioColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              section.name,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
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
        PopupMenuItem(
            value: _SectionAction.delete, child: Text('Delete')),
      ],
    );
    if (result != null) onMenu(result);
  }
}

class _PageList extends ConsumerStatefulWidget {
  const _PageList({required this.notebookId, required this.sectionId});
  final String notebookId;
  final String? sectionId;

  @override
  ConsumerState<_PageList> createState() => _PageListState();
}

class _PageListState extends ConsumerState<_PageList> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;

    final sectionId = widget.sectionId;
    if (sectionId == null) {
      return Center(
        child: Text('No section selected',
            style: GoogleFonts.inter(fontSize: 13, color: muted)),
      );
    }

    final pagesAsync = ref.watch(pagesStreamProvider(
        (notebookId: widget.notebookId, sectionId: sectionId)));

    return pagesAsync.when(
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
      data: (pages) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final selection = ref.read(selectionProvider);
          final ids = pages.map((p) => p.id).toSet();
          if (selection.pageId == null || !ids.contains(selection.pageId)) {
            if (pages.isNotEmpty) {
              ref
                  .read(selectionProvider.notifier)
                  .selectPage(pages.first.id);
            }
          }
        });
        if (pages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No pages yet',
                style: GoogleFonts.inter(fontSize: 13, color: muted),
              ),
            ),
          );
        }
        final selection = ref.watch(selectionProvider);
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: pages.length,
          itemBuilder: (context, i) {
            final p = pages[i];
            final selected = p.id == selection.pageId;
            return _PageTile(
              page: p,
              selected: selected,
              onTap: () =>
                  ref.read(selectionProvider.notifier).selectPage(p.id),
              onMenu: (action) => _handleAction(context, p, action),
            );
          },
        );
      },
    );
  }

  Future<void> _handleAction(
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
        await MarkdownExporter(GetIt.I<DriveService>())
            .exportPageToFile(context, page);
      case _PageAction.exportPdf:
        await PdfExporter(GetIt.I<DriveService>())
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? MarioColors.primary.withValues(alpha: isDark ? 0.18 : 0.32)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page.title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(page.updatedAt),
                  style: GoogleFonts.inter(fontSize: 11, color: muted),
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

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return 'Today';
    }
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
