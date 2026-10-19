/// The Writing tab — spelling and grammar suggestions for the open page.
///
/// A list, not inline squiggles. Squiggles would mean running a model
/// continuously against a document that is being typed into, which a local
/// model cannot keep up with and which interrupts the writer mid-thought. Here
/// the user asks for a check, reads what came back, and accepts the fixes they
/// agree with — one at a time, each its own undo step.
///
/// A view over [writingSessionProvider]: the check, its results and which
/// suggestions have been dealt with all outlive this widget, so switching to
/// the quiz tab mid-check no longer throws the check away.
///
/// Every row shows the change as before -> after, because "Grammar issue on
/// line 4" is not something anyone can act on without scrolling to look.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/colors.dart';
import '../../ui/mac/mac_look.dart';
import 'ai_progress.dart';
import 'ai_progress_view.dart';
import 'ai_session_state.dart';
import 'ai_state.dart';
import 'grammar_check.dart';
import 'ai_markdown.dart';
import 'mac_ai_common.dart';

part 'mac_writing_panel.dart';

class WritingPanel extends ConsumerStatefulWidget {
  const WritingPanel({super.key});

  @override
  ConsumerState<WritingPanel> createState() => _WritingPanelState();
}

class _WritingPanelState extends ConsumerState<WritingPanel> {
  void _check() {
    final bridge = ref.read(aiEditorBridgeProvider);
    if (bridge == null) return;

    final run = ref.read(grammarCheckerProvider).check(bridge.readPage());
    final notifier = ref.read(writingSessionProvider.notifier)..startCheck(run);

    // The notifier is captured, not read from `ref` inside the callback: the
    // run outlives this widget, and a late `ref` read would throw.
    void listener() {
      final s = run.value;
      if (s.status == AiRunStatus.running) return;
      run.removeListener(listener);
      // Only a completed check can report "nothing to fix". A cancelled or
      // failed one has no result, and treating that as an empty list told the
      // user their writing was clean when it had not been read.
      if (s.status != AiRunStatus.done) return;
      notifier.checked(s.result is List<GrammarSuggestion>
          ? s.result as List<GrammarSuggestion>
          : const []);
    }

    run.addListener(listener);
  }

  Future<void> _accept(int index, GrammarSuggestion s) async {
    final applier = ref.read(grammarApplierProvider);
    final notifier = ref.read(writingSessionProvider.notifier);
    final ok = await applier?.call(s) ?? false;
    notifier.resolve(
        index, ok ? SuggestionOutcome.applied : SuggestionOutcome.expired);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bridge = ref.watch(aiEditorBridgeProvider);
    final session = ref.watch(writingSessionProvider);
    final run = session.run;

    if (useMacLook) {
      final notifier = ref.read(writingSessionProvider.notifier);
      return _MacWritingView(
        hasPage: bridge != null,
        session: session,
        onCheck: _check,
        onStop: notifier.stop,
        onAccept: _accept,
        onIgnore: (i) => notifier.resolve(i, SuggestionOutcome.ignored),
      );
    }

    if (bridge == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Open a page to check its writing.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: run == null
              ? _Intro(onCheck: _check)
              : ValueListenableBuilder<AiRunState>(
                  valueListenable: run,
                  builder: (context, state, _) => ListView(
                    padding: EdgeInsets.fromLTRB(
                        12, 12, 12, ComposerReserve.of(context)),
                    children: [
                      if (state.isRunning || state.error != null)
                        AiProgressView(
                          state: state,
                          onCancel:
                              ref.read(writingSessionProvider.notifier).stop,
                        ),
                      if (state.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(state.error!,
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: scheme.error)),
                        ),
                      if (state.status == AiRunStatus.done &&
                          session.suggestions.isEmpty)
                        _AllClear(backend: state.backendLabel),
                      for (var i = 0; i < session.suggestions.length; i++)
                        _SuggestionCard(
                          suggestion: session.suggestions[i],
                          outcome: session.outcomes[i],
                          onAccept: () => _accept(i, session.suggestions[i]),
                          onIgnore: () => ref
                              .read(writingSessionProvider.notifier)
                              .resolve(i, SuggestionOutcome.ignored),
                        ),
                    ],
                  ),
                ),
        ),
        const Divider(height: 1),
        Padding(
          // Same reserve as the other tabs: the composer floats over this
          // content, so a docked footer has to clear it explicitly.
          padding: EdgeInsets.fromLTRB(10, 10, 10, ComposerReserve.of(context)),
          child: Row(
            children: [
              if (run != null && session.suggestions.isNotEmpty)
                Expanded(
                  child: Text('${session.pending} left',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                )
              else
                const Spacer(),
              FilledButton.icon(
                onPressed: _check,
                icon: const Icon(Icons.spellcheck, size: 16),
                label: Text(run == null ? 'Check this page' : 'Check again'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.outcome,
    required this.onAccept,
    required this.onIgnore,
  });

  final GrammarSuggestion suggestion;
  final SuggestionOutcome? outcome;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = outcome != null;

    return Opacity(
      opacity: done ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(suggestion.kind.label,
                      style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: scheme.onSurfaceVariant)),
                ),
                const Spacer(),
                if (outcome != null)
                  Text(
                    switch (outcome!) {
                      SuggestionOutcome.applied => 'Applied',
                      SuggestionOutcome.ignored => 'Ignored',
                      SuggestionOutcome.expired => 'Text has changed',
                    },
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: outcome == SuggestionOutcome.expired
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _Diff(before: suggestion.before, after: suggestion.after),
            if (suggestion.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              // The proofreader writes this line, in Markdown like everything
              // else it writes. The diff above stays raw on purpose — that is
              // the literal page text, and styling it would misrepresent what
              // is about to be written.
              AiInlineMarkdown(suggestion.reason,
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      height: 1.35,
                      color: scheme.onSurfaceVariant)),
            ],
            if (!done) ...[
              const SizedBox(height: 9),
              Row(
                children: [
                  FilledButton(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: GoogleFonts.inter(
                          fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Accept'),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: onIgnore,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: GoogleFonts.inter(fontSize: 11.5),
                    ),
                    child: const Text('Ignore'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Diff extends StatelessWidget {
  const _Diff({required this.before, required this.after});
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          before,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            height: 1.4,
            color: scheme.onSurfaceVariant,
            decoration: TextDecoration.lineThrough,
            decorationColor: scheme.error.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.subdirectory_arrow_right,
                size: 13, color: MarioColors.labelGreen),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                after,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear({required this.backend});
  final String? backend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline,
              size: 26, color: MarioColors.labelGreen),
          const SizedBox(height: 8),
          Text('Nothing to fix',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface)),
          if (backend != null) ...[
            const SizedBox(height: 3),
            Text('Checked by $backend',
                style: GoogleFonts.inter(
                    fontSize: 10.5, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onCheck});
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.spellcheck, size: 26, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text('Check spelling and grammar',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            const SizedBox(height: 5),
            Text(
              'Runs when you ask, not while you type. Technical terms, code and '
              'formulas are left alone.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 11, height: 1.4, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
