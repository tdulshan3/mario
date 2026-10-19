/// What the desktop window shows when no page is open: the pages of the
/// place picked in the sidebar, as a Finder-style table.
///
///   Recents   every page, newest edit first, grouped Today / Yesterday /
///             Earlier, with where each one lives
///   notebook  its pages, grouped by section
///   section   its pages, in their sidebar order
///
/// Double-click or Return opens a page. When there is nothing to list, the
/// pane says so and offers the one action that would change that.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/note_page.dart';
import '../../../core/models/notebook.dart';
import '../../../core/models/section.dart';
import '../shell_actions.dart';
import '../shell_state.dart';

/// One table row: a page and where it lives.
class _Row {
  const _Row(this.page, this.location);
  final NotePage page;
  final String location;
}

/// "Today at 9:41 AM", "Yesterday at 5:20 PM", "4 Oct 2026 at 6:05 PM" —
/// Finder's Date Modified column.
String macDateLabel(DateTime d, DateTime now) {
  final time = DateFormat.jm().format(d);
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Today at $time';
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday at $time';
  }
  return '${DateFormat.yMMMd().format(d)} at $time';
}

void _open(WidgetRef ref, NotePage page) =>
    ref.read(selectionProvider.notifier).selectPage(
          page.id,
          sectionId: page.sectionId,
          notebookId: page.notebookId,
        );

/// The page table, sized to fill the content pane.
class _PageTable extends StatefulWidget {
  const _PageTable({
    required this.label,
    required this.onOpen,
    this.rows = const [],
    this.groups,
    this.showLocation = false,
  });

  final String label;
  final ValueChanged<NotePage> onOpen;
  final List<_Row> rows;
  final List<MacTableGroup<_Row>>? groups;
  final bool showLocation;

  @override
  State<_PageTable> createState() => _PageTableState();
}

class _PageTableState extends State<_PageTable> {
  Set<Object> _selection = const {};

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return MacTable<_Row>(
      semanticLabel: widget.label,
      columns: [
        MacTableColumn<_Row>(
          title: 'Title',
          value: (r) => r.page.title.toLowerCase(),
          text: (r) => r.page.title.isEmpty ? 'Untitled' : r.page.title,
          flex: 3,
        ),
        if (widget.showLocation)
          MacTableColumn<_Row>(
            title: 'Location',
            value: (r) => r.location.toLowerCase(),
            text: (r) => r.location,
            flex: 2,
          ),
        MacTableColumn<_Row>(
          title: 'Date Modified',
          value: (r) => r.page.updatedAt,
          text: (r) => macDateLabel(r.page.updatedAt, now),
          width: 200,
        ),
      ],
      rows: widget.rows,
      groups: widget.groups,
      rowId: (r) => r.page.id,
      icon: (_) => const MacTableIcon(AppleIcons.docText),
      selection: _selection,
      onSelectionChanged: (ids) => setState(() => _selection = ids),
      onRowAction: (r) => widget.onOpen(r.page),
    );
  }
}

/// An empty pane: what is missing, and the button that fixes it.
class _EmptyPane extends StatelessWidget {
  const _EmptyPane({
    required this.title,
    this.message,
    this.action,
    this.onAction,
  });

  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return MacContent(
      scroll: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MacEmptyState(title: title, message: message),
            if (action != null) ...[
              const SizedBox(height: 16),
              MacButton(label: action, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// Recents: every page, newest edit first.
class MacRecentsBrowser extends ConsumerWidget {
  const MacRecentsBrowser({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentPagesProvider);
    final notebooksAsync = ref.watch(notebooksStreamProvider);

    if (recents.isEmpty) {
      if (notebooksAsync.hasError) {
        return const _EmptyPane(
          title: 'Notebooks Unavailable',
          message: 'Your notebooks could not be loaded.',
        );
      }
      if (!notebooksAsync.hasValue) {
        return const MacContent(
          scroll: false,
          child: Center(child: MacSpinner()),
        );
      }
      if ((notebooksAsync.valueOrNull ?? const []).isEmpty) {
        return _EmptyPane(
          title: 'No Notebooks',
          message: 'A notebook holds sections, and sections hold pages. '
              'One notebook is plenty to begin.',
          action: 'New Notebook…',
          onAction: () => createNotebook(context, ref),
        );
      }
      return const _EmptyPane(
        title: 'No Pages',
        message: 'Pages you write appear here, newest first.',
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final t = <_Row>[], y = <_Row>[], older = <_Row>[];
    for (final r in recents) {
      final u = r.page.updatedAt;
      final day = DateTime(u.year, u.month, u.day);
      final row = _Row(r.page, '${r.sectionName} · ${r.notebookName}');
      if (!day.isBefore(today)) {
        t.add(row);
      } else if (!day.isBefore(yesterday)) {
        y.add(row);
      } else {
        older.add(row);
      }
    }

    return _PageTable(
      label: 'Recents',
      showLocation: true,
      onOpen: (p) => _open(ref, p),
      groups: [
        if (t.isNotEmpty) MacTableGroup(title: 'Today', rows: t),
        if (y.isNotEmpty) MacTableGroup(title: 'Yesterday', rows: y),
        if (older.isNotEmpty) MacTableGroup(title: 'Earlier', rows: older),
      ],
    );
  }
}

/// A notebook's pages, grouped by section.
class MacNotebookBrowser extends ConsumerWidget {
  const MacNotebookBrowser({super.key, required this.notebook});

  final Notebook notebook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(sectionsStreamProvider(notebook.id));
    final sections = sectionsAsync.valueOrNull ?? const <Section>[];
    if (!sectionsAsync.hasValue) {
      return const MacContent(
        scroll: false,
        child: Center(child: MacSpinner()),
      );
    }
    if (sections.isEmpty) {
      return _EmptyPane(
        title: 'No Sections',
        message: 'Sections hold the pages of a notebook.',
        action: 'New Section…',
        onAction: () => createSection(context, ref, notebook.id),
      );
    }

    final groups = <MacTableGroup<_Row>>[];
    for (final s in sections) {
      final pages = ref
              .watch(pagesStreamProvider(
                  (notebookId: notebook.id, sectionId: s.id)))
              .valueOrNull ??
          const <NotePage>[];
      if (pages.isEmpty) continue;
      groups.add(MacTableGroup(
        title: s.name.isEmpty ? 'Untitled' : s.name,
        rows: [for (final p in pages) _Row(p, s.name)],
      ));
    }
    if (groups.isEmpty) {
      return const _EmptyPane(
        title: 'No Pages',
        message: 'Choose a section in the sidebar, then New Page.',
      );
    }
    return _PageTable(
      label: notebook.name,
      onOpen: (p) => _open(ref, p),
      groups: groups,
    );
  }
}

/// A section's pages.
class MacSectionBrowser extends ConsumerWidget {
  const MacSectionBrowser({
    super.key,
    required this.notebookId,
    required this.sectionId,
  });

  final String notebookId;
  final String sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pagesAsync = ref.watch(
        pagesStreamProvider((notebookId: notebookId, sectionId: sectionId)));
    if (!pagesAsync.hasValue) {
      return pagesAsync.hasError
          ? const _EmptyPane(
              title: 'Pages Unavailable',
              message: 'This section could not be loaded.',
            )
          : const MacContent(scroll: false, child: Center(child: MacSpinner()));
    }
    final pages = pagesAsync.value!;
    if (pages.isEmpty) {
      return _EmptyPane(
        title: 'No Pages',
        message: 'Start with a blank page.',
        action: 'New Page…',
        onAction: () => createPage(
          context,
          ref,
          notebookId: notebookId,
          sectionId: sectionId,
        ),
      );
    }
    return _PageTable(
      label: 'Pages',
      onOpen: (p) => _open(ref, p),
      rows: [for (final p in pages) _Row(p, '')],
    );
  }
}
