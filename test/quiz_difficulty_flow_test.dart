/// What the two difficulties actually *do* differently at run time.
///
/// `quiz_style_test.dart` checks the rules read correctly. This checks they
/// arrive: that hard mode looks the subject up before writing anything, that
/// easy mode does not, and that what comes back reaches the prompt. The whole
/// feature is a prompt and a search, so a wiring mistake here would leave both
/// difficulties producing identical quizzes while the UI insisted otherwise —
/// a failure nothing else in the suite would notice.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider.dart';
import 'package:mario/core/services/ai/llm_service.dart';
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/core/services/ai/web_search_service.dart';
import 'package:mario/features/ai/ai_progress.dart';
import 'package:mario/features/ai/ai_tasks.dart';
import 'package:mario/features/ai/note_context.dart';
import 'package:mario/features/ai/quiz_style.dart';

/// Waits for a run to stop running. `AiRun` reports through a listener rather
/// than a future, because the UI wants every intermediate state, not just the
/// last one.
Future<AiRunState> settle(AiRun run) {
  if (run.value.status != AiRunStatus.running) return Future.value(run.value);
  final completer = Completer<AiRunState>();
  void listener() {
    if (run.value.status != AiRunStatus.running && !completer.isCompleted) {
      completer.complete(run.value);
    }
  }

  run.addListener(listener);
  return completer.future.whenComplete(() => run.removeListener(listener));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final note = NoteText(
    title: 'Cell Respiration',
    blocks: const [
      NoteBlock(
        nodeId: 'h1',
        path: [0],
        type: 'heading',
        text: 'Glycolysis',
        headingLevel: 2,
      ),
      NoteBlock(
        nodeId: 'p1',
        path: [1],
        type: 'paragraph',
        text: 'Glucose is split into two pyruvate molecules, netting 2 ATP.',
      ),
    ],
  );

  /// Runs a quiz to completion and hands back what the fakes saw.
  Future<({_RecordingLlm llm, _RecordingSearch search, AiRunState state})> run(
    QuizDifficulty difficulty, {
    List<AiSource> results = const [
      AiSource(title: 'Glycolysis explained', url: 'https://example.com/gly'),
    ],
    bool searchEnabled = true,
    Object? searchThrows,
  }) async {
    final llm = _RecordingLlm();
    final search = _RecordingSearch(
      results: results,
      enabled: searchEnabled,
      throws: searchThrows,
    );
    final tasks = AiTasks(llm: llm, search: search);
    final r = tasks.generateQuiz(
      note: note,
      scopeLabel: 'This page',
      mcqCount: 2,
      essayCount: 0,
      difficulty: difficulty,
    );
    final state = await settle(r);
    r.dispose();
    return (llm: llm, search: search, state: state);
  }

  group('hard mode looks the subject up first', () {
    test('easy never touches the network', () async {
      final it = await run(QuizDifficulty.easy);
      expect(it.search.queries, isEmpty);
      expect(it.state.error, isNull);
    });

    test('hard searches once, before generating', () async {
      final it = await run(QuizDifficulty.hard);
      expect(it.search.queries, hasLength(1),
          reason: 'searching per batch would multiply cost for no new context');
      expect(it.search.queries.single, contains('Cell Respiration'));
      expect(it.search.queries.single, contains('Glycolysis'));
    });

    test('the search step is in the plan from the start in hard mode',
        () async {
      // Announcing a step only once it begins makes the plan jump around; the
      // user should see what is coming.
      final hard = await run(QuizDifficulty.hard);
      expect(hard.state.steps.map((s) => s.kind),
          contains(AiStepKind.searchingWeb));

      final easy = await run(QuizDifficulty.easy);
      expect(easy.state.steps.map((s) => s.kind),
          isNot(contains(AiStepKind.searchingWeb)));
    });

    test('what it finds is shown as sources', () async {
      final it = await run(QuizDifficulty.hard);
      expect(it.state.sources, hasLength(1));
      expect(it.state.searchQuery, isNotEmpty);
    });
  });

  group('the difficulty reaches the model', () {
    test('easy sends the easy rules, and not the hard ones', () async {
      final it = await run(QuizDifficulty.easy);
      final system = it.llm.quizRequest.system!;
      expect(system, contains(quizStyleEasy));
      expect(system, isNot(contains(quizStyleHard)));
    });

    test('hard sends the hard rules, and not the easy ones', () async {
      final it = await run(QuizDifficulty.hard);
      final system = it.llm.quizRequest.system!;
      expect(system, contains(quizStyleHard));
      expect(system, isNot(contains(quizStyleEasy)));
    });

    test('both send the shared item-writing rules', () async {
      for (final d in QuizDifficulty.values) {
        final it = await run(d);
        expect(it.llm.quizRequest.system, contains(quizStyleCore),
            reason: d.name);
      }
    });

    test('web results are put in front of the model, with the notes', () async {
      final it = await run(QuizDifficulty.hard);
      final user = it.llm.quizRequest.messages.last.content;
      expect(user, contains('Glycolysis explained'));
      expect(user, contains('example.com'));
      expect(user, contains('pyruvate'),
          reason: 'the notes are still the subject');
    });

    test('easy sends no web context at all', () async {
      final it = await run(QuizDifficulty.easy);
      expect(it.llm.quizRequest.messages.last.content,
          isNot(contains('example.com')));
    });
  });

  group('when the lookup cannot happen', () {
    // Hard mode is degraded without the web, not broken. Refusing to make a
    // quiz because a search key is missing would be the wrong trade.

    test('search turned off still produces a quiz', () async {
      final it = await run(QuizDifficulty.hard, searchEnabled: false);
      expect(it.state.error, isNull);
      expect(it.state.result, isNotNull);
      expect(it.llm.quizRequest.system, contains(quizStyleHard),
          reason: 'the reasoning rules apply with or without the web');
    });

    test('a failing search is survived', () async {
      final it = await run(
        QuizDifficulty.hard,
        searchThrows: const LlmException('Serper rejected the API key.'),
      );
      expect(it.state.error, isNull);
      expect(it.state.result, isNotNull);
    });

    test('a search that finds nothing is survived', () async {
      final it = await run(QuizDifficulty.hard, results: const []);
      expect(it.state.error, isNull);
      expect(it.state.result, isNotNull);
    });

    test('a note with nothing to search for skips the lookup', () async {
      final llm = _RecordingLlm();
      final search = _RecordingSearch();
      final tasks = AiTasks(llm: llm, search: search);
      final r = tasks.generateQuiz(
        note: const NoteText(title: 'Untitled', blocks: [
          NoteBlock(
              nodeId: 'p', path: [0], type: 'paragraph', text: 'some prose'),
        ]),
        scopeLabel: 'This page',
        mcqCount: 1,
        essayCount: 0,
        difficulty: QuizDifficulty.hard,
      );
      await settle(r);
      expect(search.queries, isEmpty,
          reason: 'an empty query spends a request to learn nothing');
      expect(r.value.error, isNull);
      r.dispose();
    });
  });
}

/// An LLM that answers every structured request with valid quiz JSON and keeps
/// what it was asked.
class _RecordingLlm implements LlmService {
  final requests = <LlmRequest>[];
  final schemaNames = <String>[];
  var _n = 0;

  /// The quiz-generation call, as opposed to the search-query planning call
  /// that now runs before it in hard mode.
  LlmRequest get quizRequest =>
      requests[schemaNames.indexWhere((n) => n.contains('quiz'))];

  @override
  Future<LlmProvider> requireProvider([String? id]) async => _StubProvider();

  @override
  LlmEffort get userEffort => LlmEffort.medium;

  @override
  Future<Map<String, dynamic>> structured({
    required LlmRequest request,
    required String schemaName,
    required Map<String, dynamic> schema,
    CancelToken? cancel,
    bool describeSchema = true,
    int repairAttempts = 1,
  }) async {
    requests.add(request);
    schemaNames.add(schemaName);
    // Distinct stems each round, or the de-duplicator drops the second batch
    // and the run ends early for a reason that has nothing to do with the test.
    final i = _n++;
    return {
      'title': 'Cell Respiration',
      'items': [
        {
          'kind': 'mcq',
          'question': 'What does glycolysis yield, take $i?',
          'options': ['2 ATP', '4 ATP', '36 ATP', 'No ATP'],
          'correctIndex': 0,
          'explanation': 'Net two, after the two spent activating glucose.',
        },
      ],
    };
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Just enough of a provider to name itself and report a context window.
class _StubProvider implements LlmProvider {
  @override
  String get displayName => 'Test model';

  @override
  LlmCapabilities get capabilities =>
      const LlmCapabilities(contextTokens: 32000);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A search service that records its queries instead of making them.
class _RecordingSearch implements WebSearchService {
  _RecordingSearch({
    this.results = const [],
    this.enabled = true,
    this.throws,
  });

  final List<AiSource> results;
  final bool enabled;
  final Object? throws;
  final queries = <String>[];

  @override
  Future<bool> get isEnabled async => enabled;

  @override
  Future<WebSearchStatus> status() async =>
      enabled ? WebSearchStatus.ready : WebSearchStatus.turnedOff;

  @override
  Future<int> remainingToday() async => WebSearchService.dailyLimit;

  @override
  Future<List<AiSource>> search(String query,
      {int limit = 5, CancelToken? cancel}) async {
    queries.add(query);
    if (throws != null) throw throws!;
    return results;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
