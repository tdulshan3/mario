/// The step list a run shows while it works.
///
/// The transitions matter more than they look: a step that never closes leaves
/// a spinner turning forever, and a step silently vanishing from the middle of
/// the list reads to the user as a crash. These tests pin the rules — one
/// active step at a time, jumped-over steps become "skipped" rather than
/// staying pending, and every terminal path closes the whole list.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_service.dart';
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/features/ai/ai_progress.dart';

void main() {
  AiRun newRun() => AiRun(const [
        AiStepKind.readingNote,
        AiStepKind.searchingWeb,
        AiStepKind.thinking,
        AiStepKind.answering,
      ]);

  AiStepState stateOf(AiRun run, AiStepKind kind) =>
      run.value.steps.firstWhere((s) => s.kind == kind).state;

  test('publishes the whole plan up front, all pending', () {
    final run = newRun();
    expect(run.value.steps.length, 4);
    expect(run.value.steps.every((s) => s.state == AiStepState.pending), isTrue);
    expect(run.value.status, AiRunStatus.running);
    run.dispose();
  });

  test('begin activates one step and closes the previous', () {
    final run = newRun();
    run.begin(AiStepKind.readingNote);
    expect(stateOf(run, AiStepKind.readingNote), AiStepState.active);

    run.begin(AiStepKind.thinking);
    expect(stateOf(run, AiStepKind.readingNote), AiStepState.done);
    expect(stateOf(run, AiStepKind.thinking), AiStepState.active);
    expect(run.value.steps.where((s) => s.state == AiStepState.active).length, 1);
    run.dispose();
  });

  test('a jumped-over step is skipped, not left pending', () {
    // No web search was needed, so that row must resolve rather than sit there
    // looking like it is still to come.
    final run = newRun();
    run.begin(AiStepKind.readingNote);
    run.begin(AiStepKind.thinking);
    expect(stateOf(run, AiStepKind.searchingWeb), AiStepState.skipped);
    run.dispose();
  });

  test('detail updates the active step without disturbing the plan', () {
    final run = newRun();
    run.begin(AiStepKind.readingNote, detail: 'page 1 of 12');
    run.detail('page 7 of 12');
    final step = run.value.steps.first;
    expect(step.detail, 'page 7 of 12');
    expect(step.state, AiStepState.active);
    expect(run.value.steps.length, 4);
    run.dispose();
  });

  test('finish closes every step and marks the run done', () {
    final run = newRun();
    run.begin(AiStepKind.readingNote);
    run.begin(AiStepKind.answering);
    run.finish();
    expect(run.value.status, AiRunStatus.done);
    expect(run.value.steps.any((s) => s.state == AiStepState.active), isFalse);
    expect(run.value.steps.any((s) => s.state == AiStepState.pending), isFalse);
    run.dispose();
  });

  test('fail marks the active step failed and keeps the message', () {
    final run = newRun();
    run.begin(AiStepKind.searchingWeb);
    run.fail(const LlmException('Connection refused'));
    expect(run.value.status, AiRunStatus.failed);
    expect(stateOf(run, AiStepKind.searchingWeb), AiStepState.failed);
    expect(run.value.error, 'Connection refused');
    run.dispose();
  });

  test('a cancellation is not reported as a failure', () {
    // The user pressing Stop is not an error, and must not surface a red banner.
    final run = newRun();
    run.begin(AiStepKind.thinking);
    run.fail(const LlmCancelled());
    expect(run.value.status, AiRunStatus.cancelled);
    expect(run.value.error, isNull);
    run.dispose();
  });

  test('cancel trips the token so the HTTP request actually stops', () {
    final run = newRun();
    run.begin(AiStepKind.thinking);
    expect(run.cancelToken.isCancelled, isFalse);
    run.cancel();
    expect(run.cancelToken.isCancelled, isTrue);
    expect(run.value.status, AiRunStatus.cancelled);
    run.dispose();
  });

  test('disposing a live run cancels it, so nothing keeps streaming', () {
    final run = newRun();
    run.begin(AiStepKind.answering);
    final token = run.cancelToken;
    run.dispose();
    expect(token.isCancelled, isTrue);
  });

  test('answer and reasoning accumulate on separate channels', () {
    final run = newRun();
    run.appendReasoning('let me think...');
    run.appendAnswer('The answer ');
    run.appendAnswer('is 4.');
    expect(run.value.answer, 'The answer is 4.');
    expect(run.value.reasoning, 'let me think...');
    run.dispose();
  });

  test('sources accumulate across several search rounds', () {
    final run = newRun();
    run.addSources(const [AiSource(title: 'A', url: 'https://a')]);
    run.addSources(const [AiSource(title: 'B', url: 'https://b')]);
    expect(run.value.sources.map((s) => s.title), ['A', 'B']);
    run.dispose();
  });

  group('writing to a disposed run is ignored, not fatal', () {
    // The task driving a run is a detached async function. It is still inside
    // `await provider.stream(...)` when the user closes the panel or starts a
    // different quiz and the panel disposes the run underneath it; the task
    // then continues to its next begin()/fail(). Before this was handled, that
    // threw "A AiRun was used after being disposed" out of an unawaited future.

    test('every mutator is a no-op after dispose', () {
      final run = newRun()..dispose();
      expect(() {
        run
          ..begin(AiStepKind.thinking)
          ..detail('still going')
          ..skip(AiStepKind.searchingWeb)
          ..appendAnswer('text')
          ..appendReasoning('thoughts')
          ..addSources(const [AiSource(title: 'A', url: 'https://a')])
          ..setBackend('qwen')
          ..setResult(const [1, 2, 3])
          ..finish();
      }, returnsNormally);
    });

    test('failing after dispose does not throw', () {
      // The common shape: the task catches an error and reports it to a run
      // that no longer exists.
      final run = newRun()..dispose();
      expect(() => run.fail(const LlmException('boom')), returnsNormally);
    });

    test('cancelling after dispose does not throw', () {
      final run = newRun()..dispose();
      expect(run.cancel, returnsNormally);
    });

    test('disposing twice is harmless', () {
      final run = newRun()..dispose();
      expect(run.dispose, returnsNormally);
    });

    test('adding a listener after dispose is a no-op', () {
      // A save-on-completion listener registered by a widget torn down in the
      // same frame.
      final run = newRun()..dispose();
      expect(() => run.addListener(() {}), returnsNormally);
    });

    test('isDisposed reports the state', () {
      final run = newRun();
      expect(run.isDisposed, isFalse);
      run.dispose();
      expect(run.isDisposed, isTrue);
    });

    test('state stays readable after dispose', () {
      // The UI may render one last frame from a run it just disposed.
      final run = newRun();
      run.begin(AiStepKind.readingNote);
      run.appendAnswer('partial');
      run.dispose();
      expect(run.value.answer, 'partial');
    });
  });

  test('a failure carries the raw model output for the UI to show', () {
    final run = newRun();
    run.begin(AiStepKind.thinking);
    run.fail(const StructuredOutputException('no JSON', raw: 'Sure! Here...'));
    expect(run.value.error, 'no JSON');
    expect(run.value.errorDetail, 'Sure! Here...');
    run.dispose();
  });
}
