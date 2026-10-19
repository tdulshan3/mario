part of 'agent_panel.dart';

/// The Do tab in the desktop inspector.
///
/// The same three states as the Material tab — the HTML artifact preview, the
/// launcher before anything has run, and a run with its steps, its plan to
/// approve and its outcome — and the same rules: the whole plan is previewed,
/// every applied step is named, one Undo puts everything back. The launcher
/// is a grouped form: each preset a row that runs when clicked, with the
/// "Preview before writing" switch at the top of the same group so it is seen
/// before the first preset is.
class _MacAgentView extends StatelessWidget {
  const _MacAgentView({
    required this.session,
    required this.canEdit,
    required this.onRunPreset,
    required this.onRunInstruction,
    required this.onStop,
    required this.onUndo,
    required this.onApprovePlan,
    required this.onDiscardPlan,
    required this.onApplyArtifact,
    required this.onDiscardArtifact,
  });

  final AgentSession session;

  /// False with no page open.
  final bool canEdit;
  final ValueChanged<_PagePreset> onRunPreset;
  final Future<void> Function(String instruction) onRunInstruction;
  final VoidCallback onStop;
  final Future<void> Function() onUndo;
  final VoidCallback onApprovePlan;
  final VoidCallback onDiscardPlan;
  final Future<void> Function() onApplyArtifact;
  final VoidCallback onDiscardArtifact;

  @override
  Widget build(BuildContext context) {
    final run = session.run;
    final draft = session.artifactDraft;
    if (draft != null) {
      return _MacArtifactDraft(
        html: draft,
        applied: session.artifactApplied,
        undone: session.undone,
        canApply: canEdit,
        onApply: onApplyArtifact,
        onDiscard: onDiscardArtifact,
        onUndo: onUndo,
      );
    }
    if (run == null) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const _MacAgentIntro(),
          const SizedBox(height: 20),
          _MacActOnThisPage(enabled: canEdit, onRun: onRunPreset),
          DoHistoryList(onReplay: onRunInstruction),
        ],
      );
    }
    return ValueListenableBuilder<AiRunState>(
      valueListenable: run,
      builder: (context, state, _) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AiProgressView(state: state, onCancel: onStop),
          if (state.error != null) ...[
            const SizedBox(height: 10),
            MacAiErrorNote(message: state.error!),
          ],
          if (session.review != null) ...[
            const SizedBox(height: 12),
            _MacPlanPreview(
              plan: session.review!.plan,
              canApply: canEdit,
              onApply: onApprovePlan,
              onDiscard: onDiscardPlan,
            ),
          ],
          if (state.result is AgentOutcome) ...[
            const SizedBox(height: 12),
            _MacOutcome(
              outcome: state.result as AgentOutcome,
              undone: session.undone,
              undoing: session.isUndoing,
              canUndo: session.snapshot != null && canEdit,
              onUndo: onUndo,
              onFollowUp: !canEdit || state.isRunning ? null : onRunInstruction,
            ),
          ],
          // The launcher rides along under the result too: the agent session
          // is never cleared, so without it the presets would be usable once.
          if (session.review == null) ...[
            const SizedBox(height: 20),
            _MacActOnThisPage(
              enabled: canEdit && !state.isRunning,
              onRun: onRunPreset,
            ),
            DoHistoryList(
              onReplay: state.isRunning ? null : onRunInstruction,
            ),
          ],
        ],
      ),
    );
  }
}

class _MacAgentIntro extends StatelessWidget {
  const _MacAgentIntro();

  static const _examples = [
    'Add a table comparing the three methods',
    'Turn the last paragraph into bullet points',
    'Add a Python example for this algorithm',
    'Rename this page to match its heading',
    'Create a page "Krebs cycle" with a summary of this one',
    'Find my notes on enzymes and pull them into one page',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final t = MacTypography.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(CupertinoIcons.wand_stars, size: 24, color: c.labelTertiary),
          const SizedBox(height: 8),
          Text('Change the Page',
              textAlign: TextAlign.center,
              style: t.headline.copyWith(color: c.labelPrimary)),
          const SizedBox(height: 4),
          MacAiText(
            'Say what you want and it edits the page directly — tables, code, '
            'formulas, spreadsheets, lists, the title — and can add pages and '
            'sections to the notebook. Every change is listed as it happens, '
            'and one Undo puts the page back.',
            secondary: true,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          for (final e in _examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '“$e”',
                style: t.subheadline.copyWith(color: c.labelSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// The launcher: the review switch, then one row per preset.
class _MacActOnThisPage extends ConsumerWidget {
  const _MacActOnThisPage({required this.enabled, required this.onRun});

  /// False with no page open, and while a run is in flight — a preset that
  /// queued a second plan on top of the first would leave two sets of edits
  /// and one snapshot.
  final bool enabled;
  final ValueChanged<_PagePreset> onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review =
        ref.watch(agentSessionProvider.select((s) => s.reviewBeforeWriting));
    final accent = context.accent;
    return MacForm(
      children: [
        MacFormSection(
          title: 'Act on This Page',
          footer: 'Mario works through the job and lists each step as it '
              'happens; Undo All puts the page back. Turn on Preview before '
              'writing to approve each step first.',
          children: [
            MacFormRow(
              label: 'Preview before writing',
              child: MacSwitch(
                value: review,
                onChanged: ref
                    .read(agentSessionProvider.notifier)
                    .setReviewBeforeWriting,
                semanticLabel: 'Preview before writing',
              ),
            ),
            for (final preset in _presets)
              MacFormRow(
                label: preset.title,
                subtitle: preset.description,
                icon: Icon(preset.macIcon,
                    size: 15,
                    color: enabled ? accent : context.macColors.labelTertiary),
                enabled: enabled,
                onTap: enabled ? () => onRun(preset) : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// A validated plan, paused before the first write.
class _MacPlanPreview extends StatelessWidget {
  const _MacPlanPreview({
    required this.plan,
    required this.canApply,
    required this.onApply,
    required this.onDiscard,
  });

  final AgentPlan plan;
  final bool canApply;
  final VoidCallback onApply;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final html = plan.actions
        .where((a) => a.kind == AgentActionKind.htmlArtifact)
        .firstOrNull
        ?.text;
    return MacGroupBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MacAiText('Preview — nothing has changed yet',
              emphasized: true),
          if (plan.summary.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            MacAiText(plan.summary),
          ],
          const SizedBox(height: 8),
          for (final action in plan.actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      action.isDestructive
                          ? AppleIcons.exclamationmarkTriangle
                          : AppleIcons.chevronRight,
                      size: 11,
                      color: action.isDestructive
                          ? c.accentOrange
                          : c.labelTertiary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: MacAiText(action.summary, secondary: true),
                  ),
                ],
              ),
            ),
          if (html != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 360,
              child: HtmlPreviewPane(
                html: html,
                isDark: context.appleTheme.isDark,
                title: 'Generated artifact · sandboxed',
                sandboxed: true,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              MacButton(
                label: html == null ? 'Apply Changes' : 'Apply Artifact',
                icon: AppleIcons.checkmark,
                style: MacButtonStyle.tinted,
                onPressed: canApply ? onApply : null,
              ),
              MacButton(label: 'Discard', onPressed: onDiscard),
            ],
          ),
        ],
      ),
    );
  }
}

/// An HTML artifact from an answer, in its sandbox, to apply to the page.
class _MacArtifactDraft extends StatelessWidget {
  const _MacArtifactDraft({
    required this.html,
    required this.applied,
    required this.undone,
    required this.canApply,
    required this.onApply,
    required this.onDiscard,
    required this.onUndo,
  });

  final String html;
  final bool applied;
  final bool undone;
  final bool canApply;
  final Future<void> Function() onApply;
  final VoidCallback onDiscard;
  final Future<void> Function() onUndo;

  @override
  Widget build(BuildContext context) {
    final live = applied && !undone;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: HtmlPreviewPane(
              html: html,
              isDark: context.appleTheme.isDark,
              title: 'AI artifact · sandboxed preview',
              sandboxed: true,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              MacButton(
                label: live ? 'Applied' : 'Apply to Page',
                icon: live ? AppleIcons.checkmark : null,
                style: MacButtonStyle.tinted,
                onPressed: !canApply || live ? null : onApply,
              ),
              if (live)
                MacButton(
                    label: 'Undo', icon: AppleIcons.undo, onPressed: onUndo),
              MacButton(label: 'Close Preview', onPressed: onDiscard),
            ],
          ),
        ],
      ),
    );
  }
}

/// What a run did, what it could not do, what it is asking, what it
/// suggests next — and Undo All.
class _MacOutcome extends StatelessWidget {
  const _MacOutcome({
    required this.outcome,
    required this.undone,
    required this.undoing,
    required this.canUndo,
    required this.onUndo,
    required this.onFollowUp,
  });

  final AgentOutcome outcome;
  final bool undone;
  final bool undoing;
  final bool canUndo;
  final VoidCallback onUndo;

  /// Runs a suggested next instruction. Null while nothing can run.
  final Future<void> Function(String instruction)? onFollowUp;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final t = MacTypography.of(context);
    return MacGroupBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  undone ? AppleIcons.undo : AppleIcons.checkmarkCircleFill,
                  size: 14,
                  color: undone ? c.labelSecondary : c.accentGreen,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: MacAiText(
                  undone
                      ? 'Undone — the page is back as it was'
                      : outcome.summary.isEmpty
                          ? 'Done'
                          : outcome.summary,
                  emphasized: true,
                ),
              ),
            ],
          ),
          if (!undone) ...[
            const SizedBox(height: 8),
            for (final line in outcome.applied)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(AppleIcons.checkmark,
                          size: 11, color: c.accentGreen),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: MacAiText(line, secondary: true)),
                  ],
                ),
              ),
            // Rewrites and deletions get their own line: "9 changes" reads
            // very differently once you know three of them removed something.
            if (outcome.destructive > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: MacAiText(
                  '${outcome.destructive} of these changed or removed '
                  'existing content.',
                  secondary: true,
                  small: true,
                ),
              ),
            if (outcome.failed > 0 || outcome.dropped > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: MacAiText(
                  [
                    if (outcome.dropped > 0)
                      '${outcome.dropped} proposed change(s) could not be '
                          'used${outcome.dropReasons.isEmpty ? '' : ': '
                              '${outcome.dropReasons.join('; ')}'}',
                    if (outcome.failed > 0)
                      '${outcome.failed} step(s) could not be done',
                  ].join('. '),
                  secondary: true,
                  small: true,
                ),
              ),
            // The agent stopped to ask; the reply goes in the box below.
            if (outcome.question != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(AppleIcons.questionmarkCircle,
                        size: 14, color: context.accent),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MacAiText(outcome.question!, emphasized: true),
                        const SizedBox(height: 2),
                        const MacAiText('Reply in the box below to carry on.',
                            secondary: true, small: true),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            // Suggested next steps as links rather than buttons: they are
            // sentences, and a push button's label is one line that cannot
            // wrap in a 280 px inspector.
            if (outcome.followUps.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final f in outcome.followUps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Semantics(
                    button: true,
                    enabled: onFollowUp != null,
                    child: MacAiLinkRow(
                      onTap: onFollowUp == null ? null : () => onFollowUp!(f),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(AppleIcons.arrowRight,
                                size: 11,
                                color: onFollowUp == null
                                    ? c.labelTertiary
                                    : context.accent),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              f,
                              style: t.body.copyWith(
                                  color: onFollowUp == null
                                      ? c.labelTertiary
                                      : context.accent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            MacButton(
              label: undoing ? 'Undoing…' : 'Undo All',
              icon: AppleIcons.undo,
              onPressed: canUndo && !undoing ? onUndo : null,
            ),
          ],
        ],
      ),
    );
  }
}
