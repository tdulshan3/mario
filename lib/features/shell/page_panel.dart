/// PagePanel — list of pages inside the selected section, styled to match
/// NotebookPanel. Section selection lives in SectionPanel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:get_it/get_it.dart';

import '../../core/models/note_page.dart';
import '../../core/services/drive_service.dart';
import '../../ui/colors.dart';
import '../../ui/widgets/panel_header.dart';
import '../export/markdown_exporter.dart';
import '../export/pdf_exporter.dart';
import 'dialogs/text_input_dialog.dart';
import 'shell_state.dart';

class PagePanel extends ConsumerWidget {
  const PagePanel({super.key, this.onCollapse});

  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        isDark ? MarioColors.surfaceVariantDark : MarioColors.surfaceVariant;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;

    final notebookId = selection.notebookId;
    final sectionId = selection.sectionId;

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(title: 'Pages', onCollapse: onCollapse),
          Expanded(
            child: (notebookId == null || sectionId == null)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        notebookId == null
                            ? 'Select a notebook'
                            : 'Select a section',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12, color: muted),
                      ),
                    ),
                  )
                : _PageList(notebookId: notebookId, sectionId: sectionId),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: TextButton.icon(
              onPressed: (notebookId == null || sectionId == null)
                  ? null
                  : () => _createPage(context, ref, notebookId, sectionId),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New page'),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;

    final pagesAsync = ref.watch(pagesStreamProvider(
        (notebookId: widget.notebookId, sectionId: widget.sectionId)));

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
                'No pages yet.\nClick + below to create one.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: muted),
              ),
            ),
          );
        }
        final selection = ref.watch(selectionProvider);
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
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
    final fg = isDark ? MarioColors.onSurfaceDark : MarioColors.onSurface;
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
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        page.title,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: fg,
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
                _MenuButton(onSelected: onMenu),
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

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onSelected});
  final ValueChanged<_PageAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PageAction>(
      onSelected: onSelected,
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz, size: 16),
      itemBuilder: (_) => const [
        PopupMenuItem(value: _PageAction.rename, child: Text('Rename')),
        PopupMenuItem(
            value: _PageAction.exportMd, child: Text('Export as Markdown')),
        PopupMenuItem(
            value: _PageAction.exportPdf, child: Text('Export as PDF')),
        PopupMenuItem(value: _PageAction.delete, child: Text('Delete')),
      ],
      padding: EdgeInsets.zero,
      iconSize: 16,
    );
  }
}

