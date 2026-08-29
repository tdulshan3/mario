/// ShellScreen — two-zone layout:
///   - 284px collapsible sidebar (notebook picker + sections + pages, merged)
///   - editor canvas (everything else)
///
/// The old 60px NotebookRail is gone: the redesign folds the notebook switcher
/// into the sidebar itself, so a column is no longer spent on six avatars. The
/// canvas answers with a real home screen when no page is open — a greeting, a
/// count of what is synced, the two create actions and the notebook list —
/// instead of the old "Pick a page to start writing" placeholder.
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
import 'shell_state.dart';
import 'toolbar.dart';

/// The design's sidebar width. Still draggable — this is only where it starts.
const double kSidebarWidth = 284;

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
            if (_treeCollapsed)
              _CollapsedTreeStrip(onExpand: _toggleTree)
            else
              ResizablePanel(
                initialWidth: kSidebarWidth,
                minWidth: 220,
                maxWidth: 420,
                child: NavTree(onCollapse: _toggleTree),
              ),
            const Expanded(child: _EditorHost()),
            // Renders nothing until opened, so the editor keeps its full width.
            const AiSidePanel(),
          ],
        ),
      ),
    );
  }
}

/// Slim strip shown when the sidebar is collapsed; click to expand.
///
/// Glass rather than a flat panel, so the collapsed state reads as the same
/// chrome as the sidebar it replaces on all four grounds.
class _CollapsedTreeStrip extends StatelessWidget {
  const _CollapsedTreeStrip({required this.onExpand});
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 28,
      child: MarioGlass(
        opacity: 0.62,
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
        ? ref.watch(pagesStreamProvider(
            (notebookId: notebookId, sectionId: sectionId)))
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
    if (page != null) {
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
      canvas = const _Landing();
    }

    return Container(color: scheme.surface, child: canvas);
  }
}

// ── Landing ───────────────────────────────────────────────────────────────

/// The home screen the canvas shows when no page is open.
///
/// Everything on it is real: the greeting reads the clock and the signed-in
/// user, the subtitle counts the notebooks the live stream has delivered, and
/// each card counts that notebook's sections. Nothing here is filled in with a
/// stand-in number — a slot with no data behind it simply does not render.
class _Landing extends ConsumerWidget {
  const _Landing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final notebooksAsync = ref.watch(notebooksStreamProvider);
    final notebooks = notebooksAsync.valueOrNull ?? const <Notebook>[];
    final selection = ref.watch(selectionProvider);
    final user = ref.watch(authStateProvider).valueOrNull;

    // A page can only be created into a section, so the action is live only
    // when the sidebar has both settled. Disabled beats guessing a target.
    final canCreatePage =
        selection.notebookId != null && selection.sectionId != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          MarioSpace.x8, MarioSpace.x8, MarioSpace.x8, MarioSpace.x8 * 1.5),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(DateTime.now(), user?.displayName),
                style: text.displayLarge?.copyWith(fontSize: 38),
              ),
              const SizedBox(height: MarioSpace.x2),
              Text(
                _statusLine(notebooksAsync, notebooks.length),
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: MarioSpace.x6),
              Wrap(
                spacing: MarioSpace.x3,
                runSpacing: MarioSpace.x2,
                children: [
                  FilledButton.icon(
                    onPressed: () => _createNotebook(context, ref),
                    icon: const Icon(Icons.library_add_outlined, size: 18),
                    label: const Text('New notebook'),
                  ),
                  Tooltip(
                    message: canCreatePage
                        ? 'Add a page to the open section'
                        : 'Pick a notebook and section first',
                    child: OutlinedButton.icon(
                      onPressed:
                          canCreatePage ? () => _createPage(context, ref) : null,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New page'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MarioSpace.x8),
              Row(
                children: [
                  const MarioKicker('Notebooks'),
                  if (notebooksAsync.hasValue) ...[
                    const SizedBox(width: MarioSpace.x2),
                    MarioCountBadge(notebooks.length),
                  ],
                ],
              ),
              const SizedBox(height: MarioSpace.x3),
              if (notebooks.isEmpty)
                _EmptyNote(
                  text: notebooksAsync.hasValue
                      ? 'Nothing here yet. Create a notebook to get started.'
                      : notebooksAsync.hasError
                          ? 'Your notebooks could not be loaded.'
                          : 'Loading your notebooks…',
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 620 ? 2 : 1;
                    const gap = MarioSpace.x3;
                    final width =
                        ((constraints.maxWidth - gap * (columns - 1)) / columns)
                            .floorToDouble();
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final nb in notebooks)
                          SizedBox(
                            width: width,
                            child: _NotebookCard(notebook: nb),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Time-aware, and named only when the account actually carries a name.
  static String _greeting(DateTime now, String? displayName) {
    final part = now.hour < 12
        ? 'Morning'
        : now.hour < 17
            ? 'Afternoon'
            : 'Evening';
    final name = (displayName ?? '').trim().split(RegExp(r'\s+')).first;
    if (name.isEmpty) return 'Good ${part.toLowerCase()}';
    return '$part, $name';
  }

  /// The count, and nothing the app cannot actually observe.
  ///
  /// The design's line is "Four notebooks, all synced." — but nothing here
  /// knows whether anything is synced. [MarioFirestore.watchCollection] hands
  /// back documents with no `hasPendingWrites` or `fromCache` metadata, and no
  /// sync-status provider exists, so "all synced" would be a claim the app is
  /// in no position to make — worst of all during an outage, which is exactly
  /// when someone would read it and believe it.
  ///
  /// So the count is stated and the sync half is dropped. The error case is
  /// checked BEFORE the value case on purpose: a stream that fails while still
  /// holding a cached list has both `hasError` and `hasValue`, and reporting
  /// the stale count as though nothing were wrong is the failure this ordering
  /// exists to prevent.
  static String _statusLine(AsyncValue<List<Notebook>> async, int count) {
    if (async.hasError) {
      return 'Your notebooks could not be reached just now.';
    }
    if (async.isLoading && !async.hasValue) return 'Checking your notebooks…';
    if (count == 0) return 'No notebooks yet.';
    if (count == 1) return 'One notebook.';
    return '${_spell(count)} notebooks.';
  }

  static const _words = [
    'No',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
  ];

  static String _spell(int n) => n < _words.length ? _words[n] : '$n';

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

/// One notebook, as a card: colour dot with its initial, name, and the counts
/// the providers can actually answer for.
class _NotebookCard extends ConsumerWidget {
  const _NotebookCard({required this.notebook});

  final Notebook notebook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(MarioRadius.card);

    // Sections are one stream per notebook, so this count is real and cheap.
    // Page counts would need a stream per section of every notebook, so the
    // line carries only what is genuinely known.
    final sections = ref.watch(sectionsStreamProvider(notebook.id)).valueOrNull;
    final meta = sections == null
        ? ''
        : '${sections.length} ${sections.length == 1 ? 'section' : 'sections'}';

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
          onTap: () =>
              ref.read(selectionProvider.notifier).selectNotebook(notebook.id),
          child: Padding(
            padding: const EdgeInsets.all(MarioSpace.x4),
            child: Row(
              children: [
                _ColorInitial(notebook: notebook),
                const SizedBox(width: MarioSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        notebook.name.trim().isEmpty
                            ? 'Untitled'
                            : notebook.name,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge,
                      ),
                      const SizedBox(height: MarioSpace.x1 * 0.5),
                      Text(
                        meta,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
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

/// The notebook's colour as a disc, with its initial in the display face.
/// Ink is chosen against the disc, not the ground, so it holds on all four.
class _ColorInitial extends StatelessWidget {
  const _ColorInitial({required this.notebook});

  static const double size = 38;

  final Notebook notebook;

  @override
  Widget build(BuildContext context) {
    final name = notebook.name.trim();
    final initial = name.isEmpty ? '·' : name[0].toUpperCase();
    final ink = notebook.color.computeLuminance() > 0.5
        ? MarioColors.navy
        : MarioColors.neutral100;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: notebook.color,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontSize: size * 0.39, color: ink),
      ),
    );
  }
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
