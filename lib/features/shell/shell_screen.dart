/// ShellScreen — the Simple design's three bands:
///   - a 43px top bar
///   - a 35px notebook strip, full width, above everything else
///   - a 248px collapsible sidebar (sections + pages) beside the canvas
///
/// Notebooks moved out of the sidebar and onto the strip, which is what lets
/// the sidebar be a single flat tree. The canvas answers with the recents
/// home screen whenever no page is open — the state the strip's leading
/// "Recent" tab selects.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/note_page.dart';
import '../../core/models/notebook.dart';
import '../../ui/colors.dart';
import '../../ui/organic.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/resizable_panel.dart';
import '../ai/ai_side_panel.dart';
import '../auth/auth_notifier.dart';
import '../editor/editor_screen.dart';
import 'dialogs/notebook_dialog.dart';
import 'dialogs/text_input_dialog.dart';
import 'keyboard_shortcuts.dart';
import 'nav_tree.dart';
import 'notebook_tabs.dart';
import 'shell_state.dart';
import 'toolbar.dart';

/// The design's sidebar width. Still draggable — this is only where it starts.
const double kSidebarWidth = 248;

/// How wide the recents list is allowed to get.
///
/// Wider than the artboard's 720: that number is a reading measure for prose,
/// and these rows are a title, a breadcrumb and a timestamp with a large gap
/// between them — the measure that suits a paragraph leaves them stretched
/// apart on a wide display.
const double _kRecentsMaxWidth = 960;

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  @override
  Widget build(BuildContext context) {
    final onHome = ref.watch(selectionProvider).home;
    final treeCollapsed = ref.watch(sidebarCollapsedProvider);

    return GlobalShortcuts(
      child: Scaffold(
        appBar: const ShellToolbar(),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Full width, above the split — notebooks are a property of the
            // window, not of the pane the sidebar happens to be showing.
            const NotebookTabBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Recents runs full width. The tree is scoped to one
                  // notebook and the list deliberately is not, so beside it
                  // the sidebar would be answering a different question.
                  if (!onHome)
                    if (treeCollapsed)
                      _CollapsedTreeStrip(
                        onExpand: () => ref
                            .read(sidebarCollapsedProvider.notifier)
                            .state = false,
                      )
                    else
                      const ResizablePanel(
                        initialWidth: kSidebarWidth,
                        minWidth: 200,
                        maxWidth: 420,
                        child: NavTree(),
                      ),
                  const Expanded(child: _EditorHost()),
                  // Renders nothing until opened, so the editor keeps its
                  // full width.
                  const AiSidePanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim strip shown when the sidebar is collapsed; click to expand.
///
/// Painted in the sidebar's own tone, so the collapsed state reads as the
/// same chrome as the sidebar it replaces on all four grounds.
class _CollapsedTreeStrip extends StatelessWidget {
  const _CollapsedTreeStrip({required this.onExpand});
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 28,
      child: MarioSurface(
        border: Border(right: BorderSide(color: marioDivider(context))),
        child: Material(
          color: Colors.transparent,
          child: Tooltip(
            message: 'Expand sidebar',
            child: InkWell(
              onTap: onExpand,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: MarioSpace.x3),
                  child: Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
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

    final notebooksAsync = ref.watch(notebooksStreamProvider);
    final notebooks = notebooksAsync.valueOrNull ?? const <Notebook>[];

    final pagesAsync = (notebookId != null && sectionId != null)
        ? ref.watch(
            pagesStreamProvider((notebookId: notebookId, sectionId: sectionId)))
        : null;
    final pages = pagesAsync?.valueOrNull ?? const <NotePage>[];
    final page = pages.where((p) => p.id == pageId).firstOrNull;

    // Which canvas. Both empty states claim emptiness only once the stream
    // behind them has actually settled AND is not in error — a stream that
    // fails while still holding a stale, empty cached list has `hasError` and
    // `hasValue` at the same time, and "Start your first notebook" shown
    // mid-outage to someone who owns twenty is exactly the lie this guard
    // exists to prevent. Anything unsettled falls through to [_Landing],
    // which already states loading and failure in words.
    final Widget canvas;
    if (selection.home) {
      canvas = const _Recents();
    } else if (page != null) {
      canvas = EditorScreen(key: ValueKey(page.id), page: page);
    } else if (notebooksAsync.hasValue &&
        !notebooksAsync.hasError &&
        notebooks.isEmpty) {
      canvas = const _NoNotebooks();
    } else if (pagesAsync != null &&
        pagesAsync.hasValue &&
        !pagesAsync.hasError &&
        pages.isEmpty) {
      canvas = const _EmptySection();
    } else {
      canvas = const _Recents();
    }

    return Container(color: scheme.surface, child: canvas);
  }
}

// ── Recents ───────────────────────────────────────────────────────────────

/// The home screen: everything you have written, newest edit first.
///
/// The remodel replaces the old landing page — a greeting, a status line and
/// a grid of notebook cards — with the one thing you actually came back for.
/// Notebooks are on the strip above now, so a grid of them here would just be
/// a second copy of the same navigation.
///
/// It runs full width, with no sidebar. That is the artboard's own layout,
/// and it follows from what the screen is: recents cross every notebook, so
/// a per-notebook tree beside them would be scoped to something the list
/// deliberately is not.
class _Recents extends ConsumerWidget {
  const _Recents();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = marioTokens(context);
    final text = Theme.of(context).textTheme;
    final recents = ref.watch(recentPagesProvider);
    final selection = ref.watch(selectionProvider);
    final notebooksAsync = ref.watch(notebooksStreamProvider);

    // A page can only be created into a section, so the action is live only
    // once the shell has one. Disabled beats guessing a target.
    final canCreatePage =
        selection.notebookId != null && selection.sectionId != null;

    final groups = _group(recents, DateTime.now());

    // On the ground, with the list on its own bounded surface.
    //
    // The artboard runs this at 720px on plain paper, which on a 1272px
    // artboard reads as a page. On a real 1920px display it read as a narrow
    // ribbon of text floating in an empty pane, with nothing to say where it
    // began or ended — so it gets an edge, and room to use the width it has.
    return Container(
      color: t.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kRecentsMaxWidth),
            child: Container(
              decoration: BoxDecoration(
                color: t.paper,
                borderRadius: BorderRadius.circular(MarioRadius.lg),
                border: Border.all(color: t.line),
              ),
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('Recent', style: text.displayMedium),
                      const Spacer(),
                      _HeadAction(
                        icon: Icons.add,
                        label: 'New page',
                        emphasised: true,
                        onTap: canCreatePage
                            ? () => _createPage(context, ref)
                            : null,
                        disabledHint: 'Pick a notebook and section first',
                      ),
                      const SizedBox(width: 16),
                      _HeadAction(
                        icon: Icons.library_add_outlined,
                        label: 'New notebook',
                        onTap: () => _createNotebook(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  if (groups.isEmpty)
                    _EmptyNote(
                      text: notebooksAsync.hasValue && !notebooksAsync.hasError
                          ? 'Nothing written yet. Create a notebook to get started.'
                          : notebooksAsync.hasError
                              ? 'Your notebooks could not be loaded.'
                              : 'Loading your pages…',
                    )
                  else
                    for (var g = 0; g < groups.length; g++) ...[
                      if (g > 0) const SizedBox(height: 30),
                      MarioKicker(groups[g].label),
                      const SizedBox(height: 6),
                      for (var i = 0; i < groups[g].rows.length; i++)
                        _RecentRow(
                          entry: groups[g].rows[i],
                          now: DateTime.now(),
                          // The artboard closes each block with a rule under
                          // its final row.
                          last: i == groups[g].rows.length - 1,
                        ),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One dated block of the recents list.
class _RecentGroup {
  const _RecentGroup(this.label, this.rows);
  final String label;
  final List<RecentPage> rows;
}

/// Split by calendar day, the way the artboard does — Today, Yesterday, and
/// everything before that in one block.
List<_RecentGroup> _group(List<RecentPage> all, DateTime now) {
  if (all.isEmpty) return const [];
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  final t = <RecentPage>[], y = <RecentPage>[], older = <RecentPage>[];
  for (final r in all) {
    final u = r.page.updatedAt;
    final day = DateTime(u.year, u.month, u.day);
    if (!day.isBefore(today)) {
      t.add(r);
    } else if (!day.isBefore(yesterday)) {
      y.add(r);
    } else {
      older.add(r);
    }
  }

  return [
    if (t.isNotEmpty) _RecentGroup('Today', t),
    if (y.isNotEmpty) _RecentGroup('Yesterday', y),
    if (older.isNotEmpty) _RecentGroup('Earlier', older),
  ];
}

/// A create action in the recents header — icon, then label. The primary one
/// is w600 ink; the secondary sits in the secondary tone.
class _HeadAction extends StatelessWidget {
  const _HeadAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasised = false,
    this.disabledHint,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool emphasised;
  final String? disabledHint;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    final enabled = onTap != null;

    final row = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: t.mut),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.2,
              fontWeight: emphasised ? FontWeight.w600 : FontWeight.w400,
              color: emphasised ? t.ink : t.sec,
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: enabled ? label : (disabledHint ?? label),
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: row,
      ),
    );
  }
}

/// One 52px row: title over its breadcrumb, with the edit time trailing.
class _RecentRow extends ConsumerWidget {
  const _RecentRow({
    required this.entry,
    required this.now,
    required this.last,
  });

  final RecentPage entry;
  final DateTime now;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = marioTokens(context);
    final page = entry.page;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.line),
          bottom: last ? BorderSide(color: t.line) : BorderSide.none,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => ref.read(selectionProvider.notifier).selectPage(
                page.id,
                sectionId: entry.sectionId,
                notebookId: page.notebookId,
              ),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        page.title.isEmpty ? 'Untitled' : page.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: t.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.breadcrumb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, height: 1.2, color: t.mut),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  _ago(page.updatedAt, now),
                  style: TextStyle(fontSize: 12.5, height: 1.2, color: t.mut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "12 min ago", "2 h ago", "1 d ago" — the artboard's own shorthand.
String _ago(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 365) return '${d.inDays} d ago';
  return '${(d.inDays / 365).floor()} y ago';
}

// ── The two create flows ──────────────────────────────────────────────────
//
// Top-level rather than methods on [_Landing] because three screens now offer
// them — the landing, the first-run empty state and the empty-section state —
// and a second copy of either would be a second thing to keep in step with the
// keyboard shortcuts.

/// Same flow the Ctrl+N shortcut and the old rail's "+" used.
Future<void> _createNotebook(BuildContext context, WidgetRef ref) async {
  final user = ref.read(authStateProvider).valueOrNull;
  if (user == null) return;
  final result = await showNotebookDialog(
    context,
    title: 'New notebook',
    submitLabel: 'Create',
  );
  if (result == null) return;
  final now = DateTime.now();
  final id = await ref.read(syncServiceProvider).createNotebook(
        Notebook(
          id: '',
          name: result.name,
          ownerId: user.uid,
          colorIndex: result.colorIndex,
          createdAt: now,
          updatedAt: now,
        ),
      );
  ref.read(selectionProvider.notifier).selectNotebook(id);
}

/// Same flow as the sidebar footer's "Page" and the Ctrl+Alt+N shortcut.
Future<void> _createPage(BuildContext context, WidgetRef ref) async {
  final selection = ref.read(selectionProvider);
  final notebookId = selection.notebookId;
  final sectionId = selection.sectionId;
  if (notebookId == null || sectionId == null) return;
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
  final now = DateTime.now();
  final id = await ref.read(syncServiceProvider).createPage(
        NotePage(
          id: '',
          sectionId: sectionId,
          notebookId: notebookId,
          title: title,
          order: pages.length,
          createdAt: now,
          updatedAt: now,
        ),
      );
  ref.read(selectionProvider.notifier).selectPage(id);
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MarioSpace.x4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(MarioRadius.card),
        boxShadow: marioShadow(context, level: 0),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

// ── Empty states ──────────────────────────────────────────────────────────
//
// The design's principle for these is "every empty state offers the next
// action" — so each one below ends in a control, and every control here runs
// the same real flow the sidebar and the keyboard shortcuts run. Two of the
// design's actions are missing rather than mocked:
//
//   * "Import from Markdown" on the first-run state. There is no importer in
//     this app. `lib/features/export/` holds a Markdown exporter and a PDF
//     exporter and nothing that reads a file back in; `FilePicker` is only
//     ever called for `saveFile`, plus `.xlsx` into a spreadsheet block and an
//     image into a page. A button offering to import Markdown would have had
//     nothing to call.
//
//   * "Photograph a page — OCR pulls the text out" on the section state.
//     [OcrService] is real and `isAvailable` is honest, but both of its call
//     sites (`MarioImageBlock._maybeRunOcr` and `NoteImageReader`) start from
//     an image node that is ALREADY inside an open page's document and write
//     their result back through an `EditorState` transaction. There is no
//     picture -> OCR -> new page flow to point at, and building one is out of
//     scope.
//
//   * "Dictate a note". [VoiceDictationButton] is the only dictation entry
//     point and it requires an `afe.EditorState`, which it uses to insert each
//     interim transcript at the caret. The shell has no EditorState — the one
//     that exists is private to `_EditorScreenBody`, and no provider publishes
//     it — so from here there is nothing to start. Dictation stays where it
//     works: the mic in the editor toolbar, once a page is open.

/// The accent disc behind an empty state's icon.
///
/// Gold is a FILL in this system, never ink: on the light grounds the disc is
/// `accent100` with `accent700` on it, and on the dark ones a 20% `accent400`
/// wash with `accent200` on it — the same pairing [MarioTag]'s accent tone
/// uses, so it is already known to hold on all four grounds.
class _AccentIcon extends StatelessWidget {
  const _AccentIcon({required this.icon, this.size = 44});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = marioMode(context).isDark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark
            ? MarioColors.accent400.withValues(alpha: 0.20)
            : MarioColors.accent100,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: dark ? MarioColors.accent200 : MarioColors.accent700,
      ),
    );
  }
}

/// Centres an empty state in the canvas and lets it scroll when the canvas is
/// shorter than the content — a 400px-tall window must not overflow.
class _EmptyStateFrame extends StatelessWidget {
  const _EmptyStateFrame({required this.child, required this.maxWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: MarioSpace.x8,
          vertical: MarioSpace.x8,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // Clamped: a canvas shorter than its own padding would otherwise
            // ask for a negative minimum and trip BoxConstraints' assertion.
            minHeight: (constraints.maxHeight - MarioSpace.x8 * 2)
                .clamp(0.0, double.infinity),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// First run: the account has no notebooks at all.
///
/// [_Landing] handles the general "no page open" case and would render an
/// empty notebook grid here; this takes over when the count is genuinely
/// zero, because at that point there is exactly one thing worth doing and the
/// screen should say so.
class _NoNotebooks extends ConsumerWidget {
  const _NoNotebooks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return _EmptyStateFrame(
      maxWidth: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _AccentIcon(icon: Icons.menu_book_outlined, size: 76),
          const SizedBox(height: MarioSpace.x6),
          Text(
            'Start your first notebook',
            textAlign: TextAlign.center,
            style: text.displayMedium,
          ),
          const SizedBox(height: MarioSpace.x3),
          Text(
            'A notebook holds sections, and sections hold pages. '
            'One notebook is plenty to begin.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: MarioSpace.x6),
          FilledButton.icon(
            onPressed: () => _createNotebook(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create a notebook'),
          ),
        ],
      ),
    );
  }
}

/// A section is selected and has no pages in it.
///
/// The design lists three next actions here; two of them have nothing behind
/// them in this app and are omitted — see the note at the top of this section.
/// What is left is the one that is real, and it runs the same create flow as
/// the sidebar's "New page" button and Ctrl+Alt+N.
class _EmptySection extends ConsumerWidget {
  const _EmptySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return _EmptyStateFrame(
      maxWidth: 540,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AccentIcon(icon: Icons.article_outlined),
          const SizedBox(height: MarioSpace.x4),
          Text(
            'Nothing in this section yet',
            style: text.displaySmall,
          ),
          const SizedBox(height: MarioSpace.x2),
          // The design's line is "Start with a blank page, or drop in
          // something you already have." The second half advertised the
          // photograph-and-OCR and dictate rows, and with those omitted it
          // would be pointing at controls that are not on the screen. The
          // half that is true is kept.
          Text(
            'Start with a blank page.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: MarioSpace.x6),
          _NextAction(
            icon: Icons.edit_outlined,
            title: 'Blank page',
            description: 'Just start typing',
            onTap: () => _createPage(context, ref),
          ),
        ],
      ),
    );
  }
}

/// One row in an empty state's list of next actions: leading icon, bold title,
/// muted description, trailing chevron.
class _NextAction extends StatelessWidget {
  const _NextAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(MarioRadius.card);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: marioShadow(context, level: 0),
      ),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MarioSpace.x4,
              vertical: MarioSpace.x3,
            ),
            child: Row(
              children: [
                _AccentIcon(icon: icon, size: 38),
                const SizedBox(width: MarioSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: MarioSpace.x1 * 0.5),
                      Text(
                        description,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: MarioSpace.x2),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
