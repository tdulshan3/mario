/// NavTree — the app's single sidebar.
///
/// The Simple remodel empties it back out again. Notebooks live on the
/// `NotebookTabBar` strip now, so the picker card, the switcher panel and the
/// "New page" pill are all gone from here; what is left is a filter field, a
/// create menu, and one flat tree of sections with their pages nested under
/// them. Nothing was dropped — the notebook actions moved to the strip, and
/// creating a section moved into the `+` beside the filter.
///
/// Chrome here is flat: the sidebar is a solid `--side` panel with a hairline
/// down its right edge. The selected page is marked by a 2px accent bar on its
/// leading edge and by the accent's deep text tone — no fill, no border, no
/// radius. Colour comes from the tokens, so all four grounds read correctly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../core/models/section.dart';
import '../../core/services/asset_sync_service.dart';
import '../../core/services/page_content_repository.dart';
import '../../ui/colors.dart';
import '../../ui/organic.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/mario_loader.dart';
import '../export/markdown_exporter.dart';
import '../export/pdf_exporter.dart';
import 'dialogs/notebook_dialog.dart';
import 'dialogs/text_input_dialog.dart';
import 'shell_state.dart';
import 'tree_order.dart';

class NavTree extends ConsumerStatefulWidget {
  const NavTree({super.key});

  @override
  ConsumerState<NavTree> createState() => _NavTreeState();
}

class _NavTreeState extends ConsumerState<NavTree> {
  /// Section IDs that are currently expanded. Sections default to expanded;
  /// flipping the chevron collapses just that section's pages.
  final Set<String> _collapsedSections = {};

  /// Whether the notebook picker is showing its switcher list.

  /// What the tree is filtered by. Empty means "show everything".
  final TextEditingController _filter = TextEditingController();
  String _filterText = '';

  @override
  void initState() {
    super.initState();
    _filter.addListener(() {
      final next = _filter.text.trim().toLowerCase();
      if (next == _filterText) return;
      setState(() => _filterText = next);
    });
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

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
    final selection = ref.watch(selectionProvider);
    final notebooks =
        ref.watch(notebooksStreamProvider).valueOrNull ?? const <Notebook>[];
    final notebook =
        notebooks.where((n) => n.id == selection.notebookId).firstOrNull;

    return MarioSurface(
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: marioDivider(context))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Filter, and the create action ───────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(child: _TreeFilterField(controller: _filter)),
                  const SizedBox(width: 4),
                  _SidebarAddButton(
                    notebookId: notebook?.id,
                    sectionId: selection.sectionId,
                  ),
                ],
              ),
            ),
            Expanded(
              child: notebook == null
                  ? _EmptyHint(
                      text: notebooks.isEmpty
                          ? 'No notebooks yet.\nUse + on the notebook strip to create your first one.'
                          : 'Pick a notebook from the strip above to see its sections.',
                    )
                  : _SectionList(
                      notebookId: notebook.id,
                      collapsedSections: _collapsedSections,
                      onToggleSection: _toggleSection,
                      filter: _filterText,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header controls ───────────────────────────────────────────────────────

/// The tree filter — "Search page or heading…" on the artboard.
///
/// A real filter, not a jump-to-search: it narrows the tree in place, so the
/// structure around a hit stays visible. The command palette (Ctrl+Shift+F)
/// is still the thing for searching across notebooks.
class _TreeFilterField extends StatelessWidget {
  const _TreeFilterField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: t.paper,
        borderRadius: BorderRadius.circular(MarioRadius.sm),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: t.mut),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              cursorColor: t.ink,
              cursorWidth: 1,
              style: TextStyle(fontSize: 12.5, height: 1.2, color: t.ink),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search page or heading…',
                hintStyle: TextStyle(fontSize: 12.5, height: 1.2, color: t.mut),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: controller.clear,
              behavior: HitTestBehavior.opaque,
              child: Icon(Icons.close, size: 14, color: t.mut),
            ),
        ],
      ),
    );
  }
}

/// The `+` beside the filter.
///
/// The artboard draws one glyph, so this is one control — but the sidebar
/// creates two kinds of thing, and the old "New page" pill and "Add" section
/// chip both lived here. Both survive, as a two-item menu behind the glyph.
class _SidebarAddButton extends ConsumerWidget {
  const _SidebarAddButton({required this.notebookId, required this.sectionId});

  final String? notebookId;
  final String? sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = marioTokens(context);
    final hasNotebook = notebookId != null;
    return PopupMenuButton<_AddAction>(
      tooltip: 'New…',
      position: PopupMenuPosition.under,
      enabled: hasNotebook,
      color: t.paper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MarioRadius.md),
        side: BorderSide(color: t.line),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _AddAction.page,
          enabled: sectionId != null,
          child: const Text('New page'),
        ),
        const PopupMenuItem(
          value: _AddAction.section,
          child: Text('New section'),
        ),
      ],
      onSelected: (a) => switch (a) {
        _AddAction.page => _createPage(context, ref),
        _AddAction.section => _createSection(context, ref),
      },
      child: SizedBox(
        width: 26,
        height: 26,
        child: Icon(
          Icons.add,
          size: 17,
          color: hasNotebook ? t.sec : t.mut.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Future<void> _createPage(BuildContext context, WidgetRef ref) async {
    final nid = notebookId;
    final sid = sectionId;
    if (nid == null || sid == null) return;
    final title = await showTextInputDialog(
      context,
      title: 'New page',
      label: 'Title',
      submitLabel: 'Create',
    );
    if (title == null) return;
    final pages = ref
            .read(pagesStreamProvider((notebookId: nid, sectionId: sid)))
            .valueOrNull ??
        const [];
    final now = DateTime.now();
    final page = NotePage(
      id: '',
      sectionId: sid,
      notebookId: nid,
      title: title,
      order: pages.length,
      createdAt: now,
      updatedAt: now,
    );
    final id = await ref.read(syncServiceProvider).createPage(page);
    ref.read(selectionProvider.notifier).selectPage(id);
  }

  Future<void> _createSection(BuildContext context, WidgetRef ref) async {
    final nid = notebookId;
    if (nid == null) return;
    final result = await showNotebookDialog(
      context,
      title: 'New section',
      submitLabel: 'Create',
    );
    if (result == null) return;
    final sections =
        ref.read(sectionsStreamProvider(nid)).valueOrNull ?? const [];
    final id = await ref.read(syncServiceProvider).createSection(
          Section(
            id: '',
            notebookId: nid,
            name: result.name,
            colorIndex: result.colorIndex,
            order: sections.length,
          ),
        );
    ref.read(selectionProvider.notifier).selectSection(id);
  }
}

enum _AddAction { page, section }

// ── Sections and pages ─────────────────────────────────────────────────────

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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
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
    required this.filter,
  });
  final String notebookId;
  final Set<String> collapsedSections;
  final ValueChanged<String> onToggleSection;

  /// Lower-cased, already trimmed. Empty means "show everything".
  final String filter;

  @override
  ConsumerState<_SectionList> createState() => _SectionListState();
}

class _SectionListState extends ConsumerState<_SectionList> {
  @override
  Widget build(BuildContext context) {
    final sectionsAsync = ref.watch(sectionsStreamProvider(widget.notebookId));
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return sectionsAsync.when(
      loading: () => const Center(child: MarioLoader(size: 18)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('$e',
            style: text.bodySmall
                ?.copyWith(fontSize: 12.5, color: scheme.onSurfaceVariant)),
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
            text: 'No sections yet.\nUse Add above to create your first one.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
          itemCount: sections.length,
          itemBuilder: (context, i) {
            final s = sections[i];
            // A filtered tree is always open: collapsing a group would hide
            // the very rows the filter just found.
            final expanded = widget.filter.isNotEmpty ||
                !widget.collapsedSections.contains(s.id);
            return _SectionGroup(
              section: s,
              expanded: expanded,
              filter: widget.filter,
              onToggle: () => widget.onToggleSection(s.id),
              onMenu: (a) => _handleSectionAction(context, s, a),
              onDropSection: (dragged, before) =>
                  _reorderSections(sections, dragged, s, before: before),
              onDropPageInto: (page) => _movePageInto(page, s),
            );
          },
        );
      },
    );
  }

  /// A section dragged to sit before or after another. Every section whose
  /// place changed is written; the rest are left alone.
  Future<void> _reorderSections(
    List<Section> sections,
    Section dragged,
    Section target, {
    required bool before,
  }) async {
    final order = reorderedIds(
      [for (final s in sections) s.id],
      dragged.id,
      target.id,
      before: before,
    );
    final byId = {for (final s in sections) s.id: s};
    final writes =
        ordersToWrite(order, {for (final s in sections) s.id: s.order});
    final sync = ref.read(syncServiceProvider);
    for (final e in writes.entries) {
      await sync.updateSection(byId[e.key]!.copyWith(order: e.value));
    }
  }

  /// A page dropped on a section's header goes to the end of that section.
  Future<void> _movePageInto(NotePage page, Section target) async {
    final pages = ref
            .read(pagesStreamProvider(
                (notebookId: target.notebookId, sectionId: target.id)))
            .valueOrNull ??
        const <NotePage>[];
    await _writePageOrder(
      ref,
      appendedIds([for (final p in pages) p.id], page.id),
      {for (final p in pages) p.id: p, page.id: page},
      sectionId: target.id,
      notebookId: target.notebookId,
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

class _SectionGroup extends ConsumerStatefulWidget {
  const _SectionGroup({
    required this.section,
    required this.expanded,
    required this.filter,
    required this.onToggle,
    required this.onMenu,
    required this.onDropSection,
    required this.onDropPageInto,
  });

  final Section section;
  final bool expanded;
  final String filter;
  final VoidCallback onToggle;
  final ValueChanged<_SectionAction> onMenu;

  /// Another section was dropped on this one's header: before or after it.
  final void Function(Section dragged, bool before) onDropSection;

  /// A page was dropped on this section's header.
  final ValueChanged<NotePage> onDropPageInto;

  @override
  ConsumerState<_SectionGroup> createState() => _SectionGroupState();
}

class _SectionGroupState extends ConsumerState<_SectionGroup> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    final section = widget.section;
    final pages = ref
            .watch(pagesStreamProvider(
                (notebookId: section.notebookId, sectionId: section.id)))
            .valueOrNull ??
        const <NotePage>[];

    // While a filter is running, a group that matches nothing gets out of the
    // way entirely — leaving an empty header behind would make the filter
    // look broken.
    final f = widget.filter;
    if (f.isNotEmpty &&
        !section.name.toLowerCase().contains(f) &&
        !pages.any((p) => p.title.toLowerCase().contains(f))) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DropZone(
          // A section lands before or after this one; a page lands inside.
          accepts: (d) => switch (d) {
            _DragSection(:final section) => section.id != widget.section.id,
            _DragPage() => true,
          },
          split: (d) => d is _DragSection,
          onDrop: (d, before) => switch (d) {
            _DragSection(:final section) =>
              widget.onDropSection(section, before),
            _DragPage(:final page) => widget.onDropPageInto(page),
          },
          child: _DragHandle(
            data: _DragSection(section),
            label: section.name,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    ref
                        .read(selectionProvider.notifier)
                        .selectSection(section.id);
                    if (!widget.expanded) widget.onToggle();
                  },
                  onSecondaryTapDown: (d) =>
                      _showMenu(context, d.globalPosition),
                  child: SizedBox(
                    height: t.row,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          // The chevron swaps glyph rather than rotating: the
                          // artboard draws `expand_more` open and
                          // `chevron_right` closed, which are not the same shape
                          // turned 90°.
                          GestureDetector(
                            onTap: widget.onToggle,
                            behavior: HitTestBehavior.opaque,
                            child: Icon(
                              widget.expanded
                                  ? Icons.expand_more
                                  : Icons.chevron_right,
                              size: 17,
                              color: t.mut,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              section.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: t.rowFontSize,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                color: t.ink,
                              ),
                            ),
                          ),
                          _HoverReveal(
                            visible: _hovered,
                            child: _MenuButton<_SectionAction>(
                              onSelected: widget.onMenu,
                              items: const [
                                ('Rename / recolor', _SectionAction.rename),
                                ('Delete', _SectionAction.delete),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 160),
          crossFadeState: widget.expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: _PageList(
            notebookId: section.notebookId,
            sectionId: section.id,
            filter: widget.filter,
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
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
    if (result != null) widget.onMenu(result);
  }
}

class _PageList extends ConsumerStatefulWidget {
  const _PageList({
    required this.notebookId,
    required this.sectionId,
    required this.filter,
  });
  final String notebookId;
  final String sectionId;
  final String filter;

  @override
  ConsumerState<_PageList> createState() => _PageListState();
}

class _PageListState extends ConsumerState<_PageList> {
  @override
  Widget build(BuildContext context) {
    final pagesAsync = ref.watch(pagesStreamProvider(
        (notebookId: widget.notebookId, sectionId: widget.sectionId)));
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final selection = ref.watch(selectionProvider);

    // The artboard indents the children by 19px and draws no rail at all —
    // the accent is spent on the selected row's own bar instead, and a second
    // vertical accent line running beside it would fight with that.
    Widget rail(Widget child) => Padding(
          padding: const EdgeInsets.only(left: 19),
          child: child,
        );

    return pagesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: MarioLoader(size: 18)),
      ),
      error: (e, _) => rail(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('$e',
              style:
                  text.bodySmall?.copyWith(fontSize: 12, color: scheme.error)),
        ),
      ),
      data: (all) {
        final f = widget.filter;
        final pages = f.isEmpty
            ? all
            : all.where((p) => p.title.toLowerCase().contains(f)).toList();
        // A filter that matched the section name but none of its pages says
        // so by showing nothing, not by claiming the section is empty.
        if (pages.isEmpty && f.isNotEmpty) return const SizedBox.shrink();
        if (pages.isEmpty) {
          // An empty section still takes a page dropped into it.
          return rail(
            _DropZone(
              accepts: (d) => d is _DragPage,
              split: (_) => false,
              onDrop: (d, _) => _dropIntoEmpty(d as _DragPage),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  'No pages yet',
                  style: text.bodySmall?.copyWith(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          );
        }
        return rail(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in pages)
                _PageTile(
                  page: p,
                  selected: p.id == selection.pageId,
                  onTap: () => ref.read(selectionProvider.notifier).selectPage(
                        p.id,
                        sectionId: p.sectionId,
                        notebookId: p.notebookId,
                      ),
                  onMenu: (a) => _handlePageAction(context, p, a),
                  onDrop: (d, before) =>
                      _dropOnPage(d, p, before: before, all: all),
                ),
            ],
          ),
        );
      },
    );
  }

  /// A page dropped before or after [target] — from this section, or from
  /// another, in which case it moves here at that spot.
  Future<void> _dropOnPage(
    _Drag d,
    NotePage target, {
    required bool before,
    required List<NotePage> all,
  }) async {
    if (d is! _DragPage) return;
    final dragged = d.page;
    if (dragged.id == target.id) return;
    final order = reorderedIds(
      [for (final p in all) p.id],
      dragged.id,
      target.id,
      before: before,
    );
    await _writePageOrder(
      ref,
      order,
      {for (final p in all) p.id: p, dragged.id: dragged},
      sectionId: widget.sectionId,
      notebookId: widget.notebookId,
    );
  }

  Future<void> _dropIntoEmpty(_DragPage d) => _writePageOrder(
        ref,
        [d.page.id],
        {d.page.id: d.page},
        sectionId: widget.sectionId,
        notebookId: widget.notebookId,
      );

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

class _PageTile extends StatefulWidget {
  const _PageTile({
    required this.page,
    required this.selected,
    required this.onTap,
    required this.onMenu,
    required this.onDrop,
  });

  final NotePage page;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<_PageAction> onMenu;

  /// A page was dropped before or after this one.
  final void Function(_Drag dragged, bool before) onDrop;

  @override
  State<_PageTile> createState() => _PageTileState();
}

class _PageTileState extends State<_PageTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    final selected = widget.selected;

    return _DropZone(
      accepts: (d) => d is _DragPage && d.page.id != widget.page.id,
      split: (_) => true,
      onDrop: widget.onDrop,
      child: _DragHandle(
        data: _DragPage(widget.page),
        label: widget.page.title.isEmpty ? 'Untitled' : widget.page.title,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: MarioAccentEdge(
            active: selected,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
                child: SizedBox(
                  height: t.row,
                  child: Padding(
                    // Leading 12 only. The selected row's bar is an overlay, so
                    // it does not push the label across the way a border would —
                    // selected and unselected rows stay on the same left edge.
                    padding: const EdgeInsets.only(left: 12, right: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.page.title.isEmpty
                                ? 'Untitled'
                                : widget.page.title,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: t.rowFontSize,
                              height: 1.2,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? t.accentText : t.sec,
                            ),
                          ),
                        ),
                        // Same trade as the section rows: quiet by default, menu
                        // on hover, right-click anywhere on the row. Export has no
                        // other entry point here, so it must not be hover-only on
                        // touch.
                        _HoverReveal(
                          visible: _hovered,
                          child: _MenuButton<_PageAction>(
                            onSelected: widget.onMenu,
                            items: const [
                              ('Rename', _PageAction.rename),
                              ('Export as Markdown', _PageAction.exportMd),
                              ('Export as PDF', _PageAction.exportPdf),
                              ('Delete', _PageAction.delete),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
    if (result != null) widget.onMenu(result);
  }
}

/// Writes the orders that changed once [order] became the order of the pages
/// in [sectionId], moving any page that came from another section.
///
/// The open page can be the one that moved: the editor host looks it up in
/// the selected section's list, so the selection follows it across.
Future<void> _writePageOrder(
  WidgetRef ref,
  List<String> order,
  Map<String, NotePage> byId, {
  required String sectionId,
  required String notebookId,
}) async {
  final sync = ref.read(syncServiceProvider);
  final selection = ref.read(selectionProvider);
  for (var i = 0; i < order.length; i++) {
    final p = byId[order[i]];
    if (p == null) continue;
    if (p.order == i && p.sectionId == sectionId) continue;
    await sync.updatePage(p.copyWith(order: i, sectionId: sectionId));
    if (p.sectionId != sectionId && selection.pageId == p.id) {
      ref.read(selectionProvider.notifier).selectPage(
            p.id,
            sectionId: sectionId,
            notebookId: notebookId,
          );
    }
  }
}

// ── Drag and drop ──────────────────────────────────────────────────────────
//
// Rows are picked up with a short press and dropped on other rows. A
// section dropped on a section header lands before or after it, by which
// half of the row the pointer is in; a page dropped on a page does the same,
// in that page's section; a page dropped on a section header, or on an
// empty section's placeholder, goes to the end of that section. The drop
// zone draws a 2px accent line where the row will land, or a frame around
// the section it will join. Orders are renumbered and written through the
// sync service, so a drag works offline like everything else.

/// What is being dragged.
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

/// Makes a row draggable after a short press — short enough to feel like
/// picking it up, long enough that a click still selects. The feedback hangs
/// from the pointer, which is what lets drop zones read the pointer's
/// position from the drag details.
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
        feedback: _DragFeedback(label: label),
        childWhenDragging: Opacity(opacity: 0.35, child: child),
        child: child,
      );
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return Transform.translate(
      offset: const Offset(10, -16),
      child: Material(
        elevation: 4,
        color: t.paper,
        borderRadius: BorderRadius.circular(MarioRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: t.rowFontSize,
                fontWeight: FontWeight.w500,
                color: t.ink,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that other rows can be dropped on.
///
/// [split] says whether a drag lands before or after this row (an accent
/// line shows which) or inside it (a frame shows that).
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
  /// Where the drag would land: true above, false below, null not here.
  bool? _before;
  bool _into = false;

  void _track(DragTargetDetails<_Drag> d) {
    if (!widget.accepts(d.data)) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(d.offset);
    final split = widget.split(d.data);
    final before = split && local.dy < box.size.height / 2;
    final into = !split;
    if (before != _before || into != _into) {
      setState(() {
        _before = before;
        _into = into;
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
    final t = marioTokens(context);
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
                      border: Border.all(color: t.accentBase, width: 1.5),
                      borderRadius: BorderRadius.circular(MarioRadius.sm),
                    ),
                  ),
                ),
              ),
            if (hovering && !_into && _before != null)
              Positioned(
                left: 8,
                right: 8,
                top: _before! ? -1 : null,
                bottom: _before! ? null : -1,
                child: IgnorePointer(
                  child: Container(height: 2, color: t.accentBase),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// True where there is no mouse, so a hover-revealed control would never
/// appear at all. The repo ships android and ios targets.
bool _isTouch(BuildContext context) => switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };

/// Wraps a row's overflow menu so it can be hover-revealed WITHOUT becoming a
/// dead control.
///
/// The naive `if (_hovered) _MenuButton(...)` looks right and does not work:
/// opening the popup pushes a modal barrier that takes the pointer, so
/// `MouseRegion.onExit` fires, `_hovered` flips false, and the button is torn
/// out of the tree while its own menu is still open. `PopupMenuButtonState`
/// then finds itself unmounted and drops the selection on the floor — every
/// item silently does nothing.
///
/// `maintainState` keeps the button mounted while it is hidden, which is what
/// makes the callback survive; `maintainSize` reserves the slot so the row does
/// not jump on hover. On touch the control is simply always shown.
class _HoverReveal extends StatelessWidget {
  const _HoverReveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => Visibility(
        visible: visible || _isTouch(context),
        maintainState: true,
        maintainSize: true,
        maintainAnimation: true,
        child: child,
      );
}

class _MenuButton<T> extends StatelessWidget {
  const _MenuButton({required this.onSelected, required this.items});
  final ValueChanged<T> onSelected;
  final List<(String, T)> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      onSelected: onSelected,
      tooltip: 'More',
      icon: Icon(Icons.more_horiz, size: 15, color: scheme.onSurfaceVariant),
      itemBuilder: (_) => [
        for (final (label, value) in items)
          PopupMenuItem(value: value, child: Text(label)),
      ],
      padding: EdgeInsets.zero,
      iconSize: 15,
      splashRadius: 14,
      constraints: const BoxConstraints(minWidth: 180),
    );
  }
}

// ── Footer ─────────────────────────────────────────────────────────────────
