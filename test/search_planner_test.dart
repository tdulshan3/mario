/// Letting the model say what to search for.
///
/// The queries this replaces were mechanical transforms: `/ask` sent the user's
/// sentence verbatim, and a hard quiz glued a note's title to its first three
/// headings. Both are queries no person would type, and the second is four
/// topics at once.
///
/// The property that matters most here is not query quality — that is the
/// model's job — but that this can never break searching. It sits in front of
/// every search the app makes, so a planner that throws, hangs, or returns
/// nothing usable must leave the caller exactly where it started.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider.dart';
import 'package:mario/core/services/ai/llm_service.dart';
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/features/ai/search_planner.dart';

void main() {
  Future<SearchPlan> plan(
    _FakeLlm llm, {
    String task = 'does this still apply?',
    String fallback = 'does this still apply?',
    String? context,
    int maxQueries = 2,
  }) =>
      planSearch(
        llm: llm,
        task: task,
        fallback: fallback,
        context: context,
        maxQueries: maxQueries,
      );

  group('the model chooses', () {
    test('its queries are used, and marked as its own', () async {
      final result = await plan(_FakeLlm.replying({
        'needsSearch': true,
        'queries': ['GDPR Article 22 automated decision-making 2026'],
      }));
      expect(
          result.queries, ['GDPR Article 22 automated decision-making 2026']);
      expect(result.fromModel, isTrue);
    });

    test('it can say the web adds nothing', () async {
      // A question about what the user already wrote does not need a search,
      // and spending a paid query to learn that is the wrong trade.
      final result = await plan(_FakeLlm.replying({
        'needsSearch': false,
        'queries': ['x'],
      }));
      expect(result.needsSearch, isFalse);
    });

    test('more queries than the cap are trimmed, not sent', () async {
      // Serper bills per query against a daily allowance; a model that wants
      // five searches does not get to spend five credits.
      final result = await plan(
        _FakeLlm.replying({
          'needsSearch': true,
          'queries': ['a', 'b', 'c', 'd', 'e'],
        }),
        maxQueries: 2,
      );
      expect(result.queries, ['a', 'b']);
    });

    test('what it is shown includes the passage the pronoun points at',
        () async {
      // The whole reason this exists: "does this still apply?" carries its
      // subject in a pronoun, and the subject is in the highlighted passage.
      final llm = _FakeLlm.replying({
        'needsSearch': true,
        'queries': ['q'],
      });
      await plan(llm, context: 'Article 22 of the GDPR restricts…');
      expect(llm.lastPrompt, contains('Article 22'));
    });

    test('a very long context is cut rather than sent whole', () async {
      // A planning call that costs as much as the answer is not worth making.
      final llm = _FakeLlm.replying({
        'needsSearch': true,
        'queries': ['q'],
      });
      await plan(llm, context: 'x' * 5000);
      expect(llm.lastPrompt.length, lessThan(2000));
    });
  });

  group('it cannot break searching', () {
    test('a backend that cannot do structured output falls back', () async {
      final result = await plan(_FakeLlm.throwing(
          const StructuredOutputException('no json_schema support')));
      expect(result.queries, ['does this still apply?']);
      expect(result.fromModel, isFalse);
      expect(result.needsSearch, isTrue);
    });

    test('a network failure falls back', () async {
      final result = await plan(
          _FakeLlm.throwing(const LlmException('connection refused')));
      expect(result.queries, ['does this still apply?']);
    });

    test('a reply of the wrong type falls back rather than throwing', () async {
      // A 4B returns a bare string where the schema says array often enough
      // that a cast here would throw past every guard this function provides.
      final result = await plan(_FakeLlm.replying({
        'needsSearch': true,
        'queries': {'not': 'a list'},
      }));
      expect(result.queries, ['does this still apply?']);
      expect(result.fromModel, isFalse);
    });

    test('a bare string of queries is read, not discarded', () async {
      final result = await plan(_FakeLlm.replying({
        'needsSearch': true,
        'queries': 'GDPR Article 22',
      }));
      expect(result.queries, ['GDPR Article 22']);
    });

    test('an empty or blank query list falls back', () async {
      for (final queries in [
        <String>[],
        ['  ', '']
      ]) {
        final result = await plan(_FakeLlm.replying({
          'needsSearch': true,
          'queries': queries,
        }));
        expect(result.queries, ['does this still apply?'], reason: '$queries');
      }
    });

    test('cancellation is passed through, not swallowed', () async {
      // Stopping a run is the user's decision; turning it into a fallback
      // search would spend a credit they just declined to spend.
      expect(
        () => plan(_FakeLlm.throwing(const LlmCancelled())),
        throwsA(isA<LlmCancelled>()),
      );
    });

    test('no fallback and a failed plan means no search at all', () async {
      // Better than searching for an empty string, which spends a request to
      // learn nothing.
      final result = await plan(
        _FakeLlm.throwing(const LlmException('x')),
        fallback: '   ',
      );
      expect(result.queries, isEmpty);
      expect(result.needsSearch, isFalse);
    });

    test('an empty task does not reach the model at all', () async {
      final llm = _FakeLlm.replying({
        'needsSearch': true,
        'queries': ['q']
      });
      final result = await plan(llm, task: '   ', fallback: 'topic');
      expect(llm.calls, 0);
      expect(result.queries, ['topic']);
    });
  });

  group('what it is allowed to see', () {
    test('the planning call is small', () async {
      final llm = _FakeLlm.replying({
        'needsSearch': true,
        'queries': ['q']
      });
      await plan(llm);
      expect(llm.lastRequest!.maxTokens, lessThanOrEqualTo(400),
          reason: 'a planning call that costs as much as the answer is not '
              'worth making');
    });
  });
}

class _FakeLlm implements LlmService {
  _FakeLlm.replying(this._reply) : _error = null;
  _FakeLlm.throwing(this._error) : _reply = null;

  final Map<String, dynamic>? _reply;
  final Object? _error;

  var calls = 0;
  LlmRequest? lastRequest;
  String get lastPrompt => lastRequest?.messages.last.content ?? '';

  @override
  Future<Map<String, dynamic>> structured({
    required LlmRequest request,
    required String schemaName,
    required Map<String, dynamic> schema,
    CancelToken? cancel,
    bool describeSchema = true,
    int repairAttempts = 1,
  }) async {
    calls++;
    lastRequest = request;
    if (_error != null) throw _error;
    return _reply!;
  }

  @override
  Future<LlmProvider> requireProvider([String? id]) =>
      throw UnimplementedError();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
