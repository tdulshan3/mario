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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/ai/ai_artifacts.dart';
import '../../core/services/ai/llm_types.dart';
import 'ai_progress.dart';
import 'ai_tasks.dart';
import 'grammar_check.dart';

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
  final int mcqCount;
  final int essayCount;

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

  double get awarded =>
      grades.values.fold(0.0, (sum, g) => sum + g.effective);
  int get outOf => grades.values.fold(0, (sum, g) => sum + g.outOf);
  bool get anyProvisional => grades.values.any((g) => g.isProvisional);

  QuizSession copyWith({
    QuizPhase? phase,
    QuizScope? scope,
    int? mcqCount,
    int? essayCount,
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
        run: clearRun ? null : (run ?? this.run),
        items: items ?? this.items,
        title: title ?? this.title,
        quiz: quiz ?? this.quiz,
        answers: answers ?? this.answers,
        grades: grades ?? this.grades,
        markingDone: markingDone ?? this.markingDone,
        error: clearError ? null : (error ?? this.error),
        attemptId: clearAttemptId ? null : (attemptId ?? this.attemptId),
        markingCancel: clearMarkingCancel
            ? null
            : (markingCancel ?? this.markingCancel),
        notebookId: notebookId ?? this.notebookId,
      );
}

class QuizSessionNotifier extends Notifier<QuizSession> {
  @override
  QuizSession build() => const QuizSession();

  void setScope(QuizScope scope) => state = state.copyWith(scope: scope);
  void setMcqCount(int n) => state = state.copyWith(mcqCount: n);
  void setEssayCount(int n) => state = state.copyWith(essayCount: n);

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
