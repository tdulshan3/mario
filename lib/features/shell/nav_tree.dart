/// NavTree — the app's single sidebar.
///
/// One column now carries everything the shell used to split across a 60px
/// notebook rail and a separate tree: the notebook picker, the primary
/// "New page" action, the sections with their pages nested under them, and the
/// footer. The rail's entire action set (switch, create, rename, recolor,
/// delete) moved into the picker at the top, so nothing was lost when the rail
/// went away.
///
/// Chrome here is glass, as everywhere else in the design: the sidebar veils
/// the ground at 0.62, and the picker and its switcher are glass cards on top
/// of it. Colour comes from the scheme, never from a literal, so all four
/// grounds (light, white, night, black) read correctly.
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
import '../auth/auth_notifier.dart';
import '../export/markdown_exporter.dart';
import '../export/pdf_exporter.dart';
import 'dialogs/notebook_dialog.dart';
import 'dialogs/text_input_dialog.dart';
import 'shell_state.dart';

/// The selected page's fill. Coral at a light tint on the light grounds; a
/// lifted, much weaker coral on the dark ones, where a 62% tint would glare.
Color _selectedFill(BuildContext context) => marioMode(context).isDark
    ? MarioColors.accent400.withValues(alpha: 0.20)
    : MarioColors.accent300.withValues(alpha: 0.62);

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

  /// Whether the notebook picker is showing its switcher list.
  bool _switcherOpen = false;

  /// Closing can be asked for after an await (creating a notebook opens a
  /// dialog first), by which point the sidebar may already be gone.
  void _closeSwitcher() {
    if (!mounted) return;
    setState(() => _switcherOpen = false);
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
    final scheme = Theme.of(context).colorScheme;
    final selection = ref.watch(selectionProvider);
    final notebooks =
        ref.watch(notebooksStreamProvider).valueOrNull ?? const <Notebook>[];
    final notebook =
        notebooks.where((n) => n.id == selection.notebookId).firstOrNull;

    return MarioGlass(
      opacity: 0.62,
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: marioDivider(context))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Notebook picker ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _NotebookPickerCard(
                      notebook: notebook,
                      open: _switcherOpen,
                      onToggle: () =>
                          setState(() => _switcherOpen = !_switcherOpen),
                    ),
                  ),
                  if (widget.onCollapse != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Collapse sidebar',
                      onPressed: widget.onCollapse,
                      icon: const Icon(Icons.chevron_left, size: 18),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 30, minHeight: 30),
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
            if (_switcherOpen)
              _NotebookSwitcher(
                notebooks: notebooks,
                selectedId: selection.notebookId,
                onClose: _closeSwitcher,
              ),

            // ── Primary action ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _NewPageButton(
                notebookId: notebook?.id,
                sectionId: selection.sectionId,
              ),
            ),

            // ── Sections ────────────────────────────────────────────────
            if (notebook != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 18, 12, 8),
                child: Row(
                  children: [
                    const MarioKicker('Sections'),
                    const Spacer(),
                    _AddSectionChip(notebookId: notebook.id),
                  ],
                ),
              ),
            Expanded(
              child: notebook == null
                  ? _EmptyHint(
                      text: notebooks.isEmpty
                          ? 'No notebooks yet.\nUse the picker above to create your first one.'
                          : 'Pick a notebook from the picker above to see its sections.',
                    )
                  : _SectionList(
                      notebookId: notebook.id,
                      collapsedSections: _collapsedSections,
                      onToggleSection: _toggleSection,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notebook picker ────────────────────────────────────────────────────────

/// The glass card at the top of the sidebar: the notebook's colour, its name in
/// the display face, and the chevron that opens the switcher below it.
class _NotebookPickerCard extends StatelessWidget {
  const _NotebookPickerCard({
    required this.notebook,
    required this.open,
    required this.onToggle,
  });

  final Notebook? notebook;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = notebook?.name ?? 'No notebook';
    final dot = notebook?.color ?? scheme.onSurfaceVariant;
    final radius = BorderRadius.circular(MarioRadius.md);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: marioShadow(context, level: 0),
      ),
      child: MarioGlass(
        opacity: 0.62,
        borderRadius: radius,
        border: Border.all(color: marioDivider(context)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggle,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Tooltip(
                      message: name,
                      waitDuration: const Duration(milliseconds: 500),
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: text.headlineSmall?.copyWith(fontSize: 17),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _NotebookAction { rename, delete }

/// The switcher the picker opens: every notebook, its colour and selected
/// state, each row carrying the rail's old rename / recolor / delete menu, and
/// the "New notebook" action underneath.
class _NotebookSwitcher extends ConsumerWidget {
  const _NotebookSwitcher({
    required this.notebooks,
    required this.selectedId,
    required this.onClose,
  });

  final List<Notebook> notebooks;
  final String? selectedId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius = BorderRadius.circular(MarioRadius.md);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: marioShadow(context, level: 1),
        ),
        child: MarioGlass(
          opacity: 0.62,
          borderRadius: radius,
          border: Border.all(color: marioDivider(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notebooks.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      for (final nb in notebooks)
                        _NotebookRow(
                          notebook: nb,
                          selected: nb.id == selectedId,
                          onTap: () {
                            ref
                                .read(selectionProvider.notifier)
                                .selectNotebook(nb.id);
                            onClose();
                          },
                          onMenu: (a) => _handleAction(context, ref, nb, a),
                        ),
                    ],
                  ),
                ),
              Container(height: 1, color: marioDivider(context)),
              _SwitcherAction(
                icon: Icons.add,
                label: 'New notebook',
                onTap: () => _create(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Carried over verbatim from NotebookRail.
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
    onClose();
  }

  /// Carried over verbatim from NotebookRail.
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

class _NotebookRow extends StatelessWidget {
  const _NotebookRow({
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
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(MarioRadius.md);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: selected ? _selectedFill(context) : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
          borderRadius: radius,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: notebook.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      notebook.name,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        fontSize: 14,
                        height: 1.2,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (selected)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child:
                          Icon(Icons.check, size: 15, color: scheme.onSurface),
                    ),
                  _MenuButton<_NotebookAction>(
                    onSelected: onMenu,
                    items: const [
                      ('Rename / recolor', _NotebookAction.rename),
                      ('Delete', _NotebookAction.delete),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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

class _SwitcherAction extends StatelessWidget {
  const _SwitcherAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, size: 16, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: text.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Primary action ─────────────────────────────────────────────────────────

/// The coral "New page" pill. Disabled until a section is open, because a page
/// has to be created into one.
class _NewPageButton extends ConsumerWidget {
  const _NewPageButton({required this.notebookId, required this.sectionId});

  final String? notebookId;
  final String? sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final enabled = notebookId != null && sectionId != null;
    final radius = BorderRadius.circular(MarioRadius.pill);

    return Tooltip(
      message: enabled
          ? 'Add a page to the open section'
          : 'Pick a notebook and section first',
      waitDuration: const Duration(milliseconds: 500),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: scheme.primary,
          borderRadius: radius,
          child: InkWell(
            onTap: enabled ? () => _createPage(context, ref) : null,
            borderRadius: radius,
            child: SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 17, color: scheme.onPrimary),
                  const SizedBox(width: 8),
                  Text(
                    'New page',
                    style: text.titleLarge?.copyWith(
                      fontSize: 15,
                      color: scheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
}

/// The "Add" chip beside the Sections kicker — the old footer's section action.
class _AddSectionChip extends ConsumerWidget {
  const _AddSectionChip({required this.notebookId});

  final String notebookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(MarioRadius.pill);

    return Tooltip(
      message: 'New section',
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: radius,
        child: InkWell(
          onTap: () => _createSection(context, ref),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.create_new_folder_outlined,
                    size: 13, color: scheme.primary),
                const SizedBox(width: 5),
                Text(
                  'Add',
                  style: text.labelSmall?.copyWith(
                    fontSize: 11,
                    letterSpacing: 0.2,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
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
}

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

class _SectionGroup extends ConsumerStatefulWidget {
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
  ConsumerState<_SectionGroup> createState() => _SectionGroupState();
}

class _SectionGroupState extends ConsumerState<_SectionGroup> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final section = widget.section;
    final selection = ref.watch(selectionProvider);
    final isActiveSection = section.id == selection.sectionId;
    final color = MarioColors.labelPalette[section.colorIndex.clamp(0, 5)];
    final radius = BorderRadius.circular(MarioRadius.md);

    // The badge shows the section's real page count, straight off the same
    // stream the nested list renders. While the stream is still loading there
    // is no number to show, so the badge simply does not render.
    final pageCount = ref
        .watch(pagesStreamProvider(
            (notebookId: section.notebookId, sectionId: section.id)))
        .valueOrNull
        ?.length;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                onTap: () {
                  ref
                      .read(selectionProvider.notifier)
                      .selectSection(section.id);
                  if (!widget.expanded) widget.onToggle();
                },
                onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
                borderRadius: radius,
                child: SizedBox(
                  height: 34,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: widget.onToggle,
                          borderRadius: BorderRadius.circular(MarioRadius.sm),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: AnimatedRotation(
                              duration: const Duration(milliseconds: 150),
                              turns: widget.expanded ? 0.0 : -0.25,
                              child: Icon(
                                Icons.expand_more,
                                size: 15,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        MarioSectionBar(
                          color: isActiveSection
                              ? color
                              : color.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            section.name,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              fontSize: 14,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // The design draws the count; rename / delete is the
                        // app's own and rides alongside it, revealed on hover.
                        if (pageCount != null) MarioCountBadge(pageCount),
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
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            crossFadeState: widget.expanded
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
    if (result != null) widget.onMenu(result);
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
    final text = Theme.of(context).textTheme;
    final selection = ref.watch(selectionProvider);

    // The 2px rail that runs down the group, drawn as the container's left
    // border so it always matches the group's real height.
    Widget rail(Widget child) => Container(
          margin: const EdgeInsets.only(left: 17, bottom: 4),
          padding: const EdgeInsets.only(left: 9),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: MarioColors.accent300, width: 2),
            ),
          ),
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
      data: (pages) {
        if (pages.isEmpty) {
          return rail(
            Padding(
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

class _PageTile extends StatefulWidget {
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
  State<_PageTile> createState() => _PageTileState();
}

class _PageTileState extends State<_PageTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final selected = widget.selected;
    final radius = BorderRadius.circular(MarioRadius.md);

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? _selectedFill(context) : Colors.transparent,
            borderRadius: radius,
            border: selected ? Border.all(color: marioDivider(context)) : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              onTap: widget.onTap,
              onSecondaryTapDown: (d) => _showMenu(context, d.globalPosition),
              borderRadius: radius,
              child: SizedBox(
                height: 38,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.page.title.isEmpty
                              ? 'Untitled'
                              : widget.page.title,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            fontSize: 14,
                            height: 1.2,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                      // Same trade as the section rows: quiet by default,
                      // menu on hover, right-click anywhere on the row. Export
                      // has no other entry point here, so it must not be
                      // hover-only on touch.
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
