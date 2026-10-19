/// Global search — the redesign's command palette (artboard 2e).
///
/// One palette over pages and actions, with the keyboard as the primary input:
/// ↑↓ moves, ↵ opens, esc closes. The design draws a content snippet under each
/// hit ("…net torque about an axis…") and a footer reading "Searches titles and
/// content" — this searches TITLES ONLY until the Drift FTS5 index lands, so it
/// says titles, and shows the breadcrumb where the snippet would go. Promising
/// content search that does not happen would be worse than the honest label.
///
/// The design also offers an "Ask Mario about …" action. The AI panel can be
/// opened ([AiPanelNotifier.open]) but has no API for handing it a question, so
/// the row would drop the text the user just typed. It is omitted until there
/// is something to hand the question to.
///
/// The desktop builds show the same search as a Spotlight-style panel
/// (`mac_global_search.dart`). Both looks run on [GlobalSearchState], so what
/// matches and what the keys do cannot drift apart between them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/note_page.dart';
import '../../ui/colors.dart';
import '../../ui/mac/mac_look.dart';
import '../../ui/organic.dart';
import '../../ui/theme.dart';
import '../shell/shell_state.dart';
import 'mac_global_search.dart';

/// One page whose notebook, section or title matches the query.
class GlobalSearchHit {
  final String notebookId;
  final String notebookName;
  final String sectionId;
  final String? sectionName;
  final NotePage page;

  const GlobalSearchHit({
    required this.notebookId,
    required this.notebookName,
    required this.sectionId,
    required this.sectionName,
    required this.page,
  });

  /// Where the page lives — "Physics › Mechanics" — which is what the
  /// palette shows in place of a content snippet (see the library comment).
  String get breadcrumb =>
      sectionName == null ? notebookName : '$notebookName › $sectionName';
}

/// Opens the palette. [initialQuery] arrives already typed — the desktop
/// toolbar's search field hands over its text on Return — and the default
/// opens it empty, as the shortcut does.
void showGlobalSearch(BuildContext context, {String initialQuery = ''}) {
  if (useMacLook) {
    showMacGlobalSearch(context, initialQuery: initialQuery);
    return;
  }
  // The design dims the page behind the palette with its own neutral-900,
  // which is the mark's navy. That is right on three grounds and wrong on the
  // fourth: over Black's pure #000 a navy scrim is simply a blue wash, because
  // there is no navy in that ground for it to agree with. Black dims with
  // black — and harder, since it has no ambient light to lose.
  final black = marioMode(context) == MarioThemeMode.black;
  showDialog(
    context: context,
    barrierColor: black
        ? Colors.black.withValues(alpha: 0.52)
        : MarioColors.navy.withValues(alpha: 0.16),
    builder: (_) => _GlobalSearchDialog(initialQuery: initialQuery),
  );
}

/// What the palette does, whichever look draws it: the query, the matches,
/// the cursor over them (the hits, then the create action one past them),
/// and what ↑ ↓ ↵ esc do.
mixin GlobalSearchState<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  /// The query as typed, trimmed.
  String query = '';

  /// The highlighted row: an index into [search], or [search]'s length for
  /// the create action.
  int cursor = 0;

  /// A new query starts the cursor over at the first row.
  void setQuery(String text) => setState(() {
        query = text.trim();
        cursor = 0;
      });

  List<GlobalSearchHit> search() {
    final lower = query.toLowerCase();
    if (lower.isEmpty) return const [];
    final notebooks = ref.read(notebooksStreamProvider).valueOrNull ?? [];
    final hits = <GlobalSearchHit>[];
    for (final nb in notebooks) {
      final sections =
          ref.read(sectionsStreamProvider(nb.id)).valueOrNull ?? [];
      for (final s in sections) {
        final pages = ref
                .read(pagesStreamProvider((notebookId: nb.id, sectionId: s.id)))
                .valueOrNull ??
            [];
        for (final p in pages) {
          if ('${nb.name} ${s.name} ${p.title}'.toLowerCase().contains(lower)) {
            hits.add(GlobalSearchHit(
              notebookId: nb.id,
              notebookName: nb.name,
              sectionId: s.id,
              sectionName: s.name,
              page: p,
            ));
          }
        }
      }
    }
    return hits;
  }

  /// A page can only be created into a section, so the action exists only when
  /// the shell has one open. Offering it otherwise would have nowhere to file
  /// the result.
  bool get canCreate {
    final sel = ref.read(selectionProvider);
    return query.isNotEmpty && sel.notebookId != null && sel.sectionId != null;
  }

  int get rowCount => search().length + (canCreate ? 1 : 0);

  void move(int delta) {
    final n = rowCount;
    if (n == 0) return;
    setState(() => cursor = (cursor + delta) % n < 0
        ? (cursor + delta) % n + n
        : (cursor + delta) % n);
  }

  /// ↵: opens the highlighted hit, or runs the create action.
  void submit() {
    final hits = search();
    if (cursor < hits.length) {
      open(hits[cursor]);
    } else if (canCreate) {
      create();
    }
  }

  void open(GlobalSearchHit h) {
    final sel = ref.read(selectionProvider.notifier);
    sel.selectNotebook(h.notebookId);
    sel.selectSection(h.sectionId);
    sel.selectPage(h.page.id);
    Navigator.of(context).pop();
  }

  Future<void> create() async {
    final sel = ref.read(selectionProvider);
    final nid = sel.notebookId;
    final sid = sel.sectionId;
    if (nid == null || sid == null) return;
    final pages = ref
            .read(pagesStreamProvider((notebookId: nid, sectionId: sid)))
            .valueOrNull ??
        const [];
    final now = DateTime.now();
    final id = await ref.read(syncServiceProvider).createPage(NotePage(
          id: '',
          sectionId: sid,
          notebookId: nid,
          title: query,
          order: pages.length,
          createdAt: now,
          updatedAt: now,
        ));
    if (!mounted) return;
    ref.read(selectionProvider.notifier).selectPage(id);
    Navigator.of(context).pop();
  }

  KeyEventResult onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        submit();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

class _GlobalSearchDialog extends ConsumerStatefulWidget {
  const _GlobalSearchDialog({this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<_GlobalSearchDialog> createState() =>
      _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<_GlobalSearchDialog>
    with GlobalSearchState<_GlobalSearchDialog> {
  final _focus = FocusNode();
  late final _field = TextEditingController.fromValue(TextEditingValue(
    text: widget.initialQuery,
    selection: TextSelection.collapsed(offset: widget.initialQuery.length),
  ));

  @override
  void initState() {
    super.initState();
    query = widget.initialQuery.trim();
  }

  @override
  void dispose() {
    _focus.dispose();
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    final scheme = Theme.of(context).colorScheme;
    final hits = search();

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 96),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
          child: MarioSurface(
            borderRadius: BorderRadius.circular(MarioRadius.lg),
            // The palette is an opaque panel now, not a veil. It floats over a
            // scrim rather than over the page, so nothing has to stay legible
            // *through* it and no blur is needed to buy that legibility back.
            color: scheme.surfaceContainerHigh,
            border: Border.all(color: marioDivider(context)),
            shadow: marioShadow(context, level: 2),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(MarioRadius.lg),
              clipBehavior: Clip.antiAlias,
              child: Focus(
                onKeyEvent: onKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── query row ──────────────────────────────────────────────
                    Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: t.line)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 19, color: t.mut),
                          const SizedBox(width: 11),
                          Expanded(
                            child: TextField(
                              controller: _field,
                              autofocus: true,
                              focusNode: _focus,
                              cursorColor: t.ink,
                              cursorWidth: 1,
                              style: TextStyle(
                                  fontSize: 15, height: 1.2, color: t.ink),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: 'Search pages',
                                hintStyle: TextStyle(
                                    fontSize: 15, height: 1.2, color: t.mut),
                              ),
                              onChanged: setQuery,
                              onSubmitted: (_) => submit(),
                            ),
                          ),
                          const SizedBox(width: 11),
                          const MarioKeyHint('esc'),
                        ],
                      ),
                    ),
                    Flexible(
                      child: query.isEmpty
                          ? const _Hint('Type to search your pages by title.')
                          : (hits.isEmpty && !canCreate)
                              ? const _Hint('No matches.')
                              : ListView(
                                  shrinkWrap: true,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  children: [
                                    if (hits.isNotEmpty) ...[
                                      const _GroupLabel('Pages'),
                                      for (var i = 0; i < hits.length; i++)
                                        _HitRow(
                                          hit: hits[i],
                                          selected: i == cursor,
                                          onTap: () => open(hits[i]),
                                        ),
                                    ],
                                    if (canCreate) ...[
                                      const _GroupLabel('Actions'),
                                      _ActionRow(
                                        icon: Icons.note_add_outlined,
                                        label: 'New page called “$query”',
                                        selected: cursor == hits.length,
                                        onTap: create,
                                      ),
                                    ],
                                  ],
                                ),
                    ),
                    // ── footer ─────────────────────────────────────────────────
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.line)),
                      ),
                      child: Row(
                        children: [
                          // The artboard's three hints, in its order. `esc`
                          // is not among them because the query row already
                          // carries it, on the right of the field.
                          _FootHint('↑↓ move'),
                          const SizedBox(width: 16),
                          _FootHint('⏎ open'),
                          const SizedBox(width: 16),
                          // No split view behind this one yet — ⇧⏎ opens the
                          // hit normally. It names something the app owes.
                          _FootHint('⇧⏎ open in split'),
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
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: MarioKicker(label),
      );
}

class _HitRow extends StatelessWidget {
  const _HitRow({
    required this.hit,
    required this.selected,
    required this.onTap,
  });

  final GlobalSearchHit hit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);

    return MarioAccentEdge(
      active: selected,
      child: Material(
        color: selected ? t.fill : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 17, color: t.sec),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hit.page.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: t.ink,
                          ),
                        ),
                        Text(
                          hit.breadcrumb,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, height: 1.3, color: t.mut),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    hit.notebookName,
                    style: TextStyle(fontSize: 11.5, height: 1.2, color: t.mut),
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);

    return MarioAccentEdge(
      active: selected,
      child: Material(
        color: selected ? t.fill : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: t.sec),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13.5, height: 1.2, color: t.ink),
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
}

class _FootHint extends StatelessWidget {
  const _FootHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.2,
          color: marioTokens(context).mut,
        ),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: marioTokens(context).mut,
            ),
          ),
        ),
      );
}
