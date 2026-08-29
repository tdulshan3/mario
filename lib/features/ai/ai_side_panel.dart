/// The AI panel, docked on the right of the editor.
///
/// It lives in [ShellScreen]'s Row rather than inside the editor's own column,
/// for two reasons. The editor canvas is wrapped in zoom, `Transform.scale`,
/// `OverflowBox` and a horizontal scroller whose sizing maths all assume it
/// owns its width; splitting that region is where the layout bugs live.
/// And an answer half-streamed should survive the user clicking another page
/// to check something, which a panel owned by the page cannot do.
///
/// Four tabs: Ask (which `/ask` and `/summary` drive), Quiz, Writing, and Do
/// — the agent, which edits the page directly. "Do" is the label the design
/// gives the agent tab; the enum member is still [AiPanelTab.agent].
///
/// The chrome is the design's: a glass header carrying the four tabs as pills,
/// and a glass composer docked at the foot of *every* tab. The composer runs
/// nothing itself — it hands the question to the Ask tab by the same route
/// `/ask` and `/summary` take, so there stays exactly one ask pathway, with one
/// history and one saved artifact per answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/ai/local_model_discovery.dart';
import '../../ui/colors.dart';
import '../../ui/organic.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/mario_loader.dart';
import '../../ui/widgets/resizable_panel.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_state.dart';
import 'agent_panel.dart';
import 'ai_progress.dart';
import 'ai_session_state.dart';
import 'ai_state.dart';
import 'ask_panel.dart';
import 'model_bar.dart';
import 'quiz_panel.dart';
import 'writing_panel.dart';

/// The panel plus its collapsed strip. Renders nothing when closed except a
/// hairline rail, so the editor keeps its full width.
class AiSidePanel extends ConsumerWidget {
  const AiSidePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(aiPanelProvider);

    // Highlighting a passage brings the panel up on the Ask tab, ready to
    // answer about it. Listened for here rather than inside AskPanel, because
    // when the panel is shut AskPanel is not in the tree to hear it — which is
    // exactly the case that needs to open it.
    //
    // The editor only publishes a selection that has settled and is long enough
    // to be deliberate (see _onSelectionChanged), so this does not fire on
    // every drag while someone is editing.
    final askOnHighlight =
        ref.watch(settingsProvider).valueOrNull?.askOnHighlight ?? true;
    ref.listen<String?>(editorSelectionProvider, (previous, next) {
      if (!askOnHighlight) return;
      if (next == null || next.trim().isEmpty) return;
      if (previous == next) return;
      ref.read(askSessionProvider.notifier).quote(next);
      ref.read(aiPanelProvider.notifier).showTab(AiPanelTab.ask);
    });

    if (!panel.isOpen) return const SizedBox.shrink();

    // 400 is the width the design states. It stays the *initial* width rather
    // than a fixed one: the drag handle was already here, and someone who has
    // widened the panel to read a long answer should keep that.
    return ResizablePanel(
      edge: PanelEdge.left,
      initialWidth: 400,
      minWidth: 280,
      maxWidth: 560,
      child: _PanelBody(tab: panel.tab),
    );
  }
}

class _PanelBody extends ConsumerStatefulWidget {
  const _PanelBody({required this.tab});

  final AiPanelTab tab;

  @override
  ConsumerState<_PanelBody> createState() => _PanelBodyState();
}

class _PanelBodyState extends ConsumerState<_PanelBody> {
  /// The composer's real laid-out height, measured rather than assumed.
  double _composerHeight = kComposerReserve;

  /// Bumped every time the docked composer hands a question to the Ask tab.
  ///
  /// [AskPanel] collects a pending question in its `initState`, so a question
  /// submitted while it is *already* on screen would never be picked up.
  /// Changing its key remounts it, which is deliberately cheap here: the run,
  /// the draft, the quoted passage and the history all live in
  /// [askSessionProvider] rather than in the widget — which is the whole point
  /// of `ai_session_state.dart`.
  int _askEpoch = 0;

  /// The same trick for the Do tab. [AgentPanel] collects its pending
  /// instruction in `initState`, so remounting is what makes a second
  /// instruction, typed while the tab is already open, actually run.
  int _agentEpoch = 0;

  /// The one ask pathway. `/ask`, `/summary` and this composer all go through
  /// [AiPanelNotifier.askQuestion], so the question is run, saved to the
  /// artifact store and added to history exactly once, by [AskPanel].
  void _handOffToAsk(String question) {
    setState(() => _askEpoch++);
    ref.read(aiPanelProvider.notifier).askQuestion(question);
  }

  /// The Do tab's equivalent. The composer is one control on every tab, but it
  /// is not one *destination*: on Do the text is an instruction that edits the
  /// page, not a question to be answered, and sending it to Ask — which is what
  /// used to happen — meant the Do tab's own box was the only thing that
  /// actually did anything, with a second, larger box sitting above it that did
  /// not.
  void _handOffToAgent(String instruction) {
    setState(() => _agentEpoch++);
    ref.read(aiPanelProvider.notifier).runInstruction(instruction);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backends = ref.watch(aiConfigsProvider);
    final notifier = ref.read(aiPanelProvider.notifier);

    // The composer only appears once a backend exists. Before that the panel is
    // showing _NeedsSetup, AskPanel is not mounted to collect a pending
    // question, and a composer there would be a control that does nothing.
    final ready = backends.valueOrNull?.isNotEmpty ?? false;

    return Material(
      color: scheme.surfaceContainerHighest,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: marioDivider(context))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              tab: widget.tab,
              onTab: notifier.showTab,
              onClose: notifier.close,
            ),
            const _Hairline(),
            // Which model is answering, and how much of its window the last
            // request used. Above the tabs' content because it applies to all
            // of them.
            _ActiveModelBar(tab: widget.tab),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ComposerReserve(
                      height: _composerHeight,
                      child: backends.when(
                        loading: () =>
                            const Center(child: MarioLoader(size: 30)),
                        error: (e, _) => _NeedsSetup(
                            message: 'Could not load AI settings: $e'),
                        data: (configs) => configs.isEmpty
                            ? const _NeedsSetup()
                            : switch (widget.tab) {
                                AiPanelTab.ask =>
                                  AskPanel(key: ValueKey(_askEpoch)),
                                AiPanelTab.quiz => const QuizPanel(),
                                AiPanelTab.writing => const WritingPanel(),
                                AiPanelTab.agent =>
                                  AgentPanel(key: ValueKey(_agentEpoch)),
                              },
                      ),
                    ),
                  ),
                  // Floating, not docked: it sits over the tab's content with
                  // an inset all round, so the answer scrolls behind its glass
                  // instead of stopping at a hard rule above it. Each panel
                  // reserves kComposerReserve at the foot of its scroll view
                  // so the last line can still be scrolled clear of it.
                  if (ready)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _MeasureHeight(
                        onChange: (h) {
                          if (h == _composerHeight) return;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _composerHeight = h);
                          });
                        },
                        child: _Composer(
                          tab: widget.tab,
                          onSubmit: widget.tab == AiPanelTab.agent
                              ? _handOffToAgent
                              : _handOffToAsk,
                          onSummarise: () => _handOffToAsk(kSummaryRequest),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-pixel rule in the theme's divider tone.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: marioDivider(context));
}

/// The glass header: the four tabs as pills, and the close button, on one row.
class _Header extends StatelessWidget {
  const _Header({
    required this.tab,
    required this.onTab,
    required this.onClose,
  });

  final AiPanelTab tab;
  final ValueChanged<AiPanelTab> onTab;
  final VoidCallback onClose;

  /// The design's order, labels and icons. The fourth reads "Do"; the tab it
  /// selects is still [AiPanelTab.agent] — only the wording differs, so nothing
  /// else in the app has to know about the rename.
  static const _tabs = <(AiPanelTab, String, IconData)>[
    (AiPanelTab.ask, 'Ask', Icons.auto_awesome),
    (AiPanelTab.quiz, 'Quiz', Icons.grid_view_outlined),
    (AiPanelTab.writing, 'Writing', Icons.text_fields),
    (AiPanelTab.agent, 'Do', Icons.auto_fix_high),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MarioGlass(
      // No blur. The header sits on the flat opaque Material this file wraps
      // the panel in, so the filter produces byte-identical output — and it
      // re-runs on every streamed token, because it is inside the subtree that
      // rebuilds per token.
      blur: 0,
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(
          MarioSpace.x2, MarioSpace.x2, MarioSpace.x1, MarioSpace.x2),
      child: Row(
        children: [
          // Scrolls rather than overflows. Four labelled pills fit comfortably
          // at the design's 400, but the panel can still be dragged down to
          // 280, where they do not — and a dropped label is a tab nobody can
          // read.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (id, label, icon) in _tabs) ...[
                    _TabPill(
                      label: label,
                      icon: icon,
                      selected: tab == id,
                      onTap: () => onTab(id),
                    ),
                    const SizedBox(width: MarioSpace.x1),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Gold is a light colour, so the selected pill carries the navy ink —
    // never the ground.
    final fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Material(
      color: selected ? scheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(MarioRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MarioRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: MarioSpace.x2, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      height: 1,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The fixed widths the composer's row is budgeted from. They are stated here
/// rather than read back from the widgets because the budget has to be struck
/// before the row is built.
const double _kSparkle = 16;
const double _kRoundChip = 28;
const double _kSendButton = 30;

/// The narrowest the question field may get before the web control gives up
/// its wording — about the width of "Ask about this page…" at the composer's
/// text size. Narrower than this the hint is clipped mid-word and the field
/// stops reading as somewhere to type; the wording is the cheapest thing in
/// the row to give up, because the tooltip already says the same.
/// The narrowest the question field may get before the web chip drops its
/// label.
///
/// Measured, not chosen: the "Ask about this page…" hint lays out at 138.7px,
/// and the previous 132 clipped it by a few pixels at exactly the width where
/// the label first appeared — the one width where the row is tightest.
const double _kMinField = 140;

/// The composer docked at the foot of every tab.
///
/// It owns no AI logic. What is typed here is handed to the Ask tab, which runs
/// it, saves it and shows it — one pathway rather than two that can drift apart.
class _Composer extends ConsumerStatefulWidget {
  const _Composer({
    required this.tab,
    required this.onSubmit,
    required this.onSummarise,
  });

  /// Which tab is showing. The composer looks the same everywhere; where the
  /// text *goes* is not the same everywhere, and neither are the controls
  /// beside it — web search and "summarise above the cursor" belong to a
  /// question, not to an instruction that edits the page.
  final AiPanelTab tab;

  final ValueChanged<String> onSubmit;
  final VoidCallback onSummarise;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  bool get _isAgent => widget.tab == AiPanelTab.agent;

  /// The draft this tab is writing. Ask and Do keep separate ones: an
  /// instruction half-typed on Do should still be there after a look at an
  /// answer, and it must not turn into a question.
  String get _draft => _isAgent
      ? ref.read(agentSessionProvider).draft
      : ref.read(askSessionProvider).draft;

  void _setDraft(String value) => _isAgent
      ? ref.read(agentSessionProvider.notifier).setDraft(value)
      : ref.read(askSessionProvider.notifier).setDraft(value);

  @override
  void initState() {
    super.initState();
    // Read once, then write back on every change. The draft is shared with the
    // Ask tab's own composer, so a half-written question survives a look at the
    // quiz — but *watching* it here would fight that field for the cursor.
    _controller = TextEditingController(text: _draft);
  }

  @override
  void didUpdateWidget(_Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching tabs switches which draft this box is showing. Without this the
    // question typed on Ask would still be sitting there on Do, ready to be
    // sent to the agent as an instruction.
    if (widget.tab != oldWidget.tab) {
      final next = _draft;
      if (_controller.text != next) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _setDraft('');
    widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Asking needs an open page: the answer is about the note, and the Ask tab
    // bails out when there is no editor bridge. Better to say so in the hint
    // than to offer a send button that quietly does nothing.
    final hasPage = ref.watch(aiEditorBridgeProvider.select((b) => b != null));
    final useWeb = ref.watch(askSessionProvider.select((s) => s.useWeb));
    // A run in flight owns the page; a second instruction queued on top of it
    // would leave two sets of edits and one snapshot to undo them with.
    final agentBusy = _isAgent &&
        ref.watch(agentSessionProvider
            .select((s) => s.run?.value.status == AiRunStatus.running));
    final enabled = hasPage && !agentBusy;

    return Padding(
      padding: const EdgeInsets.all(MarioSpace.x2),
      child: MarioGlass(
        // No blur. This one floats directly over the streaming answer, which
        // is the worst place in the app for a backdrop filter: it re-runs on
        // every token *and* on every scroll frame, and because its backdrop
        // changes constantly it can never be raster-cached. The veil stays, so
        // the composer still reads as glass.
        blur: 0,
        borderRadius: BorderRadius.circular(MarioRadius.pill),
        border: Border.all(color: marioDivider(context)),
        padding: const EdgeInsets.fromLTRB(MarioSpace.x3, 4, 4, 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The row is budgeted rather than guessed at.
            //
            // Everything in it is a fixed size except the web control, whose
            // wording changes with the state, the font and the reader's text
            // size — so that one width is measured, and the wording is only
            // kept while what is left over still leaves the question field
            // wide enough to read. Dragged narrower than that, the control
            // keeps its icon, its colour and its tap target and moves the
            // wording into its tooltip, rather than standing there in gold
            // with the field squeezed to a slot beside it.
            //
            // Everything beside the field, left to right: the sparkle and its
            // gutter, the web chip's own trailing gap, the summarise chip and
            // its gap, then the gap before the send button and the button.
            const besideTheField = _kSparkle +
                MarioSpace.x3 +
                MarioSpace.x2 +
                _kRoundChip +
                MarioSpace.x2 +
                MarioSpace.x2 +
                _kSendButton;
            bool roomForLabel() =>
                constraints.maxWidth -
                    besideTheField -
                    _WebChip.widthFor(context, useWeb, showLabel: true) >=
                MediaQuery.textScalerOf(context).scale(_kMinField);
            final showLabel = !_isAgent && roomForLabel();
            return Row(
              children: [
                // Not scheme.primary: gold on the cream and white grounds
                // measures 1.59:1 and 1.66:1, so the icon all but disappears
                // on half the themes. Same trade as the toolbar's active Ask
                // button — take a ramp step that separates from the ground and
                // keep the gold identity, rather than keep the exact hue and
                // lose the icon.
                Icon(_isAgent ? Icons.auto_fix_high : Icons.auto_awesome,
                    size: _kSparkle,
                    color: marioMode(context).isDark
                        ? scheme.primary
                        : MarioColors.accent700),
                // A full gutter, not a hairline: the sparkle is drawn in the
                // primary and so is the web chip's fill when web search is on,
                // and two gold shapes any closer than this read as one.
                const SizedBox(width: MarioSpace.x3),
                // Web search and "summarise above the cursor" are things you do
                // to a question. On Do the text is an edit to the page, so the
                // row is just the box and the send button.
                if (!_isAgent) ...[
                  _WebChip(
                    value: useWeb,
                    showLabel: showLabel,
                    onTap: ref.read(askSessionProvider.notifier).cycleWeb,
                  ),
                  const SizedBox(width: MarioSpace.x2),
                  _RoundChip(
                    icon: Icons.format_quote,
                    tooltip: hasPage
                        ? 'Summarise the notes above the cursor'
                        : 'Open a page to summarise it',
                    onTap: hasPage ? widget.onSummarise : null,
                  ),
                  const SizedBox(width: MarioSpace.x2),
                ],
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    enabled: enabled,
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    onChanged: _setDraft,
                    onSubmitted: (_) => _submit(),
                    style: text.bodySmall,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      hintMaxLines: 1,
                      hintText: switch ((hasPage, _isAgent, agentBusy)) {
                        (false, true, _) => 'Open a page to edit it',
                        (false, false, _) => 'Open a page to ask about it',
                        (_, true, true) => 'Working on the page…',
                        (_, true, false) => 'Change this page…',
                        _ => 'Ask about this page…',
                      },
                      hintStyle: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(width: MarioSpace.x2),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => _SendButton(
                    onTap: enabled && value.text.trim().isNotEmpty
                        ? _submit
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The web-search control — three states, because that is what the app has.
///
/// It reads and writes [AskSession.useWeb], the same value the Ask tab's own
/// toggle drives and the same one handed to `AiTasks.ask`: null means "decide
/// from the question" (`looksLikeItNeedsSearch`), true forces a search, false
/// forbids one. "Off" is a requirement rather than a preference — a search
/// sends a question derived from private notes to a third party.
class _WebChip extends StatelessWidget {
  const _WebChip({
    required this.value,
    required this.showLabel,
    required this.onTap,
  });

  final bool? value;
  final bool showLabel;
  final VoidCallback onTap;

  static const double _icon = 15;
  static const double _padWithLabel = 8;
  static const double _padIconOnly = 6;
  static const double _iconToLabel = 4;

  /// Icon, wording and tooltip for each state, in one place — the composer
  /// measures the wording to decide whether the row can afford it, and a
  /// second copy of these strings would let the budget and the chip disagree.
  static (IconData, String, String) _face(bool? value) => switch (value) {
        true => (Icons.public, 'Web: on', 'Web search: on for every question'),
        false => (Icons.public_off, 'Web: off', 'Web search: never'),
        null => (
            Icons.travel_explore,
            'Web: auto',
            'Web search: only when the question needs it'
          ),
      };

  static TextStyle? _labelStyle(BuildContext context, Color color) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            height: 1,
            fontWeight: FontWeight.w600,
            color: color,
          );

  /// How wide this chip will lay out, asked before it is built.
  ///
  /// The composer needs the number to strike its budget, and it cannot be a
  /// constant: "Web: auto" is wider than "Web: on", the face is whatever the
  /// theme resolves, and both grow with the reader's text size. So it is
  /// measured with the very style [build] will draw with.
  static double widthFor(
    BuildContext context,
    bool? value, {
    required bool showLabel,
  }) {
    if (!showLabel) return _icon + _padIconOnly * 2;
    final painter = TextPainter(
      text: TextSpan(
        text: _face(value).$2,
        style: _labelStyle(context, const Color(0xFF000000)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final label = painter.width;
    painter.dispose();
    return _padWithLabel * 2 + _icon + _iconToLabel + label;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, label, tip) = _face(value);
    // Gold fill with navy ink is this system's "active"; auto and off are
    // quiet, so the one state that always reaches the network stands out.
    final on = value == true;
    final fg = on ? scheme.onPrimary : scheme.onSurfaceVariant;

    return Tooltip(
      message: '$tip. Tap to change.',
      child: Material(
        color: on ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(MarioRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MarioRadius.pill),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: showLabel ? _padWithLabel : _padIconOnly,
                vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: _icon, color: fg),
                if (showLabel) ...[
                  const SizedBox(width: _iconToLabel),
                  Text(label, style: _labelStyle(context, fg)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small round action inside the composer pill. A null [onTap] disables it.
class _RoundChip extends StatelessWidget {
  const _RoundChip({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _kRoundChip,
            height: _kRoundChip,
            child: Icon(
              icon,
              size: 16,
              color: onTap == null
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.45)
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// The send button: gold, with the navy arrow on it.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = onTap != null;
    return Tooltip(
      message: 'Ask',
      child: Material(
        color: on
            ? scheme.primary
            : scheme.onSurfaceVariant.withValues(alpha: 0.16),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _kSendButton,
            height: _kSendButton,
            child: Icon(
              Icons.arrow_upward,
              size: 16,
              // Navy on the gold — the ground never sits on the primary.
              color: on ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// First run: nothing configured yet.
///
/// Rather than only pointing at Settings, this looks for a model server already
/// running on this machine and offers it directly — someone with Ollama going
/// should be one tap from a working panel, not a form.
class _NeedsSetup extends ConsumerWidget {
  const _NeedsSetup({this.message});
  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final found = ref.watch(localModelsProvider);

    final detected = found.maybeWhen(
      data: (endpoints) => endpoints,
      orElse: () => const <DiscoveredEndpoint>[],
    );
    final best = detected.isEmpty ? null : detected.first;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MarioSpace.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_outlined,
                size: 26, color: scheme.onSurfaceVariant),
            const SizedBox(height: MarioSpace.x2),
            Text(
              message ??
                  'No model is set up yet.\n\nMario can use a local model '
                      'through Ollama, any OpenAI-compatible server on your '
                      'network, OpenAI, or Claude.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                fontSize: 12,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (found.isLoading) ...[
              const SizedBox(height: MarioSpace.x3),
              const MarioLoader(size: 20),
              const SizedBox(height: MarioSpace.x1),
              Text(
                'Looking for a local model server…',
                style: text.bodySmall
                    ?.copyWith(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
            if (best != null) ...[
              const SizedBox(height: MarioSpace.x3),
              Text(
                '${best.serverName} is running here with '
                '${best.models.length} model'
                '${best.models.length == 1 ? '' : 's'}.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(
                  fontSize: 11.5,
                  height: 1.4,
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: MarioSpace.x2),
              for (final m in best.models.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: FilledButton.icon(
                    onPressed: () => _use(ref, best, m.name),
                    icon: const Icon(Icons.bolt, size: 15),
                    label: Text(
                      m.sizeLabel.isEmpty
                          ? 'Use ${m.name}'
                          : 'Use ${m.name}  ·  ${m.sizeLabel}',
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: text.labelLarge?.copyWith(fontSize: 11.5),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: MarioSpace.x3),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
              icon: const Icon(Icons.tune, size: 15),
              label: Text(best == null ? 'Set up a model' : 'More options'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: text.labelLarge?.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Saves the picked model and makes it active, so the panel is usable
  /// immediately rather than after a trip to Settings.
  Future<void> _use(
      WidgetRef ref, DiscoveredEndpoint endpoint, String model) async {
    final backends = ref.read(aiBackendsProvider);
    final config = endpoint.toConfig(
      model,
      id: 'llm-${DateTime.now().microsecondsSinceEpoch}',
    );
    await backends.saveConfigs([...backends.configs, config]);
    await backends.setActive(config.id);
    ref.invalidate(aiConfigsProvider);
  }
}

/// The model bar, fed whichever tab's run is currently live.
///
/// Each tab keeps its own run (see ai_session_state.dart), so the usage figure
/// has to follow the tab you are looking at — showing the Ask tab's numbers
/// while the Quiz tab is generating would be worse than showing none.
class _ActiveModelBar extends ConsumerWidget {
  const _ActiveModelBar({required this.tab});

  final AiPanelTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = switch (tab) {
      AiPanelTab.ask => ref.watch(askSessionProvider).run,
      AiPanelTab.quiz => ref.watch(quizSessionProvider).run,
      AiPanelTab.writing => ref.watch(writingSessionProvider).run,
      AiPanelTab.agent => ref.watch(agentSessionProvider).run,
    };
    return ModelBar(run: run);
  }
}

/// Reports its child's laid-out height.
///
/// The composer floats over the tab, so the tab has to reserve exactly what
/// the composer occupies. Measuring beats a constant: the constant was 76 and
/// close enough to look correct, which is precisely why a gold button ended up
/// painted behind the glass instead of above it.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onChange, required super.child});

  final ValueChanged<double> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureHeightBox(onChange);

  @override
  void updateRenderObject(
      BuildContext context, _MeasureHeightBox renderObject) {
    renderObject.onChange = onChange;
  }
}

class _MeasureHeightBox extends RenderProxyBox {
  _MeasureHeightBox(this.onChange);

  ValueChanged<double> onChange;
  double _last = -1;

  @override
  void performLayout() {
    super.performLayout();
    if (size.height != _last) {
      _last = size.height;
      onChange(_last);
    }
  }
}
