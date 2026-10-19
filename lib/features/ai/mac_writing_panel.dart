part of 'writing_panel.dart';

/// The Writing tab in the desktop inspector.
///
/// A list, not squiggles, as in the Material tab: a check runs when asked,
/// each suggestion shows the change as before → after, and each is accepted
/// or ignored on its own. The check button sits in a footer under a
/// separator, where the Material tab has its divider.
class _MacWritingView extends StatelessWidget {
  const _MacWritingView({
    required this.hasPage,
    required this.session,
    required this.onCheck,
    required this.onStop,
    required this.onAccept,
    required this.onIgnore,
  });

  final bool hasPage;
  final WritingSession session;
  final VoidCallback onCheck;
  final VoidCallback onStop;
  final Future<void> Function(int index, GrammarSuggestion suggestion) onAccept;
  final ValueChanged<int> onIgnore;

  @override
  Widget build(BuildContext context) {
    if (!hasPage) {
      return const MacEmptyState(
        title: 'No Page Open',
        message: 'Open a page to check its writing.',
      );
    }
    final run = session.run;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: run == null
              ? const MacEmptyState(
                  title: 'Check Spelling and Grammar',
                  message: 'Runs when you ask, not while you type. Technical '
                      'terms, code and formulas are left alone.',
                )
              : ValueListenableBuilder<AiRunState>(
                  valueListenable: run,
                  builder: (context, state, _) => ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (state.isRunning || state.error != null)
                        AiProgressView(state: state, onCancel: onStop),
                      if (state.error != null) ...[
                        const SizedBox(height: 10),
                        MacAiErrorNote(message: state.error!),
                      ],
                      // Only a completed check can say there is nothing to
                      // fix; a cancelled or failed one has not read the page.
                      if (state.status == AiRunStatus.done &&
                          session.suggestions.isEmpty)
                        _MacAllClear(backend: state.backendLabel),
                      for (var i = 0; i < session.suggestions.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MacSuggestionCard(
                            suggestion: session.suggestions[i],
                            outcome: session.outcomes[i],
                            onAccept: () => onAccept(i, session.suggestions[i]),
                            onIgnore: () => onIgnore(i),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        const MacAiSeparator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: run != null && session.suggestions.isNotEmpty
                    ? MacAiText('${session.pending} left',
                        secondary: true, small: true)
                    : const SizedBox.shrink(),
              ),
              MacButton(
                label: run == null ? 'Check This Page' : 'Check Again',
                icon: CupertinoIcons.textformat_abc,
                style: MacButtonStyle.tinted,
                onPressed: onCheck,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MacSuggestionCard extends StatelessWidget {
  const _MacSuggestionCard({
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
    final c = context.macColors;
    final t = MacTypography.of(context);
    final done = outcome != null;
    return Opacity(
      opacity: done ? 0.55 : 1,
      child: MacGroupBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: MacAiGroupTitle(suggestion.kind.label)),
                if (outcome != null)
                  MacAiText(
                    switch (outcome!) {
                      SuggestionOutcome.applied => 'Applied',
                      SuggestionOutcome.ignored => 'Ignored',
                      SuggestionOutcome.expired => 'Text has changed',
                    },
                    small: true,
                    secondary: outcome != SuggestionOutcome.expired,
                    color: outcome == SuggestionOutcome.expired
                        ? c.accentRed
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // The literal page text, before and after — unstyled, because
            // styling it would misrepresent what is about to be written.
            Text(
              suggestion.before,
              style: t.body.copyWith(
                color: c.labelSecondary,
                decoration: TextDecoration.lineThrough,
                decorationColor: c.accentRed,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(CupertinoIcons.arrow_turn_down_right,
                      size: 11, color: c.accentGreen),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(suggestion.after,
                      style: t.bodyEmphasized.copyWith(color: c.labelPrimary)),
                ),
              ],
            ),
            if (suggestion.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              // The proofreader writes this line, in Markdown like
              // everything else it writes.
              AiInlineMarkdown(suggestion.reason,
                  style: t.subheadline.copyWith(color: c.labelSecondary)),
            ],
            if (!done) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  MacButton(
                    label: 'Accept',
                    style: MacButtonStyle.tinted,
                    onPressed: onAccept,
                  ),
                  const SizedBox(width: 8),
                  MacButton(label: 'Ignore', onPressed: onIgnore),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MacAllClear extends StatelessWidget {
  const _MacAllClear({required this.backend});
  final String? backend;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final t = MacTypography.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(AppleIcons.checkmarkCircleFill, size: 24, color: c.accentGreen),
          const SizedBox(height: 8),
          Text('Nothing to Fix',
              style: t.headline.copyWith(color: c.labelPrimary)),
          if (backend != null) ...[
            const SizedBox(height: 2),
            MacAiText('Checked by $backend', secondary: true, small: true),
          ],
        ],
      ),
    );
  }
}
