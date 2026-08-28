/// AiRun — the step-by-step progress of one AI request.
///
/// A local 1-4B model answering a question about a whole section can run for
/// the better part of a minute. A single spinner for that is indistinguishable
/// from a hang, so every run publishes the plan it intends to follow — reading
/// the note, searching the web, thinking, answering — and then ticks through
/// it. The user can see which stage is slow, and cancel.
///
/// The steps are declared up front rather than appended as they happen: a list
/// that grows one row at a time reads as "something else went wrong", while a
/// dimmed row that lights up reads as progress. Steps that turn out not to be
/// needed are marked [AiStepState.skipped] instead of vanishing, so the shape
/// of the list never jumps around.
///
/// Pure state — no widgets, no I/O. The panel is a [ValueListenableBuilder]
/// over [AiRun.value], and the transitions are covered by
/// test/ai_progress_test.dart.
library;

import 'package:flutter/foundation.dart';

import '../../core/services/ai/llm_types.dart';
import '../../core/services/ai/json_coercion.dart';

enum AiStepKind {
  readingNote,
  readingSection,
  recallingContext,
  searchingWeb,
  readingSources,
  thinking,
  answering,
  checking,
  saving,
}

extension AiStepKindLabel on AiStepKind {
  /// Present-tense while running; the UI switches to [pastLabel] once done.
  String get label => switch (this) {
        AiStepKind.readingNote => 'Reading the note',
        AiStepKind.readingSection => 'Reading the section',
        AiStepKind.recallingContext => 'Recalling saved context',
        AiStepKind.searchingWeb => 'Searching the web',
        AiStepKind.readingSources => 'Reading sources',
        AiStepKind.thinking => 'Thinking',
        AiStepKind.answering => 'Answering',
        AiStepKind.checking => 'Checking the answer',
        AiStepKind.saving => 'Saving to the page',
      };

  String get pastLabel => switch (this) {
        AiStepKind.readingNote => 'Read the note',
        AiStepKind.readingSection => 'Read the section',
        AiStepKind.recallingContext => 'Recalled saved context',
        AiStepKind.searchingWeb => 'Searched the web',
        AiStepKind.readingSources => 'Read sources',
        AiStepKind.thinking => 'Thought it through',
        AiStepKind.answering => 'Answered',
        AiStepKind.checking => 'Checked the answer',
        AiStepKind.saving => 'Saved to the page',
      };
}

enum AiStepState { pending, active, done, failed, skipped }

@immutable
class AiStep {
  const AiStep({
    required this.kind,
    this.state = AiStepState.pending,
    this.detail,
    this.elapsed,
  });

  final AiStepKind kind;
  final AiStepState state;

  /// The specific thing this step is doing right now — "page 3 of 12",
  /// "qwen3:4b", the search query. Nullable because most steps have nothing
  /// useful to add until they start.
  final String? detail;

  final Duration? elapsed;

  AiStep copyWith({
    AiStepState? state,
    String? detail,
    Duration? elapsed,
  }) =>
      AiStep(
        kind: kind,
        state: state ?? this.state,
        detail: detail ?? this.detail,
        elapsed: elapsed ?? this.elapsed,
      );

  @override
  bool operator ==(Object other) =>
      other is AiStep &&
      other.kind == kind &&
      other.state == state &&
      other.detail == detail &&
      other.elapsed == elapsed;

  @override
  int get hashCode => Object.hash(kind, state, detail, elapsed);
}

/// A web result the run consulted, kept so the answer can cite it and the
/// citation can survive into the note.
@immutable
class AiSource {
  const AiSource({
    required this.title,
    required this.url,
    this.snippet = '',
  });

  final String title;
  final String url;
  final String snippet;

  Map<String, dynamic> toJson() =>
      {'title': title, 'url': url, if (snippet.isNotEmpty) 'snippet': snippet};

  factory AiSource.fromJson(Map<String, dynamic> m) => AiSource(
        title: asStringOr(m['title']),
        url: asStringOr(m['url']),
        snippet: asStringOr(m['snippet']),
      );
}

enum AiRunStatus { idle, running, done, failed, cancelled }

@immutable
class AiRunState {
  const AiRunState({
    this.steps = const [],
    this.answer = '',
    this.reasoning = '',
    this.sources = const [],
    this.status = AiRunStatus.idle,
    this.error,
    this.errorDetail,
    this.backendLabel,
    this.result,
  });

  final List<AiStep> steps;

  /// The visible answer, accumulated as it streams.
  final String answer;

  /// The model's separate thinking channel. Shown behind a disclosure and
  /// never written into the user's note — it is not the answer.
  final String reasoning;

  final List<AiSource> sources;
  final AiRunStatus status;
  final String? error;

  /// The raw model output behind a failure, when there was one. Shown behind a
  /// disclosure rather than inline — it is diagnostic, not an answer.
  final String? errorDetail;

  /// Which backend produced this — "LAN · qwen3:4b", "Claude". Shown next to
  /// the answer, because the same question gets a different answer from a 1.7B
  /// model than from Claude and the user deserves to know which they got.
  final String? backendLabel;

  /// A structured payload for runs whose output is not prose — quiz generation
  /// puts its validated `List<QuizItem>` here while [answer] holds the title.
  /// Untyped because [AiRun] is shared by every task and must not depend on any
  /// one task's model.
  final Object? result;

  bool get isRunning => status == AiRunStatus.running;
  bool get hasAnswer => answer.trim().isNotEmpty;

  AiStep? get activeStep =>
      steps.where((s) => s.state == AiStepState.active).firstOrNull;

  AiRunState copyWith({
    List<AiStep>? steps,
    String? answer,
    String? reasoning,
    List<AiSource>? sources,
    AiRunStatus? status,
    String? error,
    String? errorDetail,
    String? backendLabel,
    Object? result,
  }) =>
      AiRunState(
        steps: steps ?? this.steps,
        answer: answer ?? this.answer,
        reasoning: reasoning ?? this.reasoning,
        sources: sources ?? this.sources,
        status: status ?? this.status,
        error: error ?? this.error,
        errorDetail: errorDetail ?? this.errorDetail,
        backendLabel: backendLabel ?? this.backendLabel,
        result: result ?? this.result,
      );
}

/// Drives an [AiRunState] through one request.
///
/// Owns the [CancelToken] so the panel's Stop button reaches the HTTP socket
/// rather than merely hiding the result.
///
/// **Every mutator is a no-op once disposed.** The task driving a run is a
/// detached async function — it is still inside `await provider.stream(...)`
/// when the user closes the panel, starts a different quiz, or navigates away,
/// and the panel disposes the run underneath it. The task then continues to
/// the next `begin()` or `fail()` and, without this, hits
/// `A AiRun was used after being disposed`. Cancellation is cooperative and
/// only lands at await boundaries, so there is always a window where a write
/// arrives late. Dropping those writes is the correct semantics rather than a
/// workaround: a disposed run is one nobody is looking at, and its progress is
/// genuinely irrelevant.
class AiRun extends ValueNotifier<AiRunState> {
  AiRun(List<AiStepKind> plan)
      : cancelToken = CancelToken(),
        super(AiRunState(
          steps: [for (final k in plan) AiStep(kind: k)],
          status: AiRunStatus.running,
        ));

  final CancelToken cancelToken;
  final _stopwatch = Stopwatch();
  Duration _stepStartedAt = Duration.zero;

  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// Marks [kind] active, closing out whatever was active before it.
  ///
  /// Steps between the previously-active one and this one are marked skipped
  /// rather than left pending — running a step out of order means the ones it
  /// jumped over are not going to happen (no web search was needed, the cached
  /// context was a hit), and the list should say so.
  void begin(AiStepKind kind, {String? detail}) {
    if (_disposed) return;
    if (!_stopwatch.isRunning) _stopwatch.start();
    final now = _stopwatch.elapsed;
    final target = value.steps.indexWhere((s) => s.kind == kind);
    if (target < 0) return;

    final steps = <AiStep>[];
    for (var i = 0; i < value.steps.length; i++) {
      final s = value.steps[i];
      if (i == target) {
        steps.add(s.copyWith(state: AiStepState.active, detail: detail));
      } else if (s.state == AiStepState.active) {
        steps.add(s.copyWith(
            state: AiStepState.done, elapsed: now - _stepStartedAt));
      } else if (i < target && s.state == AiStepState.pending) {
        steps.add(s.copyWith(state: AiStepState.skipped));
      } else {
        steps.add(s);
      }
    }
    _stepStartedAt = now;
    value = value.copyWith(steps: steps);
  }

  /// Updates the detail line of the active step without changing the plan —
  /// "page 4 of 12" ticking upward inside one step.
  void detail(String detail) {
    if (_disposed) return;
    final idx = value.steps.indexWhere((s) => s.state == AiStepState.active);
    if (idx < 0) return;
    final steps = [...value.steps];
    steps[idx] = steps[idx].copyWith(detail: detail);
    value = value.copyWith(steps: steps);
  }

  void skip(AiStepKind kind) => _setState(kind, AiStepState.skipped);

  /// Attaching to a finished-and-disposed run is a no-op rather than a throw.
  /// A save-on-completion listener can be registered by a widget that is torn
  /// down in the same frame.
  @override
  void addListener(VoidCallback listener) {
    if (_disposed) return;
    super.addListener(listener);
  }

  void appendAnswer(String text) {
    if (_disposed || text.isEmpty) return;
    value = value.copyWith(answer: value.answer + text);
  }

  void appendReasoning(String text) {
    if (_disposed || text.isEmpty) return;
    value = value.copyWith(reasoning: value.reasoning + text);
  }

  void addSources(List<AiSource> sources) {
    if (_disposed || sources.isEmpty) return;
    value = value.copyWith(sources: [...value.sources, ...sources]);
  }

  void setBackend(String label) {
    if (_disposed) return;
    value = value.copyWith(backendLabel: label);
  }

  /// Attaches the structured output of a task. See [AiRunState.result].
  void setResult(Object? result) {
    if (_disposed) return;
    value = value.copyWith(result: result);
  }

  void finish() {
    if (_disposed) return;
    _closeActive(AiStepState.done);
    _stopwatch.stop();
    value = value.copyWith(status: AiRunStatus.done);
  }

  void fail(Object error) {
    if (_disposed) return;
    if (error is LlmCancelled) return cancel();
    _closeActive(AiStepState.failed);
    _stopwatch.stop();
    value = value.copyWith(
      status: AiRunStatus.failed,
      error: error is LlmException ? error.message : error.toString(),
      errorDetail: error is HasRawOutput ? error.raw : null,
    );
  }

  void cancel() {
    cancelToken.cancel();
    if (_disposed) return;
    _closeActive(AiStepState.skipped);
    _stopwatch.stop();
    value = value.copyWith(status: AiRunStatus.cancelled);
  }

  void _closeActive(AiStepState state) {
    if (_disposed) return;
    final now = _stopwatch.elapsed;
    value = value.copyWith(steps: [
      for (final s in value.steps)
        if (s.state == AiStepState.active)
          s.copyWith(state: state, elapsed: now - _stepStartedAt)
        // Anything never reached is skipped, not left spinning forever.
        else if (s.state == AiStepState.pending &&
            state != AiStepState.done)
          s.copyWith(state: AiStepState.skipped)
        else if (s.state == AiStepState.pending)
          s.copyWith(state: AiStepState.skipped)
        else
          s,
    ]);
  }

  void _setState(AiStepKind kind, AiStepState state) {
    if (_disposed) return;
    value = value.copyWith(steps: [
      for (final s in value.steps)
        if (s.kind == kind) s.copyWith(state: state) else s,
    ]);
  }

  @override
  void dispose() {
    if (_disposed) return; // disposing twice is harmless
    _disposed = true;
    cancelToken.cancel();
    _stopwatch.stop();
    super.dispose();
  }
}
