/// Global search on the desktop builds: a Spotlight-style panel.
///
/// The classic Ultra Thick material floats in the upper part of the window
/// over a light dim, with a large search field on top and the matches under
/// it as a macOS list: each page's title, with where it lives on the line
/// below. It is the palette's own search ([GlobalSearchState]) — titles only,
/// in the same order — with the same keys: ↑ ↓ move (round the ends), ↵
/// opens, esc closes. Escape first empties a field that has text, as
/// Spotlight's does; the kit's search field does that by itself, and the
/// next Escape closes the panel.
///
/// The mouse follows the Mac list rather than the palette: a click
/// highlights a row, a double-click (or ↵) opens it — the same as the page
/// tables in the desktop window.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/shell_state.dart';
import 'global_search.dart';

/// Spotlight's proportions: a panel about 680 wide whose top edge sits a
/// little under a fifth of the way down the window.
const double _kPanelWidth = 680;
const double _kTopFraction = 0.18;

/// The results area once there is a query. Spotlight keeps one height
/// whatever the count, so the panel does not jump as matches come and go;
/// this is about nine rows. A short window gets less (it is flexible).
const double _kResultsHeight = 380;

/// The panel's inner margin: the list's own row inset, so the field and the
/// highlighted row share their left and right edges.
const double _kInset = 10;

/// Shows the panel. [initialQuery] arrives already typed.
void showMacGlobalSearch(BuildContext context, {String initialQuery = ''}) {
  final theme = AppleTheme.of(context);
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  showGeneralDialog<void>(
    context: context,
    // Spotlight closes on a click anywhere outside it.
    barrierDismissible: true,
    barrierLabel: 'Close Search',
    // The kit's sheet overlay (black 20 %): a light dim that keeps the
    // window recognisable behind the panel.
    barrierColor: theme.mac.black.withValues(alpha: 0.2),
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
    pageBuilder: (_, __, ___) => AppleTheme(
      data: theme,
      child: MacGlobalSearchPanel(initialQuery: initialQuery),
    ),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

/// The panel itself, placed in the window the route covers.
class MacGlobalSearchPanel extends ConsumerStatefulWidget {
  const MacGlobalSearchPanel({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<MacGlobalSearchPanel> createState() =>
      _MacGlobalSearchPanelState();
}

class _MacGlobalSearchPanelState extends ConsumerState<MacGlobalSearchPanel>
    with GlobalSearchState<MacGlobalSearchPanel> {
  late final _field = TextEditingController.fromValue(TextEditingValue(
    text: widget.initialQuery,
    selection: TextSelection.collapsed(offset: widget.initialQuery.length),
  ));
  final _scroll = ScrollController();
  final _results = GlobalKey(debugLabel: 'search results');

  @override
  void initState() {
    super.initState();
    query = widget.initialQuery.trim();
  }

  @override
  void dispose() {
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A new query starts at the top of its results.
  @override
  void setQuery(String text) {
    super.setQuery(text);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// The keys move the highlight, so they also keep it in view.
  @override
  void move(int delta) {
    final before = cursor;
    super.move(delta);
    if (cursor != before) _reveal(upward: cursor < before);
  }

  /// A click moves the highlight there (the field keeps the keyboard, so ↵
  /// then opens it).
  void _highlight(Set<Object> ids) {
    if (ids.isEmpty) return;
    setState(() => cursor = ids.first as int);
  }

  /// A double-click opens the row.
  void _openRow(Object id) {
    setState(() => cursor = id as int);
    submit();
  }

  void _reveal({required bool upward}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      // The first row comes back with its group title above it.
      if (cursor == 0) {
        _scroll.jumpTo(0);
        return;
      }
      final row = _highlightedRow();
      if (row == null) return;
      Scrollable.ensureVisible(
        row,
        alignmentPolicy: upward
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  /// The highlighted row. [MacList] keeps its rows to itself, but it marks
  /// the selected one as selected for screen readers — and that mark is how
  /// the panel finds the row to scroll to.
  BuildContext? _highlightedRow() {
    Element? found;
    void visit(Element e) {
      if (found != null) return;
      final w = e.widget;
      if (w is Semantics && (w.properties.selected ?? false)) {
        found = e;
        return;
      }
      e.visitChildren(visit);
    }

    _results.currentContext?.visitChildElements(visit);
    return found;
  }

  /// Where the create action files the page: "In Physics › Mechanics".
  String? _createTarget() {
    final sel = ref.read(selectionProvider);
    final notebookId = sel.notebookId;
    if (notebookId == null) return null;
    final notebook = (ref.read(notebooksStreamProvider).valueOrNull ?? const [])
        .where((n) => n.id == notebookId)
        .firstOrNull;
    final section =
        (ref.read(sectionsStreamProvider(notebookId)).valueOrNull ?? const [])
            .where((s) => s.id == sel.sectionId)
            .firstOrNull;
    final parts = [notebook?.name, section?.name]
        .whereType<String>()
        .where((s) => s.isNotEmpty);
    return parts.isEmpty ? null : 'In ${parts.join(' › ')}';
  }

  @override
  Widget build(BuildContext context) {
    final hits = search();
    final creating = canCreate;

    final Widget body;
    if (query.isEmpty) {
      body = const MacEmptyState(
        title: 'Search by Title',
        message: 'Type part of a page, section or notebook name.',
      );
    } else {
      body = Flexible(
        child: SizedBox(
          height: _kResultsHeight,
          child: (hits.isEmpty && !creating)
              ? MacEmptyState(
                  title: 'No Results',
                  message: 'No page, section or notebook matches “$query”.',
                )
              : _resultList(hits, creating),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, window) => Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(20, window.maxHeight * _kTopFraction, 20, 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kPanelWidth),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: 'Search',
              // The whole panel counts as part of the field: a desktop text
              // field lets go of the keyboard on a click outside it, and a
              // click on a result must leave typing and ↑ ↓ ↵ where they are.
              child: TextFieldTapRegion(
                child: MacGlass(
                  style: MacGlassStyle.panel,
                  child: Focus(
                    onKeyEvent: onKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(_kInset),
                          // The kit's search field at its largest size (XL,
                          // 36 px). Spotlight's own field is a borderless
                          // 22-point line, but the kit has no such control and
                          // a hand-made one would be a look-alike: XL keeps the
                          // real field — bezel, clear button, Escape to clear,
                          // focus ring — at the biggest size the kit defines.
                          child: MacSearchField(
                            controller: _field,
                            size: MacControlSize.xl,
                            autofocus: true,
                            placeholder: 'Search Pages',
                            semanticLabel: 'Search pages',
                            onChanged: setQuery,
                            onSubmitted: (_) => submit(),
                          ),
                        ),
                        body,
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

  /// The matches as Mac lists: Pages, then the create action under its own
  /// title. The lists never take the keyboard ([ExcludeFocus]) — the field
  /// keeps it, so typing and ↑ ↓ ↵ still work after a click in a list.
  Widget _resultList(List<GlobalSearchHit> hits, bool creating) {
    return ExcludeFocus(
      child: MacScrollView(
        key: _results,
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: _kInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hits.isNotEmpty)
              MacList(
                semanticLabel: 'Pages',
                header: 'Pages',
                items: [
                  for (var i = 0; i < hits.length; i++)
                    MacListItem(
                      id: i,
                      title: hits[i].page.title.isEmpty
                          ? 'Untitled'
                          : hits[i].page.title,
                      subtitle: hits[i].breadcrumb,
                      icon: AppleIcons.docText,
                    ),
                ],
                selection: cursor < hits.length ? {cursor} : const {},
                onSelectionChanged: _highlight,
                onItemAction: _openRow,
              ),
            if (creating)
              MacList(
                semanticLabel: 'Actions',
                header: 'Actions',
                items: [
                  MacListItem(
                    id: hits.length,
                    title: 'New Page “$query”',
                    subtitle: _createTarget(),
                    icon: AppleIcons.squareAndPencil,
                  ),
                ],
                selection: cursor == hits.length ? {cursor} : const {},
                onSelectionChanged: _highlight,
                onItemAction: _openRow,
              ),
          ],
        ),
      ),
    );
  }
}
