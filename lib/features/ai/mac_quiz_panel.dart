part of 'quiz_panel.dart';

// The Quiz tab in the desktop inspector, one widget per phase.
//
// The honesty rules carry over unchanged: a multiple-choice mark is stated
// plainly, an essay mark is labelled a draft, shows the rubric points it was
// given against, and can be changed by the student.

/// Setup as a grouped form: what the quiz covers, how hard, whether to look
/// things up, then how many questions of each kind.
class _MacQuizSetup extends StatelessWidget {
  const _MacQuizSetup({
    required this.pageTitle,
    required this.session,
    required this.notifier,
    required this.onGenerate,
  });

  final String pageTitle;
  final QuizSession session;
  final QuizSessionNotifier notifier;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final difficulty = session.difficulty;
    // Its own choice, not a consequence of the difficulty — "easy questions
    // on the current syllabus" and "hard questions strictly from my notes"
    // both have to be possible.
    final webDetail = switch (session.useWeb) {
      true => 'Searches even for easy questions.',
      false => 'Questions come only from the notes.',
      null => difficulty.usesWeb
          ? '${difficulty.label} looks things up.'
          : '${difficulty.label} does not.',
    };

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        MacForm(
          children: [
            MacFormSection(
              title: 'Quiz',
              children: [
                MacFormRow(
                  label: 'Covers',
                  subtitle: session.scope == QuizScope.section
                      ? 'Reads every page. Saved summaries make repeat runs '
                          'faster.'
                      : pageTitle,
                  child: MacFormPopUp<QuizScope>(
                    options: const [QuizScope.page, QuizScope.section],
                    value: session.scope,
                    labelOf: (s) =>
                        s == QuizScope.section ? 'Whole section' : 'This page',
                    onChanged: notifier.setScope,
                    semanticLabel: 'Covers',
                  ),
                ),
                MacFormRow(
                  label: 'Difficulty',
                  subtitle: difficulty.blurb,
                  child: MacFormPopUp<QuizDifficulty>(
                    options: QuizDifficulty.values,
                    value: difficulty,
                    labelOf: (d) => d.label,
                    onChanged: notifier.setDifficulty,
                    semanticLabel: 'Difficulty',
                  ),
                ),
                MacFormRow(
                  label: 'Look things up',
                  subtitle: webDetail,
                  child: MacFormPopUp<bool?>(
                    options: const [null, true, false],
                    value: session.useWeb,
                    labelOf: (v) => switch (v) {
                      true => 'Always',
                      false => 'Never',
                      null => 'Auto',
                    },
                    onChanged: notifier.setWeb,
                    semanticLabel: 'Look things up',
                  ),
                ),
              ],
            ),
            MacFormSection(
              title: 'Questions',
              footer: 'Questions are generated in batches and checked as '
                  'they arrive, so a long paper takes a while and may come '
                  'back a little short if the notes run out of distinct '
                  'things to ask.',
              children: [
                _macCounterRow(
                  label: 'Multiple choice',
                  value: session.mcqCount,
                  max: 50,
                  presets: const [10, 20, 30, 50],
                  onChanged: notifier.setMcqCount,
                ),
                _macCounterRow(
                  label: 'Essay questions',
                  value: session.essayCount,
                  max: 10,
                  presets: const [1, 2, 5],
                  onChanged: notifier.setEssayCount,
                ),
              ],
            ),
          ],
        ),
        if (session.error != null) ...[
          const SizedBox(height: 10),
          MacAiErrorNote(message: session.error!),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: MacButton(
            label: 'Generate Quiz',
            icon: CupertinoIcons.sparkles,
            style: MacButtonStyle.tinted,
            onPressed: (session.mcqCount + session.essayCount) == 0
                ? null
                : onGenerate,
          ),
        ),
        // Past quizzes, so revising does not mean regenerating.
        const QuizHistoryList(),
      ],
    );
  }

  /// A count that can be nudged by one, typed, or jumped to with a preset.
  ///
  /// The stepper covers the first two; the presets stay because the useful
  /// range is wide, and a fine-grained control nobody reaches the end of is
  /// not a control. Stacked (label above) so the stepper and the presets fit
  /// side by side at the inspector's narrowest.
  MacFormRow _macCounterRow({
    required String label,
    required int value,
    required int max,
    required List<int> presets,
    required ValueChanged<int> onChanged,
  }) =>
      MacFormRow(
        label: label,
        stacked: true,
        child: Row(
          children: [
            MacStepper(
              value: value.toDouble(),
              min: 0,
              max: max.toDouble(),
              onChanged: (v) => onChanged(v.round().clamp(0, max)),
              semanticLabel: label,
            ),
            const Spacer(),
            MacSegmentedControl<int>(
              segments: [
                for (final p in presets) MacSegment(value: p, label: '$p'),
              ],
              value: presets.contains(value) ? value : null,
              onChanged: (p) => onChanged(p.clamp(0, max)),
              semanticLabel: '$label presets',
            ),
          ],
        ),
      );
}

/// The paper: every question, then Discard or Submit for Marking.
class _MacQuizAnswering extends StatelessWidget {
  const _MacQuizAnswering({
    required this.session,
    required this.essayController,
    required this.onAnswer,
    required this.onDiscard,
    required this.onSubmit,
  });

  final QuizSession session;
  final TextEditingController Function(String itemId) essayController;
  final void Function(String itemId, String answer) onAnswer;
  final VoidCallback onDiscard;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = MacTypography.of(context);
    final c = context.macColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(session.title,
                  style: t
                      .emphasized(MacTextSpecs.title3)
                      .copyWith(color: c.labelPrimary)),
              MacAiText('${session.items.length} question(s)',
                  secondary: true, small: true),
              const SizedBox(height: 12),
              for (var i = 0; i < session.items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MacQuestionCard(
                    index: i + 1,
                    item: session.items[i],
                    selectedOption: int.tryParse(
                        session.answers[session.items[i].id] ?? ''),
                    essayController: session.items[i].kind == QuizItemKind.essay
                        ? essayController(session.items[i].id)
                        : null,
                    onOption: (v) => onAnswer(session.items[i].id, '$v'),
                    onEssayChanged: (v) => onAnswer(session.items[i].id, v),
                  ),
                ),
            ],
          ),
        ),
        const MacAiSeparator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              MacButton(label: 'Discard', onPressed: onDiscard),
              const Spacer(),
              MacButton(
                label: 'Submit for Marking',
                icon: AppleIcons.checkmark,
                style: MacButtonStyle.tinted,
                onPressed: onSubmit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MacQuestionCard extends StatelessWidget {
  const _MacQuestionCard({
    required this.index,
    required this.item,
    required this.selectedOption,
    required this.essayController,
    required this.onOption,
    required this.onEssayChanged,
  });

  final int index;
  final QuizItem item;
  final int? selectedOption;
  final TextEditingController? essayController;
  final ValueChanged<int> onOption;
  final ValueChanged<String> onEssayChanged;

  @override
  Widget build(BuildContext context) {
    final t = MacTypography.of(context);
    final c = context.macColors;
    return MacGroupBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$index.',
                  style: t.bodyEmphasized.copyWith(color: c.labelSecondary)),
              const SizedBox(width: 6),
              Expanded(
                // The model writes Markdown, and "What does `foo()` return?"
                // must not arrive with its backticks showing.
                child: AiInlineMarkdown(
                  item.question,
                  style: t.body.copyWith(color: c.labelPrimary),
                ),
              ),
              if (item.marks > 1) ...[
                const SizedBox(width: 6),
                MacAiText('${item.marks} marks', secondary: true, small: true),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (item.kind == QuizItemKind.mcq)
            for (var i = 0; i < item.options.length; i++)
              _MacChoice(
                text: item.options[i],
                selected: selectedOption == i,
                onTap: () => onOption(i),
              )
          else
            _MacEssayField(
              controller: essayController!,
              onChanged: onEssayChanged,
              question: item.question,
            ),
        ],
      ),
    );
  }
}

/// One multiple-choice option: a radio button and the option's text, which
/// wraps and keeps its inline Markdown.
///
/// The radio is a one-option `MacRadioGroup` with an empty label and the text
/// beside it is ours. apple_ui's radio label is a single line that never
/// wraps, and an option is often a sentence — at the inspector's width a
/// labelled radio would run off the panel. Clicking the text picks the option
/// too, as clicking a radio's label does.
class _MacChoice extends StatelessWidget {
  const _MacChoice({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = MacTypography.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MacRadioGroup<int>(
              options: const [0],
              value: selected ? 0 : null,
              labelOf: (_) => '',
              onChanged: (_) => onTap(),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: AiInlineMarkdown(
                  text,
                  style: t.body.copyWith(color: context.macColors.labelPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Room to write an essay: eight lines that grow with the text, and a sheet
/// the size of the window for a long answer — the same controller, so
/// nothing is copied or lost between the two.
class _MacEssayField extends StatelessWidget {
  const _MacEssayField({
    required this.controller,
    required this.onChanged,
    required this.question,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String question;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MacTextArea(
          controller: controller,
          onChanged: onChanged,
          rows: 8,
          maxRows: 40,
          placeholder: 'Write your answer…',
          semanticLabel: 'Answer',
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: MacButton(
            label: 'Write in a Larger Editor…',
            style: MacButtonStyle.borderless,
            onPressed: () => _openLarge(context),
          ),
        ),
      ],
    );
  }

  Future<void> _openLarge(BuildContext context) => showMacSheet<void>(
        context: context,
        builder: (context) {
          final size = MediaQuery.sizeOf(context);
          final t = MacTypography.of(context);
          // As many lines as the window leaves room for under the question
          // and above the button row.
          final rows = ((size.height * 0.85 - 160) / 16).floor().clamp(8, 400);
          return MacSheet(
            title: 'Your Answer',
            width: size.width * 0.8,
            onCancel: () => Navigator.of(context).pop(),
            actions: [
              MacButton(
                label: 'Done',
                style: MacButtonStyle.prominent,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AiInlineMarkdown(
                  question,
                  style: t.bodyEmphasized
                      .copyWith(color: context.macColors.labelPrimary),
                ),
                const SizedBox(height: 12),
                MacTextArea(
                  controller: controller,
                  onChanged: onChanged,
                  rows: rows,
                  autofocus: true,
                  placeholder: 'Write your answer…',
                  semanticLabel: 'Answer',
                ),
              ],
            ),
          );
        },
      );
}

/// Marking in progress: how far it has got, and a way to stop and see what
/// is marked so far.
class _MacQuizMarking extends StatelessWidget {
  const _MacQuizMarking({
    required this.done,
    required this.total,
    required this.onStop,
  });

  final int done;
  final int total;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MacSpinner(large: true, semanticLabel: 'Marking'),
            const SizedBox(height: 10),
            MacAiText('Marking $done of $total'),
            const SizedBox(height: 8),
            MacProgressBar(
              value: total == 0 ? 0 : done / total,
              width: 200,
              semanticLabel: 'Marking',
            ),
            const SizedBox(height: 12),
            MacButton(
              label: 'Stop and Show What Is Marked',
              icon: AppleIcons.stop,
              onPressed: onStop,
            ),
          ],
        ),
      ),
    );
  }
}

/// The marked paper: the score, each question with its mark, and New Quiz.
class _MacQuizResults extends StatelessWidget {
  const _MacQuizResults({
    required this.session,
    required this.onOverride,
    required this.onRestart,
  });

  final QuizSession session;
  final void Function(String itemId, double value) onOverride;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _MacScoreBanner(
                awarded: session.awarded,
                outOf: session.outOf,
                anyProvisional: session.anyProvisional,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < session.items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MacResultCard(
                    index: i + 1,
                    item: session.items[i],
                    grade: session.grades[session.items[i].id],
                    answer: session.answers[session.items[i].id] ?? '',
                    onOverride: (v) => onOverride(session.items[i].id, v),
                  ),
                ),
            ],
          ),
        ),
        const MacAiSeparator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Icon(AppleIcons.icloud, size: 14, color: c.labelSecondary),
              const SizedBox(width: 5),
              const Expanded(
                child:
                    MacAiText('Saved to Drive', secondary: true, small: true),
              ),
              MacButton(
                label: 'New Quiz',
                icon: AppleIcons.arrowClockwise,
                style: MacButtonStyle.tinted,
                onPressed: onRestart,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MacScoreBanner extends StatelessWidget {
  const _MacScoreBanner({
    required this.awarded,
    required this.outOf,
    required this.anyProvisional,
  });

  final double awarded;
  final int outOf;
  final bool anyProvisional;

  @override
  Widget build(BuildContext context) {
    final t = MacTypography.of(context);
    final c = context.macColors;
    final pct = outOf == 0 ? 0.0 : awarded / outOf;
    return MacGroupBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_trim(awarded),
                  style: t
                      .emphasized(MacTextSpecs.largeTitle)
                      .copyWith(color: c.labelPrimary)),
              Text(' / $outOf',
                  style: t.title3.copyWith(color: c.labelSecondary)),
              const Spacer(),
              Text('${(pct * 100).round()}%',
                  style: t
                      .emphasized(MacTextSpecs.title3)
                      .copyWith(color: c.labelSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          MacProgressBar(
              value: pct.clamp(0, 1).toDouble(), semanticLabel: 'Score'),
          if (anyProvisional) ...[
            const SizedBox(height: 10),
            const MacAiText(
              'Essay marks are a draft from the model, not a result. Check '
              'the rubric points below and change any mark you disagree with.',
              secondary: true,
              small: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _MacResultCard extends StatelessWidget {
  const _MacResultCard({
    required this.index,
    required this.item,
    required this.grade,
    required this.answer,
    required this.onOverride,
  });

  final int index;
  final QuizItem item;
  final QuizGrade? grade;
  final String answer;
  final ValueChanged<double> onOverride;

  @override
  Widget build(BuildContext context) {
    final t = MacTypography.of(context);
    final c = context.macColors;
    final g = grade;
    // The mark's colour says how it went: green full marks, red none,
    // orange in between.
    final Color markColour = g == null
        ? c.labelPrimary
        : g.effective >= g.outOf
            ? c.accentGreen
            : g.effective <= 0
                ? c.accentRed
                : c.accentOrange;

    return MacGroupBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$index.',
                  style: t.bodyEmphasized.copyWith(color: c.labelSecondary)),
              const SizedBox(width: 6),
              Expanded(
                child: AiInlineMarkdown(item.question,
                    style: t.body.copyWith(color: c.labelPrimary)),
              ),
              if (g != null) ...[
                const SizedBox(width: 6),
                Text('${_trim(g.effective)}/${g.outOf}',
                    style: t.bodyEmphasized.copyWith(color: markColour)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (item.kind == QuizItemKind.mcq)
            _MacMcqReview(item: item, chosen: int.tryParse(answer))
          else
            _MacEssayReview(answer: answer),
          if (g != null && g.feedback.isNotEmpty) ...[
            const SizedBox(height: 8),
            AiInlineMarkdown(g.feedback,
                style: t.body.copyWith(color: c.labelSecondary)),
          ],
          if (g != null &&
              (g.matchedPoints.isNotEmpty || g.missedPoints.isNotEmpty)) ...[
            const SizedBox(height: 8),
            for (final p in g.matchedPoints)
              _MacRubricLine(text: p, matched: true),
            for (final p in g.missedPoints)
              _MacRubricLine(text: p, matched: false),
          ],
          if (g != null && g.isProvisional) ...[
            const SizedBox(height: 8),
            // A pop-up rather than a row of numbers: an essay can carry up to
            // eleven marks, and the highest are the ones a student wants.
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const MacAiText('Draft mark — change it:',
                    secondary: true, small: true),
                MacPopUpButton<double>(
                  options: [for (var m = 0; m <= g.outOf; m++) m.toDouble()],
                  value: g.effective,
                  labelOf: _trim,
                  onChanged: onOverride,
                  semanticLabel: 'Draft mark',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MacMcqReview extends StatelessWidget {
  const _MacMcqReview({required this.item, required this.chosen});
  final QuizItem item;
  final int? chosen;

  @override
  Widget build(BuildContext context) {
    final t = MacTypography.of(context);
    final c = context.macColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < item.options.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    i == item.correctIndex
                        ? AppleIcons.checkmarkCircleFill
                        : i == chosen
                            ? AppleIcons.xmarkCircleFill
                            : AppleIcons.circle,
                    size: 13,
                    color: i == item.correctIndex
                        ? c.accentGreen
                        : i == chosen
                            ? c.accentRed
                            : c.labelQuaternary,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: AiInlineMarkdown(
                    item.options[i],
                    style: (i == item.correctIndex ? t.bodyEmphasized : t.body)
                        .copyWith(
                      color: i == item.correctIndex || i == chosen
                          ? c.labelPrimary
                          : c.labelSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MacEssayReview extends StatelessWidget {
  const _MacEssayReview({required this.answer});
  final String answer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.macColors.fillQuaternary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: MacAiText(
          answer.trim().isEmpty ? '(no answer)' : answer.trim(),
          secondary: true,
        ),
      ),
    );
  }
}

class _MacRubricLine extends StatelessWidget {
  const _MacRubricLine({required this.text, required this.matched});
  final String text;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(matched ? AppleIcons.checkmark : AppleIcons.minus,
                size: 11, color: matched ? c.accentGreen : c.labelTertiary),
          ),
          const SizedBox(width: 6),
          Expanded(child: MacAiText(text, secondary: !matched)),
        ],
      ),
    );
  }
}
