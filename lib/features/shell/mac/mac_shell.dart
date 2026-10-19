/// The desktop window: a macOS 27 window built from apple_ui.
///
///   sidebar     Recents, then every notebook as a folder of sections and
///               pages (mac_sidebar.dart); hide it from the toolbar or Ctrl+\
///   toolbar     the open page's title over where it lives; New Page, a New
///               menu, Ask Mario (the inspector), the account menu, and the
///               search field last, which narrows the sidebar (Return
///               opens the search panel with the same text)
///   content     the open page's editor, or the page table of the place
///               picked in the sidebar (mac_browser.dart)
///   inspector   the AI panel, on the right
///
/// It is the desktop counterpart of the Material `ShellScreen`, which the web
/// build keeps: same providers, same selection, same create and delete flows
/// (shell_actions.dart), same editor.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/note_page.dart';
import '../../../core/models/notebook.dart';
import '../../../core/models/section.dart';
import '../../ai/ai_side_panel.dart';
import '../../ai/ai_state.dart';
import '../../auth/auth_notifier.dart';
import '../../editor/editor_screen.dart';
import '../../search/global_search.dart';
import '../keyboard_shortcuts.dart';
import '../shell_actions.dart';
import '../shell_state.dart';
import 'mac_browser.dart';
import 'mac_sidebar.dart';
import 'mac_window_frame.dart';

/// The sidebar's width range, as a macOS sidebar allows it to be dragged.
const double _kSidebarMin = 200;
const double _kSidebarMax = 360;

class MacShellScreen extends ConsumerStatefulWidget {
  const MacShellScreen({super.key});

  @override
  ConsumerState<MacShellScreen> createState() => _MacShellScreenState();
}

class _MacShellScreenState extends ConsumerState<MacShellScreen> {
  String _filter = '';
  double _sidebarWidth = 240;

  void _toggleSidebar() =>
      ref.read(sidebarCollapsedProvider.notifier).update((c) => !c);

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(selectionProvider);
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final aiOpen = ref.watch(aiPanelProvider.select((p) => p.isOpen));

    final notebooksAsync = ref.watch(notebooksStreamProvider);
    final notebooks = notebooksAsync.valueOrNull ?? const <Notebook>[];
    final notebook =
        notebooks.where((n) => n.id == selection.notebookId).firstOrNull;
    final sections = selection.notebookId == null
        ? const <Section>[]
        : ref
                .watch(sectionsStreamProvider(selection.notebookId!))
                .valueOrNull ??
            const <Section>[];
    final section =
        sections.where((s) => s.id == selection.sectionId).firstOrNull;
    final pages = (selection.notebookId != null && selection.sectionId != null)
        ? ref
                .watch(pagesStreamProvider((
                  notebookId: selection.notebookId!,
                  sectionId: selection.sectionId!,
                )))
                .valueOrNull ??
            const <NotePage>[]
        : const <NotePage>[];
    final page = selection.home
        ? null
        : pages.where((p) => p.id == selection.pageId).firstOrNull;

    // What the window is showing, for the title bar and the content pane.
    final String title;
    final String? subtitle;
    final Widget content;
    if (selection.home) {
      final count = ref.watch(recentPagesProvider).length;
      title = 'Recents';
      subtitle = count == 0 ? null : '$count ${count == 1 ? 'page' : 'pages'}';
      content = const MacRecentsBrowser();
    } else if (page != null) {
      title = page.title.isEmpty ? 'Untitled' : page.title;
      subtitle = [section?.name, notebook?.name]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' · ');
      content = EditorScreen(key: ValueKey(page.id), page: page);
    } else if (section != null) {
      title = section.name.isEmpty ? 'Untitled' : section.name;
      subtitle = notebook?.name;
      content = MacSectionBrowser(
        key: ValueKey('section-${section.id}'),
        notebookId: section.notebookId,
        sectionId: section.id,
      );
    } else if (notebook != null) {
      title = notebook.name.isEmpty ? 'Untitled' : notebook.name;
      subtitle = sections.isEmpty
          ? null
          : '${sections.length} ${sections.length == 1 ? 'section' : 'sections'}';
      content = MacNotebookBrowser(
        key: ValueKey('notebook-${notebook.id}'),
        notebook: notebook,
      );
    } else {
      title = 'Mario';
      subtitle = null;
      content = const MacContent(
        scroll: false,
        child: MacEmptyState(
          title: 'No Selection',
          message: 'Choose a notebook, a section or a page in the sidebar.',
        ),
      );
    }

    final lights = macWindowLights();
    final toggleSidebar = MacToolbarButton(
      icon: AppleIcons.sidebarLeft,
      label: collapsed ? 'Show Sidebar' : 'Hide Sidebar',
      onPressed: _toggleSidebar,
    );

    // New Page targets the open section — the one in the sidebar, or the
    // one the open page lives in.
    final newPageTarget = (selection.notebookId != null && section != null)
        ? (notebookId: selection.notebookId!, sectionId: section.id)
        : null;
    void newPage() {
      final t = newPageTarget;
      if (t == null) return;
      createPage(context, ref,
          notebookId: t.notebookId, sectionId: t.sectionId);
    }

    final titlebar = MacWindowDragArea(
      child: MacTitlebar(
        title: title,
        subtitle: (subtitle == null || subtitle.isEmpty) ? null : subtitle,
        windowControls: collapsed ? lights : null,
        leading: [if (collapsed) toggleSidebar],
        actions: [
          MacToolbarButton(
            icon: AppleIcons.squareAndPencil,
            label: newPageTarget == null
                ? 'New Page (choose a section first)'
                : 'New Page',
            onPressed: newPageTarget == null ? null : newPage,
          ),
          MacPullDownButton(
            toolbar: true,
            icon: AppleIcons.plus,
            semanticLabel: 'New',
            items: [
              MacMenuItem(
                label: 'New Page…',
                shortcut: 'Ctrl+Alt+N',
                enabled: newPageTarget != null,
                onSelected: newPage,
              ),
              MacMenuItem(
                label: 'New Section…',
                enabled: selection.notebookId != null,
                onSelected: () {
                  final id = selection.notebookId;
                  if (id != null) createSection(context, ref, id);
                },
              ),
              MacMenuItem(
                label: 'New Notebook…',
                shortcut: 'Ctrl+N',
                onSelected: () => createNotebook(context, ref),
              ),
            ],
          ),
          MacToolbarButton(
            icon: CupertinoIcons.sparkles,
            label: aiOpen ? 'Hide Mario' : 'Ask Mario',
            pressed: aiOpen,
            onPressed: () => ref.read(aiPanelProvider.notifier).toggle(),
          ),
          const _AccountMenu(),
          MacSearchField(
            toolbar: true,
            width: 180,
            value: _filter,
            placeholder: 'Search',
            semanticLabel: 'Search pages',
            onChanged: (q) => setState(() => _filter = q),
            // Return carries the text to the search panel, which also
            // matches notebook and section names and can file a new page
            // under the query.
            onSubmitted: (q) => showGlobalSearch(context, initialQuery: q),
          ),
        ],
      ),
    );

    Widget? sidebar;
    if (!collapsed) {
      sidebar = _SidebarResizer(
        width: _sidebarWidth,
        onResize: (w) =>
            setState(() => _sidebarWidth = w.clamp(_kSidebarMin, _kSidebarMax)),
        child: MacNavSidebar(
          width: _sidebarWidth,
          filter: _filter,
          header: [
            MacWindowDragArea(
              child: SizedBox(
                height: 52,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: lights ?? const SizedBox.shrink(),
                ),
              ),
            ),
            toggleSidebar,
          ],
        ),
      );
    }

    return GlobalShortcuts(
      // A Scaffold for what the editor and the AI panel still do the
      // Material way (snack bars, ink); MacWindow paints everything visible.
      child: Scaffold(
        body: MacWindow(
          sidebar: sidebar,
          titlebar: titlebar,
          inspector: const AiSidePanel(),
          child: content,
        ),
      ),
    );
  }
}

/// The signed-in account: its name, Settings and Sign Out.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final name = user?.displayName?.trim();
    final email = user?.email?.trim();
    final account = (name != null && name.isNotEmpty) ? name : email;
    return MacPullDownButton(
      toolbar: true,
      icon: AppleIcons.personCircle,
      semanticLabel: account ?? 'Account',
      items: [
        if (account != null) MacMenuHeader(account),
        if (email != null && email.isNotEmpty && email != account)
          MacMenuItem(label: email, enabled: false),
        if (account != null) const MacMenuDivider(),
        MacMenuItem(
          label: 'Settings…',
          shortcut: 'Ctrl+,',
          onSelected: () => context.push('/settings'),
        ),
        const MacMenuDivider(),
        MacMenuItem(
          label: 'Sign Out',
          enabled: user != null,
          onSelected: () => ref.read(authNotifierProvider.notifier).signOut(),
        ),
      ],
    );
  }
}

/// Lets the sidebar's right edge be dragged to resize it, as on macOS.
class _SidebarResizer extends StatelessWidget {
  const _SidebarResizer({
    required this.width,
    required this.onResize,
    required this.child,
  });

  final double width;
  final ValueChanged<double> onResize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: 5,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) => onResize(width + d.delta.dx),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
