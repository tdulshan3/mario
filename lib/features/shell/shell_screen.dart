/// ShellScreen — modern three-zone layout:
///   - 60px notebook rail (icon avatars, always visible)
///   - 280px collapsible nav tree (sections expanded with pages nested)
///   - editor canvas (everything else)
///
/// Replaces the older four-column OneNote-style sidebar set. The rail keeps
/// the notebook switcher one click away without dedicating a whole column to
/// it, and the tree merges what used to be separate Section + Page panels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/widgets/resizable_panel.dart';
import '../editor/editor_screen.dart';
import 'keyboard_shortcuts.dart';
import 'nav_tree.dart';
import 'notebook_rail.dart';
import 'shell_state.dart';
import 'toolbar.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  bool _treeCollapsed = false;

  void _toggleTree() {
    setState(() => _treeCollapsed = !_treeCollapsed);
  }

  @override
  Widget build(BuildContext context) {
    return GlobalShortcuts(
      child: Scaffold(
        appBar: const ShellToolbar(),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const NotebookRail(),
            if (_treeCollapsed)
              _CollapsedTreeStrip(onExpand: _toggleTree)
            else
              ResizablePanel(
                initialWidth: 280,
                minWidth: 220,
                maxWidth: 420,
                child: NavTree(onCollapse: _toggleTree),
              ),
            const Expanded(child: _EditorHost()),
          ],
        ),
      ),
    );
  }
}

/// Slim strip shown when the nav tree is collapsed; click to expand.
class _CollapsedTreeStrip extends StatelessWidget {
  const _CollapsedTreeStrip({required this.onExpand});
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 24,
      child: Material(
        color: scheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onExpand,
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: scheme.outlineVariant)),
            ),
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 10),
            child: Icon(Icons.chevron_right,
                size: 16, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _EditorHost extends ConsumerWidget {
  const _EditorHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selection = ref.watch(selectionProvider);

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
      color: scheme.surface,
      child: page == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_outlined,
                        size: 40, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 14),
                    Text(
                      'Pick a page to start writing',
                      style: GoogleFonts.spaceGrotesk(
                        color: scheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Notebook ▸ Section ▸ Page',
                      style: GoogleFonts.inter(
                          color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          : EditorScreen(key: ValueKey(page.id), page: page),
    );
  }
}
