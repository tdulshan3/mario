/// The desktop sidebar: Recents, then every notebook as a folder of sections
/// and pages — one source list, the way a macOS app lists its places.
///
/// It replaces two pieces of the Material shell at once: the notebook strip
/// (`notebook_tabs.dart`) and the per-notebook tree (`nav_tree.dart`). Their
/// actions all survive, as context menus on the rows:
///
///   notebook  New Section…, Edit Notebook…, Delete Notebook…
///   section   New Page…, Edit Section…, Delete Section…
///   page      Rename…, Export as Markdown…, Export as PDF…, Delete Page…
///
/// and so does drag to reorder: a section lands before or after another, a
/// page before or after another or at the end of a section, always within
/// its notebook (a page's document lives under its notebook).
///
/// Pages are drawn as siblings of their section row, one level deeper,
/// rather than as the section's nested children. That keeps each row its own
/// widget, so a row — and only that row — carries its drag handle, its drop
/// zone and its context menu. apple_ui's context menu listens for the raw
/// pointer, so menus nested inside one another would all open at once; the
/// rows here ask one shared menu (see [_MacNavSidebarState._openMenu]) to
/// open instead, through a secondary-tap recogniser, where the innermost row
/// wins the gesture arena.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/note_page.dart';
import '../../../core/models/notebook.dart';
import '../../../core/models/section.dart';
import '../../../ui/colors.dart';
import '../shell_actions.dart';
import '../shell_state.dart';

class MacNavSidebar extends ConsumerStatefulWidget {
  const MacNavSidebar({
    super.key,
    required this.header,
    this.filter = '',
    this.width = 240,
  });

  /// The 52 px header row: the window's lights and the sidebar button.
  final List<Widget> header;

  /// Narrows the tree to titles containing it (the toolbar search field).
  final String filter;
  final double width;

  @override
  ConsumerState<MacNavSidebar> createState() => _MacNavSidebarState();
}

/// What a context menu was opened on.
sealed class _MenuTarget {
  const _MenuTarget();
}

class _NotebookTarget extends _MenuTarget {
  const _NotebookTarget(this.notebook);
  final Notebook notebook;
}

class _SectionTarget extends _MenuTarget {
  const _SectionTarget(this.section);
  final Section section;
}

class _PageTarget extends _MenuTarget {
  const _PageTarget(this.page);
  final NotePage page;
}

class _MacNavSidebarState extends ConsumerState<MacNavSidebar> {
  final Set<String> _openNotebooks = {};
  final Set<String> _openSections = {};

  final _menu = MacMenuController();
  final _stackKey = GlobalKey();
  _MenuTarget? _menuTarget;
  Offset? _menuAt;

  @override
  void initState() {
    super.initState();
    _reveal(ref.read(selectionProvider));
  }

  /// Opens the folders that lead to the selection, so whatever is open in
  /// the window is visible in the sidebar.
  void _reveal(Selection s) {
    if (s.home) return;
    if (s.notebookId != null) _openNotebooks.add(s.notebookId!);
    if (s.sectionId != null) _openSections.add(s.sectionId!);
  }

  void _setOpen(Set<String> set, String id, bool open) =>
      setState(() => open ? set.add(id) : set.remove(id));

  /// Opens the shared context menu for [target] at the pointer.
  void _openMenu(_MenuTarget target, Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _menu.close();
    setState(() {
      _menuTarget = target;
      _menuAt = box.globalToLocal(global);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _menu.open();
    });
  }

  List<Widget> _menuItems() {
    final target = _menuTarget;
    return switch (target) {
      null => const [],
      _NotebookTarget(:final notebook) => [
          MacMenuItem(
            label: 'New Section…',
            onSelected: () => createSection(context, ref, notebook.id),
          ),
          MacMenuItem(
            label: 'Edit Notebook…',
            onSelected: () => editNotebook(context, ref, notebook),
          ),
          const MacMenuDivider(),
          MacMenuItem(
            label: 'Delete Notebook…',
            onSelected: () => deleteNotebook(context, ref, notebook),
          ),
        ],
      _SectionTarget(:final section) => [
          MacMenuItem(
            label: 'New Page…',
            onSelected: () => createPage(
              context,
              ref,
              notebookId: section.notebookId,
              sectionId: section.id,
            ),
          ),
          MacMenuItem(
            label: 'Edit Section…',
            onSelected: () => editSection(context, ref, section),
          ),
          const MacMenuDivider(),
          MacMenuItem(
            label: 'Delete Section…',
            onSelected: () => deleteSection(context, ref, section),
          ),
        ],
      _PageTarget(:final page) => [
          MacMenuItem(
            label: 'Rename…',
            onSelected: () => renamePage(context, ref, page),
          ),
          const MacMenuDivider(),
          MacMenuItem(
            label: 'Export as Markdown…',
            onSelected: () => exportPageAsMarkdown(context, page),
          ),
          MacMenuItem(
            label: 'Export as PDF…',
            onSelected: () => exportPageAsPdf(context, page),
          ),
          const MacMenuDivider(),
          MacMenuItem(
            label: 'Delete Page…',
            onSelected: () => deletePage(context, ref, page),
          ),
        ],
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Selection>(selectionProvider, (_, next) {
      setState(() => _reveal(next));
    });
    final selection = ref.watch(selectionProvider);
    final notebooksAsync = ref.watch(notebooksStreamProvider);
    final notebooks = notebooksAsync.valueOrNull ?? const <Notebook>[];
    final filter = widget.filter.trim().toLowerCase();

    final notebookRows = <Widget>[
      for (final nb in notebooks)
        if (_notebookRow(nb, selection, filter) case final row?) row,
    ];

    final sidebar = MacSidebar(
      width: widget.width,
      header: widget.header,
      children: [
        MacSidebarSection(
          children: [
            MacSidebarItem(
              icon: AppleIcons.clock,
              label: 'Recents',
              selected: selection.home,
              onPressed: () => ref.read(selectionProvider.notifier).goHome(),
            ),
          ],
        ),
        MacSidebarSection(
          title: 'Notebooks',
          children: [
            if (notebookRows.isNotEmpty)
              ...notebookRows
            else
              _SidebarNote(
                notebooksAsync.isLoading && !notebooksAsync.hasValue
                    ? 'Loading…'
                    : notebooksAsync.hasError
                        ? 'Notebooks could not be loaded.'
                        : filter.isNotEmpty
                            ? 'No Results'
                            : 'No Notebooks',
              ),
          ],
        ),
      ],
    );

    return Stack(
      key: _stackKey,
      children: [
        sidebar,
        if (_menuAt != null)
          Positioned(
            left: _menuAt!.dx,
            // A menu opened from its controller hangs 6 px under its anchor;
            // a context menu's top-left corner is the pointer.
            top: _menuAt!.dy - 6,
            child: MacContextMenu(
              controller: _menu,
              items: _menuItems(),
              child: const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }

  /// One notebook and, when open, its sections and their pages. Null when a
  /// filter is running and nothing inside it matches.
  Widget? _notebookRow(Notebook nb, Selection selection, String filter) {
    final filtering = filter.isNotEmpty;
    final open = filtering || _openNotebooks.contains(nb.id);
    final nameHit = nb.name.toLowerCase().contains(filter);

    final children = <Widget>[];
    if (open) {
      final sections =
          ref.watch(sectionsStreamProvider(nb.id)).valueOrNull ?? const [];
      for (final s in sections) {
        children.addAll(_sectionRows(s, sections, selection, filter));
      }
      if (sections.isEmpty && !filtering) {
        children.add(const _EmptyRow(label: 'No Sections', level: 1));
      }
    }
    if (filtering && !nameHit && children.isEmpty) return null;

    return _MenuArea(
      onMenu: (at) => _openMenu(_NotebookTarget(nb), at),
      child: MacSidebarItem(
        key: ValueKey('nb-${nb.id}'),
        image: _NotebookBadge(colorIndex: nb.colorIndex),
        label: nb.name.isEmpty ? 'Untitled' : nb.name,
        selected: !selection.home &&
            selection.notebookId == nb.id &&
            selection.sectionId == null &&
            selection.pageId == null,
        expanded: open,
        onExpandedChanged: (v) => _setOpen(_openNotebooks, nb.id, v),
        onPressed: () {
          ref.read(selectionProvider.notifier).selectNotebook(nb.id);
          _setOpen(_openNotebooks, nb.id, true);
        },
        children: children,
      ),
    );
  }

  /// A section row, then — when it is open — its pages one level deeper.
  List<Widget> _sectionRows(
    Section s,
    List<Section> siblings,
    Selection selection,
    String filter,
  ) {
    final filtering = filter.isNotEmpty;
    final open = filtering || _openSections.contains(s.id);
    final pagesAsync = ref.watch(
        pagesStreamProvider((notebookId: s.notebookId, sectionId: s.id)));
    final all = pagesAsync.valueOrNull ?? const <NotePage>[];
    final pages = filtering
        ? all.where((p) => p.title.toLowerCase().contains(filter)).toList()
        : all;
    if (filtering && !s.name.toLowerCase().contains(filter) && pages.isEmpty) {
      return const [];
    }

    final sectionRow = _DropZone(
      accepts: (d) => switch (d) {
        _DragSection(:final section) =>
          section.id != s.id && section.notebookId == s.notebookId,
        _DragPage(:final page) => page.notebookId == s.notebookId,
      },
      split: (d) => d is _DragSection,
      onDrop: (d, before) => switch (d) {
        _DragSection(:final section) =>
          reorderSections(ref, siblings, section, s, before: before),
        _DragPage(:final page) => movePageInto(ref, page, s),
      },
      child: _DragHandle(
        data: _DragSection(s),
        label: s.name,
        child: _MenuArea(
          onMenu: (at) => _openMenu(_SectionTarget(s), at),
          child: MacSidebarItem(
            key: ValueKey('s-${s.id}'),
            icon: AppleIcons.folder,
            label: s.name.isEmpty ? 'Untitled' : s.name,
            detail: pagesAsync.hasValue ? '${all.length}' : null,
            selected: !selection.home &&
                selection.sectionId == s.id &&
                selection.pageId == null,
            expanded: open,
            onExpandedChanged: (v) => _setOpen(_openSections, s.id, v),
            onPressed: () {
              ref
                  .read(selectionProvider.notifier)
                  .selectSection(s.id, notebookId: s.notebookId);
              _setOpen(_openSections, s.id, true);
            },
            // A folder whose rows are drawn beside it (see the library doc).
            children: const [],
          ),
        ),
      ),
    );
    if (!open) return [sectionRow];

    return [
      sectionRow,
      for (final p in pages)
        _DropZone(
          accepts: (d) =>
              d is _DragPage &&
              d.page.id != p.id &&
              d.page.notebookId == p.notebookId,
          split: (_) => true,
          onDrop: (d, before) => dropPageOnPage(
            ref,
            (d as _DragPage).page,
            p,
            before: before,
            sectionPages: all,
          ),
          child: _DragHandle(
            data: _DragPage(p),
            label: p.title.isEmpty ? 'Untitled' : p.title,
            child: _MenuArea(
              onMenu: (at) => _openMenu(_PageTarget(p), at),
              child: MacSidebarItem(
                key: ValueKey('p-${p.id}'),
                icon: AppleIcons.docText,
                label: p.title.isEmpty ? 'Untitled' : p.title,
                level: 2,
                selected: !selection.home && selection.pageId == p.id,
                onPressed: () =>
                    ref.read(selectionProvider.notifier).selectPage(
                          p.id,
                          sectionId: p.sectionId,
                          notebookId: p.notebookId,
                        ),
              ),
            ),
          ),
        ),
      if (pages.isEmpty && !filtering && pagesAsync.hasValue)
        _DropZone(
          accepts: (d) => d is _DragPage && d.page.notebookId == s.notebookId,
          split: (_) => false,
          onDrop: (d, _) => movePageInto(ref, (d as _DragPage).page, s),
          child: const _EmptyRow(label: 'No Pages', level: 2),
        ),
    ];
  }
}

/// A notebook's sidebar image: its label colour as a filled circle with the
/// book symbol, as Reminders draws its lists.
class _NotebookBadge extends StatelessWidget {
  const _NotebookBadge({required this.colorIndex});

  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    final palette = MarioColors.labelPalette;
    final color = palette[colorIndex.clamp(0, palette.length - 1)];
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox.square(
        dimension: 18,
        child: Center(
          child: Icon(AppleIcons.book, size: 11, color: Color(0xFFFFFFFF)),
        ),
      ),
    );
  }
}

/// A disabled placeholder row ("No Pages").
class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.label, required this.level});

  final String label;
  final int level;

  @override
  Widget build(BuildContext context) =>
      MacSidebarItem(label: label, level: level, onPressed: null);
}

/// A line of grey text in place of rows.
class _SidebarNote extends StatelessWidget {
  const _SidebarNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Text(
        text,
        style: MacTypography.of(context).body.copyWith(
              color: c.labelSecondary,
            ),
      ),
    );
  }
}

/// Opens the shared context menu when its row is secondary-clicked.
///
/// A tap recogniser, not a raw listener: when rows sit inside one another (a
/// notebook around its sections) the innermost one wins the arena, so one
/// right-click opens exactly one menu.
class _MenuArea extends StatelessWidget {
  const _MenuArea({required this.onMenu, required this.child});

  final ValueChanged<Offset> onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (d) => onMenu(d.globalPosition),
        child: child,
      );
}

// ── Drag and drop ──────────────────────────────────────────────────────────

sealed class _Drag {
  const _Drag();
}

class _DragSection extends _Drag {
  const _DragSection(this.section);
  final Section section;
}

class _DragPage extends _Drag {
  const _DragPage(this.page);
  final NotePage page;
}

/// Picks a row up after a short press — short enough to feel like picking it
/// up, long enough that a click still selects.
class _DragHandle extends StatelessWidget {
  const _DragHandle({
    required this.data,
    required this.label,
    required this.child,
  });

  final _Drag data;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => LongPressDraggable<_Drag>(
        data: data,
        delay: const Duration(milliseconds: 160),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _DragFeedback(
          label: label,
          // The feedback is built in the overlay, above the app's theme
          // scope; carry the appearance across.
          theme: AppleTheme.of(context),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: child),
        child: child,
      );
}

/// What hangs from the pointer: the row's name on the menu material.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.label, required this.theme});

  final String label;
  final AppleThemeData theme;

  @override
  Widget build(BuildContext context) {
    return AppleTheme(
      data: theme,
      child: Builder(builder: (context) {
        return Transform.translate(
          offset: const Offset(10, -12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: MacGlass(
              style: MacGlassStyle.panel,
              radius: 6,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MacTypography.of(context).body,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// A row other rows can be dropped on. [split] says whether a drop lands
/// before or after the row (a blue insertion line shows which) or into it (a
/// blue outline).
class _DropZone extends StatefulWidget {
  const _DropZone({
    required this.accepts,
    required this.split,
    required this.onDrop,
    required this.child,
  });

  final bool Function(_Drag drag) accepts;
  final bool Function(_Drag drag) split;
  final void Function(_Drag drag, bool before) onDrop;
  final Widget child;

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool? _before;
  bool _into = false;

  void _track(DragTargetDetails<_Drag> d) {
    if (!widget.accepts(d.data)) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(d.offset);
    final split = widget.split(d.data);
    final before = split && local.dy < box.size.height / 2;
    if (before != _before || !split != _into) {
      setState(() {
        _before = before;
        _into = !split;
      });
    }
  }

  void _clear() {
    if (_before == null && !_into) return;
    setState(() {
      _before = null;
      _into = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) {
        final ok = widget.accepts(d.data);
        if (ok) _track(d);
        return ok;
      },
      onMove: _track,
      onLeave: (_) => _clear(),
      onAcceptWithDetails: (d) {
        final before = _before ?? false;
        _clear();
        widget.onDrop(d.data, before);
      },
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            if (hovering && _into)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: accent, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            if (hovering && !_into && _before != null)
              Positioned(
                left: 4,
                right: 4,
                top: _before! ? -1 : null,
                bottom: _before! ? null : -1,
                child: IgnorePointer(
                  child: Container(height: 2, color: accent),
                ),
              ),
          ],
        );
      },
    );
  }
}
