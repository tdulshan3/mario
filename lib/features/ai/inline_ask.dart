/// InlineAsk — the ask composer and answer, on the page, when asked for.
///
/// The previous design moved asking into the right-hand panel. This one brings
/// it back to where you are writing: a 36px composer after the last block, and
/// the answer above it as a quiet block marked by a 2px accent bar down its
/// leading edge.
///
/// SUMMONED, not permanent, and AT THE CARET. The artboard draws the composer
/// sitting under the page at all times, which in a real notebook means a
/// control under every document whether or not anyone is asking anything.
/// `/ask` opens it instead — the same slash menu that carries the rest of the
/// AI features — and it closes again on Escape or Discard.
///
/// It lives in the canvas Stack rather than in the document, because a widget
/// in the document can only be at the START or the END of it: as the editor's
/// `footer` it appeared at the foot of the page however far that was from the
/// line you were writing on. Positioned in the Stack it can sit at the caret,
/// which is where you were looking.
///
/// Both departures from the artboard are deliberate.
///
/// This is a VIEW over [askSessionProvider], the same state the Ask tab reads.
/// Asking here and asking there are the same run: the answer appears in both,
/// "Discard" clears both, and a run started inline keeps going if you open the
/// panel to watch it. The panel is still where Write, Agent and Quiz live, and
/// where the question history is.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/ai/ai_artifacts.dart';
import '../../ui/colors.dart';
import '../../ui/organic.dart';
import '../../ui/theme.dart';
import 'ai_markdown.dart';
import 'ai_progress.dart';
import 'ai_session_state.dart';
import 'ai_state.dart';
import 'ai_tasks.dart';

class InlineAsk extends ConsumerStatefulWidget {
  const InlineAsk({super.key, this.inset = 0});

  /// The editor's own horizontal inset.
  ///
  /// AppFlowy wraps each BLOCK in `Padding(editorStyle.padding)` but hands the
  /// footer through unpadded, so this has to carry the inset itself or it
  /// would sit 52px wider than the text it follows.
  final double inset;

  @override
  ConsumerState<InlineAsk> createState() => _InlineAskState();
}

class _InlineAskState extends ConsumerState<InlineAsk> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Takes the question `/ask …` carried in, if there is one.
  ///
  /// Deferred to after the frame: this runs from `build`, and both the seed
  /// hand-back and a submitted run write to providers.
  void _consumeSeed(InlineAskPrompt prompt) {
    if (!prompt.open) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (prompt.seed.isNotEmpty) {
        _controller.text = prompt.seed;
        ref.read(inlineAskProvider.notifier).seedTaken();
        _submit();
      } else if (!_focus.hasFocus) {
        _focus.requestFocus();
      }
    });
  }

  void _close() {
    _controller.clear();
    ref.read(inlineAskProvider.notifier).close();
  }

  void _submit() {
    final question = _controller.text.trim();
    if (question.isEmpty) return;

    final bridge = ref.read(aiEditorBridgeProvider);
    if (bridge == null) return;

    // What was ABOVE the caret when the composer opened, not the whole page.
    // Asking at a point in a page is asking about what leads up to it — the
    // same thing `/summary` means by "the notes above" — and by now the caret
    // is in this text field, so the editor could not work it out any more.
    // Falls back to the whole page when there was no caret to read from.
    final above = ref.read(inlineAskProvider).above;

    final session = ref.read(askSessionProvider);
    final run = ref.read(aiTasksProvider).ask(
          question: question,
          ctx: AiTaskContext(
            notebookId: bridge.notebookId,
            pageId: bridge.pageId,
            note: above ?? bridge.readPage(),
            document: bridge.readDocument(),
          ),
          useWeb: session.useWeb,
          focus: session.quoted,
        );
    ref.read(askSessionProvider.notifier).startRun(run, question: question);
    _controller.clear();
  }

  void _askAgain() {
    final last = ref.read(askSessionProvider).lastQuestion;
    if (last.isEmpty) return;
    _controller.text = last;
    _submit();
  }

  /// The answer, as the page would store it — the same artifact the Ask tab
  /// writes, so an answer inserted from here is indistinguishable from one
  /// inserted from there.
  String _asMarkdown(AiRunState state) {
    final bridge = ref.read(aiEditorBridgeProvider)!;
    final session = ref.read(askSessionProvider);
    return renderAskForPage(AskEntry(
      id: 'inline',
      pageId: bridge.pageId,
      question: session.lastQuestion.isEmpty ? 'Summary' : session.lastQuestion,
      answer: state.answer,
      sources: state.sources,
      usedWeb: state.sources.isNotEmpty,
      provenance: AiProvenance(
        backend: state.backendLabel ?? 'unknown',
        model: '',
        createdAt: DateTime.now(),
      ),
    ));
  }

  Future<void> _insert(AiRunState state) async {
    final bridge = ref.read(aiEditorBridgeProvider);
    if (bridge == null) return;
    final notifier = ref.read(askSessionProvider.notifier)..setInserting(true);
    final ok = await bridge.insertMarkdown(_asMarkdown(state));
    notifier.insertFinished(
        error: ok ? null : 'Could not insert — the page was closed.');
  }

  Future<void> _replace(AiRunState state) async {
    final bridge = ref.read(aiEditorBridgeProvider);
    if (bridge == null) return;
    final notifier = ref.read(askSessionProvider.notifier)..setInserting(true);
    final ok = await bridge.replaceSelection(_asMarkdown(state));
    notifier.insertFinished(
        error: ok ? null : 'Nothing is highlighted to replace.');
  }

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    final prompt = ref.watch(inlineAskProvider);
    final session = ref.watch(askSessionProvider);
    final run = session.run;

    // Nothing to show until someone asks for it. An answer keeps it on screen
    // after the composer itself has been dismissed, so a reply is never
    // yanked away mid-read — Discard is what clears both.
    if (!prompt.open && run == null) return const SizedBox.shrink();

    _consumeSeed(prompt);

    // Deliberately NOT gated on the bridge being published. This only ever
    // mounts inside a page's editor, so "no page" is not a real state here —
    // it is a one-frame gap before `_publishAiBridge` runs its post-frame
    // callback, and hiding the composer for it meant the composer never
    // appeared at all: the footer widget is created once and the null branch
    // is what stuck. `_submit` re-reads the bridge and no-ops without one.
    ref.watch(aiEditorBridgeProvider);

    // Anchored to the caret when there was one. `Positioned.fill` gives this
    // the whole canvas, so the offset is placed against the top and the two
    // insets keep it on the text's own measure.
    //
    // 8px of air under the caret line, so the box sits below what you were
    // writing rather than on top of it. `LayoutBuilder` is what stops a long
    // answer running off the bottom: past halfway the box is anchored by its
    // BOTTOM to the caret instead, and opens upwards.
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (run != null)
          ValueListenableBuilder<AiRunState>(
            valueListenable: run,
            builder: (context, state, _) => Padding(
              padding: const EdgeInsets.only(top: 26),
              child: _Answer(
                state: state,
                question: session.lastQuestion,
                quoted: session.quoted != null,
                busy: session.inserting,
                error: session.insertError,
                onInsert: () => _insert(state),
                onReplace: () => _replace(state),
                onAskAgain: _askAgain,
                onDiscard: () {
                  ref.read(askSessionProvider.notifier).clear();
                  _close();
                },
                onStop: ref.read(askSessionProvider.notifier).stop,
              ),
            ),
          ),
        if (prompt.open)
          Padding(
            padding: EdgeInsets.only(top: run == null ? 0 : 12),
            child: _Composer(
              controller: _controller,
              focus: _focus,
              onSubmit: _submit,
              onDismiss: _close,
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final anchor = prompt.anchor;
        final left = widget.inset;
        final right = widget.inset;

        // Floating over the page, so it needs a ground of its own — text
        // showing through a composer is unreadable, and the border alone does
        // not separate it from the paragraph behind it.
        final surface = Container(
          decoration: BoxDecoration(
            color: t.paper,
            borderRadius: BorderRadius.circular(MarioRadius.lg),
            border: Border.all(color: t.line),
            boxShadow: marioShadow(context, level: 2),
          ),
          padding: const EdgeInsets.all(14),
          child: content,
        );

        // No caret to go by — the foot of the canvas, as before.
        if (anchor == null) {
          return Padding(
            padding: EdgeInsets.only(left: left, right: right, bottom: 40),
            child: Align(alignment: Alignment.bottomCenter, child: surface),
          );
        }

        final top = anchor.dy + 8;
        final opensUpward = top > constraints.maxHeight * 0.5;

        return Stack(
          children: [
            Positioned(
              left: left,
              right: right,
              top: opensUpward ? null : top,
              bottom: opensUpward
                  ? (constraints.maxHeight - anchor.dy + 8).clamp(
                      0.0,
                      constraints.maxHeight,
                    )
                  : null,
              child: surface,
            ),
          ],
        );
      },
    );
  }
}

/// The answer block — a 2px accent bar, a one-line attribution, the answer,
/// and what you can do with it.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.state,
    required this.question,
    required this.quoted,
    required this.busy,
    required this.error,
    required this.onInsert,
    required this.onReplace,
    required this.onAskAgain,
    required this.onDiscard,
    required this.onStop,
  });

  final AiRunState state;
  final String question;
  final bool quoted;
  final bool busy;
  final String? error;
  final VoidCallback onInsert;
  final VoidCallback onReplace;
  final VoidCallback onAskAgain;
  final VoidCallback onDiscard;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    final running = state.isRunning;

    // "Qwen 3.5:0.8b · read this page" — the artboard names the backend and
    // what it looked at. Both are real here: the label comes off the run, and
    // the scope is whether a passage was attached.
    final backend = state.backendLabel;
    final scope = quoted ? 'read your selection' : 'read this page';
    final attribution = backend == null ? scope : '$backend · $scope';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 2, 0, 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.accentBase, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 15, color: t.accentBase),
              const SizedBox(width: 8),
              Text(
                'Mario',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  attribution,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.2, color: t.mut),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (state.error != null)
            Text(
              state.error!,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.6,
                color: Theme.of(context).colorScheme.error,
              ),
            )
          else if (state.answer.isEmpty && running)
            Text(
              'Thinking…',
              style: TextStyle(fontSize: 14.5, height: 1.6, color: t.mut),
            )
          else
            // Rendered, not raw. Models answer in Markdown, and the artboard
            // draws prose — so an answer arriving as "**the** point" has to
            // read as *the* point, not as the asterisks.
            //
            // StreamingMarkdown rather than AiMarkdown, for the same reason
            // the Ask tab uses it: re-parsing the whole answer on every token
            // is quadratic in its length. It renders in one piece once the run
            // finishes, so a selection can span the whole thing.
            DefaultTextStyle.merge(
              style: TextStyle(color: t.body),
              child: StreamingMarkdown(
                state.answer,
                done: !running,
                fontSize: 14.5,
              ),
            ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          // While a run is live the only honest action is to stop it — the
          // answer is still arriving, so inserting it would commit half of it.
          if (running)
            _AnswerAction(
                label: 'Stop', tone: _ActionTone.primary, onTap: onStop)
          else
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _AnswerAction(
                  label: busy ? 'Inserting…' : 'Insert below',
                  tone: _ActionTone.primary,
                  onTap: busy ? null : onInsert,
                ),
                _AnswerAction(
                  label: 'Replace selection',
                  tone: _ActionTone.secondary,
                  onTap: busy ? null : onReplace,
                ),
                _AnswerAction(
                  label: 'Ask again',
                  tone: _ActionTone.secondary,
                  onTap: busy ? null : onAskAgain,
                ),
                _AnswerAction(
                  label: 'Discard',
                  tone: _ActionTone.muted,
                  onTap: busy ? null : onDiscard,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _ActionTone { primary, secondary, muted }

/// One action under an answer. Text only — the artboard gives these no box,
/// and grades them by tone instead: ink for the one you probably want, the
/// secondary tone for the alternatives, muted for discard.
class _AnswerAction extends StatelessWidget {
  const _AnswerAction({
    required this.label,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final _ActionTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    final color = switch (tone) {
      _ActionTone.primary => t.ink,
      _ActionTone.secondary => t.sec,
      _ActionTone.muted => t.mut,
    };
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          cursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// The 36px composer at the end of the page.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.onSubmit,
    required this.onDismiss,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSubmit;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = marioTokens(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onDismiss,
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MarioRadius.md),
          border: Border.all(color: t.line),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: t.mut),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                cursorColor: t.ink,
                cursorWidth: 1,
                style: TextStyle(fontSize: 13, height: 1.2, color: t.ink),
                // Enter sends. The editor owns Enter everywhere else on this
                // page, so the composer has to claim it explicitly rather than
                // relying on the default newline behaviour.
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Ask Mario about this page, or type / for blocks',
                  hintStyle: TextStyle(fontSize: 13, height: 1.2, color: t.mut),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              '⏎',
              style: TextStyle(fontSize: 11, height: 1.2, color: t.mut),
            ),
          ],
        ),
      ),
    );
  }
}
