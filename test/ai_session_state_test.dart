/// Work surviving a tab switch.
///
/// The panel renders one tab at a time with a `switch (tab)`, which destroys
/// the outgoing tab's widget. When each tab kept its work in its own `State`,
/// glancing at the quiz cancelled a streaming answer and threw it away; coming
/// back to the quiz tab found the generated questions and typed answers gone.
///
/// These tests pin the property that fixes it: the session providers hold the
/// work, the widgets are only views, and nothing but an explicit Stop ends a
/// run.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/ai_artifacts.dart';
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/features/ai/ai_progress.dart';
import 'package:mario/features/ai/ai_session_state.dart';
import 'package:mario/features/ai/ai_state.dart';
import 'package:mario/features/ai/ai_tasks.dart';
import 'package:mario/features/ai/agent_actions.dart';
import 'package:mario/features/ai/agent_executor.dart';
import 'package:mario/features/ai/grammar_check.dart';

void main() {
  AiRun newRun() => AiRun(const [AiStepKind.thinking, AiStepKind.answering]);

  QuizItem mcq(String id) => QuizItem(
        id: id,
        kind: QuizItemKind.mcq,
        question: 'Capital of France?',
        options: const ['Paris', 'Lyon', 'Nice', 'Metz'],
        correctIndex: 0,
      );

  group('the panel no longer owns or cancels a run', () {
    test('closing the panel does not stop the work', () {
      // It used to call run.cancel(), so looking away lost the answer.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final run = newRun();
      container.read(askSessionProvider.notifier).startRun(run, question: 'q');
      container.read(aiPanelProvider.notifier).close();

      expect(run.cancelToken.isCancelled, isFalse);
      expect(container.read(askSessionProvider).run, same(run));
    });

    test('switching tabs leaves every session untouched', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final askRun = newRun();
      container
          .read(askSessionProvider.notifier)
          .startRun(askRun, question: 'why');
      container.read(quizSessionProvider.notifier).generated([mcq('q1')], 'Q');

      final panel = container.read(aiPanelProvider.notifier)
        ..showTab(AiPanelTab.quiz)
        ..showTab(AiPanelTab.writing)
        ..showTab(AiPanelTab.ask);

      expect(panel.state.tab, AiPanelTab.ask);
      expect(askRun.cancelToken.isCancelled, isFalse);
      expect(container.read(askSessionProvider).run, same(askRun));
      expect(container.read(quizSessionProvider).items, hasLength(1));
    });
  });

  group('ask session', () {
    test('keeps a half-written question across a tab switch', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(askSessionProvider.notifier).setDraft('what is a mono');
      container.read(aiPanelProvider.notifier).showTab(AiPanelTab.quiz);
      expect(container.read(askSessionProvider).draft, 'what is a mono');
    });

    test('the web preference cycles auto -> on -> off -> auto', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(askSessionProvider.notifier);

      expect(container.read(askSessionProvider).useWeb, isNull);
      n.cycleWeb();
      expect(container.read(askSessionProvider).useWeb, isTrue);
      n.cycleWeb();
      expect(container.read(askSessionProvider).useWeb, isFalse);
      n.cycleWeb();
      expect(container.read(askSessionProvider).useWeb, isNull);
    });

    test('a new run retires the previous one', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = newRun();
      final second = newRun();
      final n = container.read(askSessionProvider.notifier)
        ..startRun(first, question: 'a')
        ..startRun(second, question: 'b');

      expect(first.isDisposed, isTrue);
      expect(second.isDisposed, isFalse);
      expect(n.state.lastQuestion, 'b');
    });

    test('stop is what cancels, and only that', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final run = newRun();
      final n = container.read(askSessionProvider.notifier)
        ..startRun(run, question: 'q');
      expect(run.cancelToken.isCancelled, isFalse);
      n.stop();
      expect(run.cancelToken.isCancelled, isTrue);
    });

    test('an inserted answer is remembered, so it is not inserted twice', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final run = newRun();
      final n = container.read(askSessionProvider.notifier)
        ..startRun(run, question: 'q');
      expect(n.alreadyInserted(run), isFalse);
      n.insertFinished();
      expect(n.alreadyInserted(run), isTrue);
    });

    test('a failed insert is not recorded as inserted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final run = newRun();
      final n = container.read(askSessionProvider.notifier)
        ..startRun(run, question: 'q')
        ..insertFinished(error: 'page closed');
      expect(n.alreadyInserted(run), isFalse);
      expect(container.read(askSessionProvider).insertError, 'page closed');
    });
  });

  group('agent review and HTML preview', () {
    AgentPlan plan() => const AgentPlan(
          summary: 'Add one paragraph',
          actions: [
            AgentAction(kind: AgentActionKind.paragraph, text: 'new text'),
          ],
        );

    AgentSnapshot snapshot() =>
        const AgentSnapshot(document: {}, title: 'Before');

    test('a validated plan waits until it is approved', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(agentSessionProvider.notifier);

      final decision = notifier.reviewPlan(plan());
      expect(container.read(agentSessionProvider).review?.plan.actions,
          hasLength(1));

      notifier.approve(snapshot());
      expect(await decision, isTrue);
      expect(container.read(agentSessionProvider).review, isNull);
      expect(container.read(agentSessionProvider).snapshot?.title, 'Before');
    });

    test('discarding a preview applies nothing', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(agentSessionProvider.notifier);

      final decision = notifier.reviewPlan(plan());
      notifier.discardReview();

      expect(await decision, isFalse);
      expect(container.read(agentSessionProvider).review, isNull);
    });

    test('an Ask artifact survives the tab switch until applied or closed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const html = '<!doctype html><html><body>Artifact</body></html>';

      container.read(agentSessionProvider.notifier).previewArtifact(html);
      container.read(aiPanelProvider.notifier).showTab(AiPanelTab.ask);
      container.read(aiPanelProvider.notifier).showTab(AiPanelTab.agent);

      expect(container.read(agentSessionProvider).artifactDraft, html);
      expect(container.read(agentSessionProvider).artifactApplied, isFalse);
    });
  });

  group('quiz session', () {
    test('answers survive a tab switch', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(quizSessionProvider.notifier)
        ..generated([mcq('q1'), mcq('q2')], 'Chapter 4')
        ..answer('q1', '0')
        ..answer('q2', '2');

      container.read(aiPanelProvider.notifier).showTab(AiPanelTab.ask);

      final s = container.read(quizSessionProvider);
      expect(s.phase, QuizPhase.answering);
      expect(s.answers, {'q1': '0', 'q2': '2'});
      expect(s.title, 'Chapter 4');
    });

    test('defaults to a revision-sized paper, not a demo', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final s = container.read(quizSessionProvider);
      expect(s.mcqCount, greaterThanOrEqualTo(20));
      expect(s.essayCount, greaterThanOrEqualTo(2));
    });

    test('the counts are user-adjustable across the whole useful range', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(quizSessionProvider.notifier);

      n.setMcqCount(50);
      expect(container.read(quizSessionProvider).mcqCount, 50);
      n.setMcqCount(0);
      expect(container.read(quizSessionProvider).mcqCount, 0);
      n.setEssayCount(10);
      expect(container.read(quizSessionProvider).essayCount, 10);
    });

    test('scope and counts persist so they are set once, not every time', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(quizSessionProvider.notifier)
        ..setScope(QuizScope.section)
        ..setMcqCount(10)
        ..setEssayCount(2);

      final s = container.read(quizSessionProvider);
      expect(s.scope, QuizScope.section);
      expect(s.mcqCount, 10);
      expect(s.essayCount, 2);
    });

    test('reset keeps the setup choices but clears the quiz', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final n = container.read(quizSessionProvider.notifier)
        ..setScope(QuizScope.section)
        ..setMcqCount(8)
        ..generated([mcq('q1')], 'Q')
        ..answer('q1', '0')
        ..reset();

      final s = container.read(quizSessionProvider);
      expect(s.items, isEmpty);
      expect(s.answers, isEmpty);
      expect(s.phase, QuizPhase.setup);
      // Re-picking "this section, 8 questions" every time would be tedious.
      expect(s.scope, QuizScope.section);
      expect(s.mcqCount, 8);
      expect(n.state.essayCount, QuizTasks.defaultEssayCount);
    });

    test('marking accumulates and totals correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(quizSessionProvider.notifier)
        ..generated([mcq('q1'), mcq('q2')], 'Q')
        ..startMarking('attempt-1', CancelToken())
        ..graded(
            'q1',
            const QuizGrade(
                itemId: 'q1', awarded: 1, outOf: 1, isProvisional: false))
        ..graded(
            'q2',
            const QuizGrade(
                itemId: 'q2', awarded: 0, outOf: 1, isProvisional: false))
        ..markingFinished();

      final s = container.read(quizSessionProvider);
      expect(s.phase, QuizPhase.results);
      expect(s.awarded, 1);
      expect(s.outOf, 2);
      expect(s.markingDone, 2);
      expect(s.anyProvisional, isFalse);
    });

    test('marking can be stopped part-way, keeping what was marked', () {
      // A paper of essays is minutes of model calls; without this the only way
      // out was to wait it out.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final cancel = CancelToken();
      container.read(quizSessionProvider.notifier)
        ..generated([mcq('q1'), mcq('q2')], 'Q')
        ..startMarking('attempt-1', cancel)
        ..graded('q1', const QuizGrade(itemId: 'q1', awarded: 1, outOf: 1))
        ..stopMarking();

      expect(cancel.isCancelled, isTrue);
      final s = container.read(quizSessionProvider);
      expect(s.phase, QuizPhase.results);
      expect(s.grades, hasLength(1),
          reason: 'a half-marked paper still counts');
    });

    test('remembers which notebook the quiz belongs to', () {
      // The session is app-level: a quiz can be submitted while a different
      // notebook is on screen, and its marks must not be filed under that one.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final quiz = Quiz(
        id: 'quiz-1',
        title: 'Q',
        scope: QuizScope.section,
        scopeId: 's1',
        items: [mcq('q1')],
        sourceHash: 'h',
        provenance: AiProvenance(
            backend: 'local', model: 'q', createdAt: DateTime(2026)),
      );
      container
          .read(quizSessionProvider.notifier)
          .setQuiz(quiz, notebookId: 'nb-original');

      expect(container.read(quizSessionProvider).notebookId, 'nb-original');
    });

    test('a student override wins over the model mark', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(quizSessionProvider.notifier)
        ..generated([mcq('q1')], 'Q')
        ..startMarking('attempt-1', CancelToken())
        ..graded('q1', const QuizGrade(itemId: 'q1', awarded: 1, outOf: 4))
        ..overrideMark('q1', 4);

      expect(container.read(quizSessionProvider).awarded, 4);
    });

    test('the attempt id is stable across overrides', () {
      // Otherwise correcting a mark files a second attempt.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(quizSessionProvider.notifier)
        ..generated([mcq('q1')], 'Q')
        ..startMarking('attempt-1', CancelToken())
        ..graded('q1', const QuizGrade(itemId: 'q1', awarded: 1, outOf: 4))
        ..overrideMark('q1', 3);

      expect(container.read(quizSessionProvider).attemptId, 'attempt-1');
    });

    test('retake reloads a saved quiz ready to answer', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final quiz = Quiz(
        id: 'quiz-1',
        title: 'Chapter 4',
        scope: QuizScope.page,
        scopeId: 'p1',
        items: [mcq('q1')],
        sourceHash: 'h',
        provenance: AiProvenance(
            backend: 'local', model: 'q', createdAt: DateTime(2026)),
      );
      container.read(quizSessionProvider.notifier).retake(quiz);

      final s = container.read(quizSessionProvider);
      expect(s.phase, QuizPhase.answering);
      expect(s.items, hasLength(1));
      expect(s.answers, isEmpty, reason: 'a retake starts from a blank paper');
      expect(s.quiz, same(quiz));
    });

    test('review reopens a marked attempt without re-marking it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final quiz = Quiz(
        id: 'quiz-1',
        title: 'Chapter 4',
        scope: QuizScope.page,
        scopeId: 'p1',
        items: [mcq('q1')],
        sourceHash: 'h',
        provenance: AiProvenance(
            backend: 'local', model: 'q', createdAt: DateTime(2026)),
      );
      final attempt = QuizAttempt(
        id: 'attempt-1',
        quizId: 'quiz-1',
        answers: const {'q1': '0'},
        grades: const {
          'q1': QuizGrade(itemId: 'q1', awarded: 1, outOf: 1),
        },
        startedAt: DateTime(2026),
      );
      container.read(quizSessionProvider.notifier).review(quiz, attempt);

      final s = container.read(quizSessionProvider);
      expect(s.phase, QuizPhase.results);
      expect(s.answers, {'q1': '0'});
      expect(s.awarded, 1);
      expect(s.attemptId, 'attempt-1');
    });
  });

  group('writing session', () {
    const suggestion = GrammarSuggestion(
      nodeId: 'n1',
      before: 'Their going',
      after: "They're going",
      kind: GrammarIssueKind.grammar,
    );

    test('suggestions and their outcomes survive a tab switch', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(writingSessionProvider.notifier)
        ..startCheck(newRun())
        ..checked(const [suggestion])
        ..resolve(0, SuggestionOutcome.applied);

      container.read(aiPanelProvider.notifier).showTab(AiPanelTab.quiz);

      final s = container.read(writingSessionProvider);
      expect(s.suggestions, hasLength(1));
      expect(s.outcomes[0], SuggestionOutcome.applied);
      expect(s.pending, 0);
    });

    test('pending counts only the unresolved ones', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(writingSessionProvider.notifier)
        ..startCheck(newRun())
        ..checked(const [suggestion, suggestion, suggestion])
        ..resolve(1, SuggestionOutcome.ignored);

      expect(container.read(writingSessionProvider).pending, 2);
    });

    test('outcomes are keyed by position, so duplicates stay distinct', () {
      // GrammarSuggestion has no value equality; identical suggestions keyed by
      // object would resolve each other.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(writingSessionProvider.notifier)
        ..startCheck(newRun())
        ..checked(const [suggestion, suggestion])
        ..resolve(0, SuggestionOutcome.applied);

      final s = container.read(writingSessionProvider);
      expect(s.outcomes[0], SuggestionOutcome.applied);
      expect(s.outcomes[1], isNull);
    });

    test('a new check retires the previous run and its results', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = newRun();
      container.read(writingSessionProvider.notifier)
        ..startCheck(first)
        ..checked(const [suggestion])
        ..startCheck(newRun());

      expect(first.isDisposed, isTrue);
      expect(container.read(writingSessionProvider).suggestions, isEmpty);
    });
  });
}
