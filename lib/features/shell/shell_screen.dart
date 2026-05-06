/// ShellScreen — three-panel OneNote-style layout (notebooks | sections+pages | canvas).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/colors.dart';
import '../../ui/widgets/resizable_panel.dart';
import 'notebook_panel.dart';
import 'page_panel.dart';
import 'shell_state.dart';
import 'toolbar.dart';

class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const ShellToolbar(),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          ResizablePanel(initialWidth: 200, child: NotebookPanel()),
          ResizablePanel(initialWidth: 250, child: PagePanel()),
          Expanded(child: _CanvasPlaceholder()),
        ],
      ),
    );
  }
}

class _CanvasPlaceholder extends ConsumerWidget {
  const _CanvasPlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted =
        isDark ? MarioColors.onSurfaceMutedDark : MarioColors.onSurfaceMuted;

    final pageId = selection.pageId;
    final notebookId = selection.notebookId;
    final sectionId = selection.sectionId;

    final page = (notebookId != null && sectionId != null)
        ? (ref
                .watch(pagesStreamProvider(
                    (notebookId: notebookId, sectionId: sectionId)))
                .valueOrNull ??
            const [])
            .where((p) => p.id == pageId)
            .firstOrNull
        : null;

    return Container(
      color: isDark ? MarioColors.surfaceDark : MarioColors.surface,
      child: page == null
          ? Center(
              child: Text(
                'Select a page to start writing',
                style: GoogleFonts.inter(color: muted, fontSize: 14),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.title,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Last edited ${_formatTime(page.updatedAt)}',
                    style: GoogleFonts.inter(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Canvas comes online in Sprint 3 — AppFlowy editor will mount here.',
                    style: GoogleFonts.inter(fontSize: 14, color: muted),
                  ),
                ],
              ),
            ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
