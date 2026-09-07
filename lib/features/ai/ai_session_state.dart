/// Session state for the three AI tabs, held above the widgets.
///
/// The panel switches tabs with a `switch (tab)`, which *destroys* the outgoing
/// tab's widget. Anything the tab kept in its own `State` — a half-streamed
/// answer, a generated quiz, the answers typed into it, a list of proofreading
/// suggestions — went with it, and `dispose()` cancelled the run for good
/// measure. Glancing at the quiz while an answer streamed threw the answer away.
///
/// So none of it lives in the widgets any more. The tabs became views over
/// state that outlives them, which also means closing the panel and reopening
/// it, or switching pages, no longer loses work in progress.
///
/// One consequence worth stating plainly: a run now keeps going when you look
/// away. That is the point — but it means the Stop button is the only thing
/// that cancels, so every tab keeps one visible while a run is live.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/ai/ai_artifacts.dart';
import '../../core/services/ai/llm_types.dart';
import 'agent_actions.dart';
import 'agent_executor.dart';
import 'agent_task.dart';
import 'ai_progress.dart';
import 'ai_tasks.dart';
import 'grammar_check.dart';
import 'quiz_style.dart';

// ---------------------------------------------------------------------- Ask

@immutable
class AskSession {
  const AskSession({
    this.run,
    this.draft = '',
    this.useWeb,
    this.lastQuestion = '',
    this.inserting = false,
    this.insertError,
    this.insertedRunIds = const {},
    this.quoted,
  });

  final AiRun? run;

  /// What is typed in the composer but not yet sent. Kept so a half-written
  /// question survives a glance at the quiz tab.
  final String draft;

  /// Tri-state web preference: null means decide automatically.
  final bool? useWeb;

  final String lastQuestion;
  final bool inserting;
  final String? insertError;

  /// Runs whose answer has already been written into the page, so the button
  /// can say so rather than silently inserting a duplicate.
  final Set<int> insertedRunIds;

  /// The passage the user highlighted, shown above the composer and used as
  /// the focus of the next question. Null when the question is about the whole
  /// page.
  final String? quoted;

  AskSession copyWith({
    AiRun? run,
    bool clearRun = false,
    String? draft,
    bool? useWeb,
    bool clearUseWeb = false,
    String? lastQuestion,
    bool? inserting,
    String? insertError,
    bool clearInsertError = false,
    Set<int>? insertedRunIds,
    String? quoted,
    bool clearQuoted = false,
  }) =>
      AskSession(
        run: clearRun ? null : (run ?? this.run),
        draft: draft ?? this.draft,
        useWeb: clearUseWeb ? null : (useWeb ?? this.useWeb),
        lastQuestion: lastQuestion ?? this.lastQuestion,
        inserting: inserting ?? this.inserting,
        insertError:
            clearInsertError ? null : (insertError ?? this.insertError),
        insertedRunIds: insertedRunIds ?? this.insertedRunIds,
        quoted: clearQuoted ? null : (quoted ?? this.quoted),
      );
}

class AskSessionNotifier extends Notifier<AskSession> {
  @override
  AskSession build() => const AskSession();

  void setDraft(String draft) => state = state.copyWith(draft: draft);

  /// Attaches a highlighted passage as the focus of the next question.
  void quote(String text) => state = state.copyWith(quoted: text);

  /// Drops the attachment — the question goes back to being about the page.
  void clearQuote() => state = state.copyWith(clearQuoted: true);

  void cycleWeb() {
    final next = switch (state.useWeb) {
      null => true,
      true => false,
      false => null,
    };
    state = next == null
        ? state.copyWith(clearUseWeb: true)
        : state.copyWith(useWeb: next);
  }

  /// Starts a run, retiring whatever came before it.
  void startRun(AiRun run, {required String question}) {
    // The previous run is finished with — dispose rather than merely drop it,
    // so its listeners are released. Disposing is safe mid-flight: AiRun
    // ignores writes once disposed.
    state.run?.dispose();
    state = state.copyWith(
      run: run,
      lastQuestion: question,
      clearInsertError: true,
      inserting: false,
      clearQuoted: true,
    );
  }

  void setInserting(bool value) => state = state.copyWith(inserting: value);

  void insertFinished({String? error}) {
    final run = state.run;
    state = state.copyWith(
      inserting: false,
      insertError: error,
      insertedRunIds: error == null && run != null
          ? {...state.insertedRunIds, identityHashCode(run)}
          : state.insertedRunIds,
    );
  }

  bool alreadyInserted(AiRun run) =>
      state.insertedRunIds.contains(identityHashCode(run));

  /// Explicit user action — the only thing that stops a run.
  void stop() => state.run?.cancel();

  void clear() {
    state.run?.dispose();
    state = const AskSession();
  }
}

final askSessionProvider =
    NotifierProvider<AskSessionNotifier, AskSession>(AskSessionNotifier.new);

// --------------------------------------------------------------------- Quiz

enum QuizPhase { setup, generating, answering, marking, results }

@immutable
class QuizSession {
  const QuizSession({
    this.phase = QuizPhase.setup,
    this.scope = QuizScope.page,
    this.mcqCount = QuizTasks.defaultMcqCount,
    this.essayCount = QuizTasks.defaultEssayCount,
    this.difficulty = QuizDifficulty.easy,
    this.useWeb,
    this.run,
    this.items = const [],
    this.title = 'Quiz',
    this.quiz,
    this.answers = const {},
    this.grades = const {},
    this.markingDone = 0,
    this.error,
    this.attemptId,
    this.markingCancel,
    this.notebookId,
  });

  final QuizPhase phase;
  final QuizScope scope;

  /// Tri-state web preference. Null follows the difficulty — hard looks
  /// things up, easy does not — while true and false override it either way.
  ///
  /// The difficulty alone was too coarse: "easy questions, but about the
  /// current syllabus" and "hard questions, strictly from my notes" were both
  /// unreachable.
  final bool? useWeb;

  /// Whether this run should consult the web.
  bool get searchesWeb => useWeb ?? difficulty.usesWeb;

  final int mcqCount;
  final int essayCount;

  /// Easy stays inside the notes; hard reasons past them and looks the subject
  /// up. Kept on the session so it is chosen once rather than every time.
  final QuizDifficulty difficulty;

  final AiRun? run;
  final List<QuizItem> items;
  final String title;

  /// The saved quiz, so an attempt references a real id rather than a title.
  final Quiz? quiz;

  /// itemId -> answer. MCQ answers are the option index as a string.
  final Map<String, String> answers;
  final Map<String, QuizGrade> grades;

  final int markingDone;
  final String? error;

  /// Stable across mark overrides, so correcting a grade updates this sitting
  /// rather than filing a second one.
  final String? attemptId;

  /// Cancels marking. Marking a paper of essays is a minutes-long sequence of
  /// model calls, and without this the only way out was to wait it out.
  final CancelToken? markingCancel;

  /// The notebook this quiz belongs to. Held because the session is app-level:
  /// a quiz can be answered while a different notebook is on screen, and its
  /// marks must be filed against the quiz's own notebook.
  final String? notebookId;

  double get awarded => grades.values.fold(0.0, (sum, g) => sum + g.effective);
  int get outOf => grades.values.fold(0, (sum, g) => sum + g.outOf);
  bool get anyProvisional => grades.values.any((g) => g.isProvisional);

  QuizSession copyWith({
    QuizPhase? phase,
    QuizScope? scope,
    int? mcqCount,
    int? essayCount,
    QuizDifficulty? difficulty,
    bool? useWeb,
    bool clearUseWeb = false,
    AiRun? run,
    bool clearRun = false,
    List<QuizItem>? items,
    String? title,
    Quiz? quiz,
    Map<String, String>? answers,
    Map<String, QuizGrade>? grades,
    int? markingDone,
    String? error,
    bool clearError = false,
    String? attemptId,
    bool clearAttemptId = false,
    CancelToken? markingCancel,
    bool clearMarkingCancel = false,
    String? notebookId,
  }) =>
      QuizSession(
        phase: phase ?? this.phase,
        scope: scope ?? this.scope,
        mcqCount: mcqCount ?? this.mcqCount,
        essayCount: essayCount ?? this.essayCount,
        difficulty: difficulty ?? this.difficulty,
        useWeb: clearUseWeb ? null : (useWeb ?? this.useWeb),
        run: clearRun ? null : (run ?? this.run),
        items: items ?? this.items,
        title: title ?? this.title,
        quiz: quiz ?? this.quiz,
        answers: answers ?? this.answers,
        grades: grades ?? this.grades,
        markingDone: markingDone ?? this.markingDone,
        error: clearError ? null : (error ?? this.error),
        attemptId: clearAttemptId ? null : (attemptId ?? this.attemptId),
        markingCancel:
            clearMarkingCancel ? null : (markingCancel ?? this.markingCancel),
        notebookId: notebookId ?? this.notebookId,
      );
}

class QuizSessionNotifier extends Notifier<QuizSession> {
  @override
  QuizSession build() => const QuizSession();

  void setScope(QuizScope scope) => state = state.copyWith(scope: scope);
  void setMcqCount(int n) => state = state.copyWith(mcqCount: n);
  void setEssayCount(int n) => state = state.copyWith(essayCount: n);
  void setDifficulty(QuizDifficulty d) => state = state.copyWith(difficulty: d);

  /// Sets the preference outright. The quiz setup shows the three states as a
  /// radio group, so it picks rather than cycles.
  void setWeb(bool? value) => state = value == null
      ? state.copyWith(clearUseWeb: true)
      : state.copyWith(useWeb: value);

  void startGenerating(AiRun run) {
    state.run?.dispose();
    state = state.copyWith(
      run: run,
      phase: QuizPhase.generating,
      items: const [],
      answers: const {},
      grades: const {},
      clearError: true,
      clearAttemptId: true,
    );
  }

  void generated(List<QuizItem> items, String title) => state = state.copyWith(
        items: items,
        title: title,
        phase: QuizPhase.answering,
      );

  void generationFailed(String? error) =>
      state = state.copyWith(phase: QuizPhase.setup, error: error);

  void setQuiz(Quiz quiz, {String? notebookId}) =>
      state = state.copyWith(quiz: quiz, notebookId: notebookId);

  void answer(String itemId, String value) =>
      state = state.copyWith(answers: {...state.answers, itemId: value});

  void startMarking(String attemptId, CancelToken cancel) =>
      state = state.copyWith(
        phase: QuizPhase.marking,
        markingDone: 0,
        grades: const {},
        attemptId: attemptId,
        markingCancel: cancel,
        clearError: true,
      );

  /// Stops marking part-way. Whatever has been marked so far is kept and
  /// shown, because a half-marked paper is still worth reading.
  void stopMarking() {
    state.markingCancel?.cancel();
    state = state.copyWith(phase: QuizPhase.results);
  }

  void graded(String itemId, QuizGrade grade) => state = state.copyWith(
        grades: {...state.grades, itemId: grade},
        markingDone: state.markingDone + 1,
      );

  void markingFinished() => state =
      state.copyWith(phase: QuizPhase.results, clearMarkingCancel: true);

  /// Records the student's own correction of a model-assigned mark.
  ///
  /// Named `overrideMark` rather than `override`, which the analyser reads as
  /// the annotation on whatever declaration follows it.
  void overrideMark(String itemId, double value) {
    final g = state.grades[itemId];
    if (g == null) return;
    state = state.copyWith(
      grades: {...state.grades, itemId: g.copyWith(userOverride: value)},
    );
  }

  /// Loads a saved quiz back in for another attempt.
  void retake(Quiz quiz) {
    state.run?.dispose();
    state = QuizSession(
      scope: state.scope,
      mcqCount: state.mcqCount,
      essayCount: state.essayCount,
      difficulty: state.difficulty,
      phase: QuizPhase.answering,
      items: quiz.items,
      title: quiz.title,
      quiz: quiz,
    );
  }

  /// Shows a finished attempt without re-marking it.
  void review(Quiz quiz, QuizAttempt attempt) {
    state.run?.dispose();
    state = QuizSession(
      scope: state.scope,
      phase: QuizPhase.results,
      items: quiz.items,
      title: quiz.title,
      quiz: quiz,
      answers: attempt.answers,
      grades: attempt.grades,
      attemptId: attempt.id,
    );
  }

  void stop() => state.run?.cancel();

  void reset() {
    state.run?.dispose();
    state = QuizSession(
      scope: state.scope,
      mcqCount: state.mcqCount,
      essayCount: state.essayCount,
      difficulty: state.difficulty,
    );
  }
}

final quizSessionProvider =
    NotifierProvider<QuizSessionNotifier, QuizSession>(QuizSessionNotifier.new);

// ------------------------------------------------------------------ Writing

enum SuggestionOutcome { applied, ignored, expired }

@immutable
class WritingSession {
  const WritingSession({
    this.run,
    this.suggestions = const [],
    this.outcomes = const {},
    this.hasRun = false,
  });

  final AiRun? run;
  final List<GrammarSuggestion> suggestions;

  /// Keyed by index into [suggestions] rather than by the suggestion itself:
  /// GrammarSuggestion has no value equality, and identity keys would break
  /// the moment the list round-tripped through anything.
  final Map<int, SuggestionOutcome> outcomes;

  /// Whether a check has been run at all, which is what separates the intro
  /// screen from an "all clear" result.
  final bool hasRun;

  int get pending => suggestions.length - outcomes.length;

  WritingSession copyWith({
    AiRun? run,
    bool clearRun = false,
    List<GrammarSuggestion>? suggestions,
    Map<int, SuggestionOutcome>? outcomes,
    bool? hasRun,
  }) =>
      WritingSession(
        run: clearRun ? null : (run ?? this.run),
        suggestions: suggestions ?? this.suggestions,
        outcomes: outcomes ?? this.outcomes,
        hasRun: hasRun ?? this.hasRun,
      );
}

class WritingSessionNotifier extends Notifier<WritingSession> {
  @override
  WritingSession build() => const WritingSession();

  void startCheck(AiRun run) {
    state.run?.dispose();
    state = state.copyWith(
      run: run,
      suggestions: const [],
      outcomes: const {},
      hasRun: true,
    );
  }

  void checked(List<GrammarSuggestion> suggestions) =>
      state = state.copyWith(suggestions: suggestions);

  void resolve(int index, SuggestionOutcome outcome) =>
      state = state.copyWith(outcomes: {...state.outcomes, index: outcome});

  void stop() => state.run?.cancel();

  void clear() {
    state.run?.dispose();
    state = const WritingSession();
  }
}

final writingSessionProvider =
    NotifierProvider<WritingSessionNotifier, WritingSession>(
        WritingSessionNotifier.new);

// -------------------------------------------------------------------- Agent

/// A validated agent plan waiting for the user's explicit decision.
class AgentPlanReview {
  AgentPlanReview(this.plan);

  final AgentPlan plan;
  final Completer<bool> _decision = Completer<bool>();

  Future<bool> get decision => _decision.future;

  void resolve(bool approved) {
    if (!_decision.isCompleted) _decision.complete(approved);
  }
}

@immutable
class AgentSession {
  const AgentSession({
    this.run,
    this.draft = '',
    this.instruction = '',
    this.useWeb,
    this.snapshot,
    this.review,
    this.artifactDraft,
    this.artifactApplied = false,
    this.undone = false,
    this.isUndoing = false,
    this.exchanges = const [],
    this.reviewBeforeWriting = false,
  });

  final AiRun? run;
  final String draft;
  final String instruction;

  /// Earlier instructions and what came of them — the conversation the next
  /// instruction continues, which is what makes a reply to the agent's
  /// question, or "now do the same for the other section", land in context.
  final List<AgentExchange> exchanges;

  /// Pause each step that writes for the user's approval, as every run used
  /// to. Off by default: the agent works through, the step list shows what
  /// it did, and Undo all puts the page back.
  final bool reviewBeforeWriting;

  /// Tri-state web preference, as on Ask: true forces a look-up before
  /// planning, false forbids one, null decides from the instruction.
  ///
  /// "Add a section on current EU AI rules" cannot be written from the page —
  /// there is nothing on the page about them. Editing an existing page and
  /// needing outside facts are not exclusive.
  final bool? useWeb;

  /// The page as it was before the run touched it. Held for exactly as long as
  /// the result is on screen — it is what makes "Undo all" one press rather
  /// than N presses of Ctrl-Z, which is unusable when the user cannot know
  /// how many edits a plan made.
  final AgentSnapshot? snapshot;

  /// A plan that has been generated and validated but has not touched the
  /// page. It survives tab switches, like the run that is waiting on it.
  final AgentPlanReview? review;

  /// HTML sent from Ask for a Claude-style live preview in the Do tab.
  final String? artifactDraft;
  final bool artifactApplied;

  final bool undone;
  final bool isUndoing;

  AgentSession copyWith({
    AiRun? run,
    bool clearRun = false,
    String? draft,
    String? instruction,
    bool? useWeb,
    bool clearUseWeb = false,
    AgentSnapshot? snapshot,
    bool clearSnapshot = false,
    AgentPlanReview? review,
    bool clearReview = false,
    String? artifactDraft,
    bool clearArtifactDraft = false,
    bool? artifactApplied,
    bool? undone,
    bool? isUndoing,
    List<AgentExchange>? exchanges,
    bool? reviewBeforeWriting,
  }) =>
      AgentSession(
        run: clearRun ? null : (run ?? this.run),
        draft: draft ?? this.draft,
        instruction: instruction ?? this.instruction,
        useWeb: clearUseWeb ? null : (useWeb ?? this.useWeb),
        snapshot: clearSnapshot ? null : (snapshot ?? this.snapshot),
        review: clearReview ? null : (review ?? this.review),
        artifactDraft:
            clearArtifactDraft ? null : (artifactDraft ?? this.artifactDraft),
        artifactApplied: artifactApplied ?? this.artifactApplied,
        undone: undone ?? this.undone,
        isUndoing: isUndoing ?? this.isUndoing,
        exchanges: exchanges ?? this.exchanges,
        reviewBeforeWriting: reviewBeforeWriting ?? this.reviewBeforeWriting,
      );
}

class AgentSessionNotifier extends Notifier<AgentSession> {
  @override
  AgentSession build() => const AgentSession();

  void setDraft(String draft) => state = state.copyWith(draft: draft);

  /// auto → on → off → auto, the same cycle the Ask tab's chip runs.
  void cycleWeb() {
    final next = switch (state.useWeb) {
      null => true,
      true => false,
      false => null,
    };
    state = next == null
        ? state.copyWith(clearUseWeb: true)
        : state.copyWith(useWeb: next);
  }

  void start(AiRun run, {required String instruction}) {
    state.review?.resolve(false);
    state.run?.dispose();
    state = AgentSession(
      run: run,
      draft: state.draft,
      instruction: instruction,
      // Survives the run, so the chip does not snap back to auto the moment
      // the plan starts.
      useWeb: state.useWeb,
      exchanges: state.exchanges,
      reviewBeforeWriting: state.reviewBeforeWriting,
    );
  }

  /// Keeps what a finished run did, for the next instruction's context.
  /// Bounded: the last dozen is a conversation, not an archive.
  void remember(AgentExchange exchange) {
    final all = [...state.exchanges, exchange];
    state = state.copyWith(
      exchanges: all.length <= 12 ? all : all.sublist(all.length - 12),
    );
  }

  void setReviewBeforeWriting(bool value) =>
      state = state.copyWith(reviewBeforeWriting: value);

  /// Pauses an already-validated run until the user accepts its preview.
  Future<bool> reviewPlan(AgentPlan plan) {
    final review = AgentPlanReview(plan);
    state = state.copyWith(
      review: review,
      clearArtifactDraft: true,
      artifactApplied: false,
    );
    return review.decision;
  }

  /// Accepts the preview. The snapshot is captured at click time, immediately
  /// before the first action rather than while the user is still reviewing.
  void approve(AgentSnapshot snapshot) {
    final review = state.review;
    if (review == null) return;
    state = state.copyWith(snapshot: snapshot, clearReview: true);
    review.resolve(true);
  }

  void discardReview() {
    final review = state.review;
    if (review == null) return;
    state = state.copyWith(clearReview: true);
    review.resolve(false);
  }

  /// Shows HTML from a normal Ask answer in the Do tab without saving it to
  /// the page. Applying it is a separate, explicit action.
  void previewArtifact(String html) {
    state.review?.resolve(false);
    state.run?.dispose();
    state = AgentSession(
      draft: state.draft,
      useWeb: state.useWeb,
      artifactDraft: html,
      exchanges: state.exchanges,
      reviewBeforeWriting: state.reviewBeforeWriting,
    );
  }

  void artifactApplied(AgentSnapshot snapshot) => state = state.copyWith(
        snapshot: snapshot,
        artifactApplied: true,
        undone: false,
      );

  void discardArtifact() => state = state.copyWith(
        clearArtifactDraft: true,
        artifactApplied: false,
        clearSnapshot: true,
      );

  void undoing() => state = state.copyWith(isUndoing: true);

  void undone(bool ok) => state = state.copyWith(isUndoing: false, undone: ok);

  void stop() {
    state.review?.resolve(false);
    state.run?.cancel();
    state = state.copyWith(clearReview: true);
  }

  void clear() {
    state.review?.resolve(false);
    state.run?.dispose();
    state = const AgentSession();
  }
}

final agentSessionProvider =
    NotifierProvider<AgentSessionNotifier, AgentSession>(
        AgentSessionNotifier.new);
