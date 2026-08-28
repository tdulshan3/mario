/// The Quiz tab — generate questions from a page or a whole section, answer
/// them, and get them marked.
///
/// A view over [quizSessionProvider]. A generated quiz, the answers typed into
/// it and its marks all live above this widget, so switching to the Ask tab
/// mid-quiz no longer discards the lot — and a quiz interrupted halfway can be
/// come back to.
///
/// The honesty rules are visible in the UI, not just the code. A multiple
/// choice mark is stated plainly because it was computed by comparing two
/// numbers. An essay mark is labelled a draft, shows the rubric points it was
/// awarded against, and can be overridden by the student — because a small
/// model's opinion of an essay is an opinion, and presenting it as a grade
/// would be a lie the student might believe.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/note_page.dart';
import '../../core/services/ai/ai_artifact_store.dart';
import '../../core/services/ai/ai_artifacts.dart';
import '../../core/services/ai/llm_types.dart';
import '../../ui/colors.dart';
import '../shell/shell_state.dart';
import 'ai_history.dart';
import 'ai_progress.dart';
import 'ai_progress_view.dart';
import 'ai_session_state.dart';
import 'ai_state.dart';
import 'ai_tasks.dart';
import 'note_context.dart';

class QuizPanel extends ConsumerStatefulWidget {
  const QuizPanel({super.key});

  @override
  ConsumerState<QuizPanel> createState() => _QuizPanelState();
}

class _QuizPanelState extends ConsumerState<QuizPanel> {
  /// Controllers are view-local; their text is mirrored into the session on
  /// every change so an in-progress essay survives a tab switch.
  final _essayControllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _essayControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Returns the controller for an essay item, seeded from saved state.
  ///
  /// No listener: the answer is written back from the TextField's `onChanged`,
  /// which fires only on user input. A controller listener would also fire when
  /// the controller is seeded during build, writing to a provider mid-build.
  TextEditingController _essayController(String itemId) {
    final existing = _essayControllers[itemId];
    if (existing != null) return existing;
    final saved = ref.read(quizSessionProvider).answers[itemId] ?? '';
    return _essayControllers[itemId] = TextEditingController(text: saved);
  }

  // ------------------------------------------------------------- generation

  Future<void> _generate() async {
    final bridge = ref.read(aiEditorBridgeProvider);
    if (bridge == null) return;

    // Everything needed from `ref` is captured before the first await.
    // Reading a whole section is many seconds of Drive I/O, and the user can
    // close the panel or switch tabs in the middle of it — after which `ref`
    // throws "Cannot use ref after the widget was disposed".
    final reader = ref.read(sectionReaderProvider);
    final tasks = ref.read(aiTasksProvider);
    final store = ref.read(aiArtifactStoreProvider);
    final scope = ref.read(quizSessionProvider).scope;
    final pages = scope == QuizScope.section
        ? (ref.read(pagesStreamProvider((
              notebookId: bridge.notebookId,
              sectionId: bridge.sectionId,
            ))).valueOrNull ??
            const <NotePage>[])
        : const <NotePage>[];

    final session = ref.read(quizSessionProvider.notifier);

    try {
      final NoteText note;
      final String scopeLabel;

      if (scope == QuizScope.section) {
        if (pages.isEmpty) {
          throw StateError('This section has no pages yet.');
        }
        final read = await reader.read(
              notebookId: bridge.notebookId,
              pages: pages,
            );
        if (!mounted) return;
        note = read.merge(title: 'Section');
        scopeLabel = read.failed.isEmpty
            ? '${read.pages.length} page(s)'
                '${read.cachedCount > 0 ? ', ${read.cachedCount} from saved summaries' : ''}'
            : '${read.pages.length} page(s), ${read.failed.length} could not be read';
      } else {
        note = bridge.readPage();
        scopeLabel = bridge.pageTitle;
      }

      final current = ref.read(quizSessionProvider);
      final run = tasks.generateQuiz(
            note: note,
            scopeLabel: scopeLabel,
            mcqCount: current.mcqCount,
            essayCount: current.essayCount,
          );
      session.startGenerating(run);

      // `session` is captured, not read from `ref` in the callback — the run
      // outlives this widget.
      void listener() {
        final s = run.value;
        if (s.status == AiRunStatus.running) return;
        run.removeListener(listener);
        if (s.status == AiRunStatus.done && s.result is List<QuizItem>) {
          final items = s.result as List<QuizItem>;
          final title = s.answer.trim().isEmpty ? 'Quiz' : s.answer.trim();
          session.generated(items, title);
          _persistQuiz(store, session, bridge, items, note, title,
              scope: scope,
              pageIds: scope == QuizScope.section
                  ? [for (final p in pages) p.id]
                  : [bridge.pageId],
              backend: s.backendLabel);
        } else {
          session.generationFailed(s.error);
        }
      }

      run.addListener(listener);
    } catch (e) {
      session.generationFailed(e.toString());
    }
  }

  void _persistQuiz(
    AiArtifactStore store,
    QuizSessionNotifier session,
    AiEditorBridge bridge,
    List<QuizItem> items,
    NoteText note,
    String title, {
    required QuizScope scope,
    required List<String> pageIds,
    String? backend,
  }) {
    final quiz = Quiz(
      id: 'quiz-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      scope: scope,
      scopeId: scope == QuizScope.section ? bridge.sectionId : bridge.pageId,
      items: items,
      sourceHash: sourceHashOf(note.render()),
      // Every page the quiz draws on, not just the one that was open. A
      // section quiz recording a single page id was deleted in full — marks
      // and all — the moment that one page was deleted.
      pageIds: pageIds,
      provenance: AiProvenance(
        backend: backend ?? 'unknown',
        model: '',
        createdAt: DateTime.now(),
      ),
    );
    session.setQuiz(quiz, notebookId: bridge.notebookId);
    store.addQuiz(bridge.notebookId, quiz).ignore();
  }

  // ---------------------------------------------------------------- marking

  Future<void> _submit() async {
    final session = ref.read(quizSessionProvider.notifier);
    final store = ref.read(aiArtifactStoreProvider);
    final bridge = ref.read(aiEditorBridgeProvider);
    final tasks = ref.read(aiTasksProvider);
    // Everything is read from `ref` before the first await. Marking an essay is
    // a live model call, and the user can close the panel mid-paper — after
    // which `ref` throws "Cannot use ref after the widget was disposed" and the
    // Quiz tab is stuck on the marking screen for the rest of the session.
    final current = ref.read(quizSessionProvider);
    final items = current.items;
    final answers = current.answers;
    final notebookId = current.notebookId ?? bridge?.notebookId;

    final cancel = CancelToken();
    session.startMarking(
        'attempt-${DateTime.now().microsecondsSinceEpoch}', cancel);

    for (final item in items) {
      if (cancel.isCancelled) break;
      try {
        session.graded(
          item.id,
          await tasks.grade(
              item: item, answer: answers[item.id] ?? '', cancel: cancel),
        );
      } on LlmCancelled {
        break;
      } catch (e) {
        // One unmarkable question must not abandon the rest of the paper.
        session.graded(
          item.id,
          QuizGrade(
            itemId: item.id,
            awarded: 0,
            outOf: item.marks,
            feedback: 'Could not mark this one: $e',
          ),
        );
      }
    }
    session.markingFinished();
    if (notebookId != null) _persistAttempt(store, notebookId);
  }

  /// [notebookId] is the notebook the *quiz* belongs to, not whichever page is
  /// open now. The session is app-level, so a quiz generated in one notebook
  /// can be submitted while another is on screen — filing the marks under the
  /// wrong notebook loses them.
  void _persistAttempt(AiArtifactStore store, String notebookId) {
    final s = ref.read(quizSessionProvider);
    store
        .putAttempt(
          notebookId,
          QuizAttempt(
            id: s.attemptId ??
                'attempt-${DateTime.now().microsecondsSinceEpoch}',
            quizId: s.quiz?.id ?? s.title,
            answers: s.answers,
            grades: s.grades,
            startedAt: DateTime.now(),
            submittedAt: DateTime.now(),
          ),
        )
        .ignore();
  }

  void _overrideMark(String itemId, double value) {
    ref.read(quizSessionProvider.notifier).overrideMark(itemId, value);
    final notebookId = ref.read(quizSessionProvider).notebookId ??
        ref.read(aiEditorBridgeProvider)?.notebookId;
    if (notebookId != null) {
      _persistAttempt(ref.read(aiArtifactStoreProvider), notebookId);
    }
    // The history list shows the latest score, so it needs re-reading.
    ref.invalidate(aiHistoryProvider);
  }

  void _restart() {
    for (final c in _essayControllers.values) {
      c.dispose();
    }
    _essayControllers.clear();
    ref.read(quizSessionProvider.notifier).reset();
    ref.invalidate(aiHistoryProvider);
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(aiEditorBridgeProvider);
    if (bridge == null) return const _NoPage();
    final session = ref.watch(quizSessionProvider);

    return switch (session.phase) {
      QuizPhase.setup => _buildSetup(bridge, session),
      QuizPhase.generating => _buildGenerating(session),
      QuizPhase.answering => _buildAnswering(session),
      QuizPhase.marking => _buildMarking(session),
      QuizPhase.results => _buildResults(session),
    };
  }

  Widget _buildSetup(AiEditorBridge bridge, QuizSession session) {
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(quizSessionProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text('What should the quiz cover?',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
        const SizedBox(height: 10),
        _ScopeOption(
          label: 'This page',
          detail: bridge.pageTitle,
          selected: session.scope == QuizScope.page,
          onTap: () => notifier.setScope(QuizScope.page),
        ),
        const SizedBox(height: 6),
        _ScopeOption(
          label: 'This whole section',
          detail: 'Reads every page. Saved summaries make repeat runs faster.',
          selected: session.scope == QuizScope.section,
          onTap: () => notifier.setScope(QuizScope.section),
        ),
        const SizedBox(height: 16),
        _Counter(
          label: 'Multiple choice',
          value: session.mcqCount,
          min: 0,
          max: 50,
          presets: const [10, 20, 30, 50],
          onChanged: notifier.setMcqCount,
        ),
        const SizedBox(height: 10),
        _Counter(
          label: 'Essay questions',
          value: session.essayCount,
          min: 0,
          max: 10,
          presets: const [1, 2, 5],
          onChanged: notifier.setEssayCount,
        ),
        const SizedBox(height: 8),
        Text(
          'Questions are generated in batches and checked as they arrive, so a '
          'long paper takes a while and may come back a little short if the '
          'notes run out of distinct things to ask.',
          style: GoogleFonts.inter(
            fontSize: 10.5,
            height: 1.4,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
        if (session.error != null) ...[
          const SizedBox(height: 12),
          Text(session.error!,
              style: GoogleFonts.inter(fontSize: 12, color: scheme.error)),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: (session.mcqCount + session.essayCount) == 0
              ? null
              : () => _generate(),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Generate quiz'),
        ),
        // Past quizzes, so revising does not mean regenerating.
        const QuizHistoryList(),
      ],
    );
  }

  Widget _buildGenerating(QuizSession session) {
    final run = session.run;
    if (run == null) return const SizedBox.shrink();
    return ValueListenableBuilder<AiRunState>(
      valueListenable: run,
      builder: (context, state, _) => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          AiProgressView(
            state: state,
            onCancel: ref.read(quizSessionProvider.notifier).stop,
          ),
          if (state.status == AiRunStatus.cancelled) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: _restart, child: const Text('Back')),
          ],
        ],
      ),
    );
  }

  Widget _buildAnswering(QuizSession session) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Text(session.title,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface)),
              const SizedBox(height: 4),
              Text(
                '${session.items.length} question(s)',
                style: GoogleFonts.inter(
                    fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < session.items.length; i++)
                _QuestionCard(
                  index: i + 1,
                  item: session.items[i],
                  selectedOption:
                      int.tryParse(session.answers[session.items[i].id] ?? ''),
                  essayController:
                      session.items[i].kind == QuizItemKind.essay
                          ? _essayController(session.items[i].id)
                          : null,
                  onOption: (v) => ref
                      .read(quizSessionProvider.notifier)
                      .answer(session.items[i].id, '$v'),
                  onEssayChanged: (v) => ref
                      .read(quizSessionProvider.notifier)
                      .answer(session.items[i].id, v),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              TextButton(onPressed: _restart, child: const Text('Discard')),
              const Spacer(),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Submit for marking'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMarking(QuizSession session) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(height: 12),
          Text('Marking ${session.markingDone} of ${session.items.length}',
              style: GoogleFonts.inter(
                  fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: ref.read(quizSessionProvider.notifier).stopMarking,
            icon: const Icon(Icons.stop_circle_outlined, size: 15),
            label: const Text('Stop and show what is marked'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: scheme.onSurfaceVariant,
              textStyle: GoogleFonts.inter(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(QuizSession session) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _ScoreBanner(
                awarded: session.awarded,
                outOf: session.outOf,
                anyProvisional: session.anyProvisional,
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < session.items.length; i++)
                _ResultCard(
                  index: i + 1,
                  item: session.items[i],
                  grade: session.grades[session.items[i].id],
                  answer: session.answers[session.items[i].id] ?? '',
                  onOverride: (v) =>
                      _overrideMark(session.items[i].id, v),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.cloud_done_outlined,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Expanded(
                child: Text('Saved to Drive',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ),
              FilledButton.icon(
                onPressed: _restart,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('New quiz'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScoreBanner extends StatelessWidget {
  const _ScoreBanner({
    required this.awarded,
    required this.outOf,
    required this.anyProvisional,
  });

  final double awarded;
  final int outOf;
  final bool anyProvisional;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = outOf == 0 ? 0.0 : awarded / outOf;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _trim(awarded),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                ' / $outOf',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text('${(pct * 100).round()}%',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: scheme.surfaceContainerHighest,
              color: MarioColors.primary,
            ),
          ),
          if (anyProvisional) ...[
            const SizedBox(height: 10),
            Text(
              'Essay marks are a draft from the model, not a result. Check the '
              'rubric points below and change any mark you disagree with.',
              style: GoogleFonts.inter(
                fontSize: 11,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$index.',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.question,
                  style: GoogleFonts.inter(
                      fontSize: 13, height: 1.4, color: scheme.onSurface),
                ),
              ),
              if (item.marks > 1)
                Text('${item.marks} marks',
                    style: GoogleFonts.inter(
                        fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          if (item.kind == QuizItemKind.mcq)
            for (var i = 0; i < item.options.length; i++)
              InkWell(
                onTap: () => onOption(i),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        selectedOption == i
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: selectedOption == i
                            ? MarioColors.primaryPressed
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.options[i],
                          style: GoogleFonts.inter(
                              fontSize: 12.5,
                              height: 1.35,
                              color: scheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              )
          else
            TextField(
              controller: essayController,
              onChanged: onEssayChanged,
              minLines: 4,
              maxLines: 10,
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.45),
              decoration: InputDecoration(
                hintText: 'Write your answer...',
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
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
    final scheme = Theme.of(context).colorScheme;
    final g = grade;
    final full = g != null && g.effective >= g.outOf;
    final zero = g != null && g.effective <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: g == null
              ? scheme.outlineVariant
              : full
                  ? MarioColors.labelGreen.withValues(alpha: 0.6)
                  : zero
                      ? scheme.error.withValues(alpha: 0.4)
                      : MarioColors.labelYellow.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$index.',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(item.question,
                    style: GoogleFonts.inter(
                        fontSize: 13, height: 1.4, color: scheme.onSurface)),
              ),
              if (g != null)
                Text('${_trim(g.effective)}/${g.outOf}',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface)),
            ],
          ),
          const SizedBox(height: 8),
          if (item.kind == QuizItemKind.mcq)
            _McqReview(item: item, chosen: int.tryParse(answer))
          else
            _EssayReview(answer: answer),
          if (g != null && g.feedback.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(g.feedback,
                style: GoogleFonts.inter(
                    fontSize: 12, height: 1.4, color: scheme.onSurfaceVariant)),
          ],
          if (g != null && (g.matchedPoints.isNotEmpty || g.missedPoints.isNotEmpty)) ...[
            const SizedBox(height: 8),
            for (final p in g.matchedPoints)
              _RubricLine(text: p, matched: true),
            for (final p in g.missedPoints)
              _RubricLine(text: p, matched: false),
          ],
          if (g != null && g.isProvisional) ...[
            const SizedBox(height: 8),
            _MarkOverride(grade: g, onOverride: onOverride),
          ],
        ],
      ),
    );
  }
}

class _McqReview extends StatelessWidget {
  const _McqReview({required this.item, required this.chosen});
  final QuizItem item;
  final int? chosen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < item.options.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  i == item.correctIndex
                      ? Icons.check_circle
                      : (i == chosen ? Icons.cancel : Icons.circle_outlined),
                  size: 14,
                  color: i == item.correctIndex
                      ? MarioColors.labelGreen
                      : (i == chosen
                          ? scheme.error
                          : scheme.onSurfaceVariant.withValues(alpha: 0.35)),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    item.options[i],
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.35,
                      color: (i == item.correctIndex || i == chosen)
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight: i == item.correctIndex
                          ? FontWeight.w600
                          : FontWeight.w400,
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

class _EssayReview extends StatelessWidget {
  const _EssayReview({required this.answer});
  final String answer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        answer.trim().isEmpty ? '(no answer)' : answer.trim(),
        style: GoogleFonts.inter(
            fontSize: 12, height: 1.4, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _RubricLine extends StatelessWidget {
  const _RubricLine({required this.text, required this.matched});
  final String text;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(matched ? Icons.check : Icons.remove,
              size: 13,
              color: matched
                  ? MarioColors.labelGreen
                  : scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                height: 1.35,
                color: matched
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the student change a mark the model gave.
///
/// Not a nicety: the student is often a better judge of their own answer than
/// a 4B model, and a mark they cannot change is a mark they have to either
/// believe or ignore entirely.
class _MarkOverride extends StatelessWidget {
  const _MarkOverride({required this.grade, required this.onOverride});
  final QuizGrade grade;
  final ValueChanged<double> onOverride;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Wrap, not Row: an essay can carry up to 11 marks, and eleven chips plus
    // the label overflow a 360px panel — putting the higher marks off-screen,
    // which are exactly the ones a student wants to award themselves.
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Draft mark — change it:',
            style: GoogleFonts.inter(
                fontSize: 11, color: scheme.onSurfaceVariant)),
        for (var m = 0; m <= grade.outOf; m++)
          Padding(
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: () => onOverride(m.toDouble()),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: grade.effective == m
                      ? MarioColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Text('$m',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: grade.effective == m
                          ? MarioColors.onSurface
                          : scheme.onSurfaceVariant,
                    )),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? scheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? MarioColors.primary : scheme.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 16,
              color:
                  selected ? MarioColors.primaryPressed : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(detail,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          height: 1.3,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A count the user can nudge by one or jump to with a preset.
///
/// The presets exist because the useful range is wide: stepping from 20 to 50
/// one tap at a time is thirty taps, and a fine-grained control that nobody can
/// reach the end of is not a control.
class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.presets = const [],
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final List<int> presets;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 12.5, color: scheme.onSurface)),
            ),
            IconButton(
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove, size: 16),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
            SizedBox(
              width: 26,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface)),
            ),
            IconButton(
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add, size: 16),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
          ],
        ),
        if (presets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 2),
            child: Wrap(
              spacing: 5,
              children: [
                for (final p in presets)
                  _PresetChip(
                    value: p,
                    selected: value == p,
                    onTap: () => onChanged(p.clamp(min, max)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? MarioColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? MarioColors.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          '$value',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? MarioColors.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _NoPage extends StatelessWidget {
  const _NoPage();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Open a page to build a quiz from it.',
          textAlign: TextAlign.center,
          style:
              GoogleFonts.inter(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
