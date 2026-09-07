/// The things Mario's AI features produce and keep: page summaries, saved
/// question-and-answer exchanges, quizzes, and the marks a quiz attempt earned.
///
/// All of it is plain JSON so it can live in a Google Drive file alongside the
/// notes it derives from (see [AiArtifactStore]) — nothing here depends on a
/// database, and a user who inspects the file gets something readable.
///
/// The one idea worth understanding is [NoteSummary.sourceHash]. A cached
/// summary is only useful if it is *known* to describe the current note, so
/// every summary records a hash of the exact text it was built from. Reading a
/// summary re-hashes the note and compares: equal means reuse it for free,
/// different means the note moved on and the summary is stale. That is what
/// makes "read the section once, then answer quickly" safe rather than a
/// source of quietly outdated answers.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../features/ai/ai_progress.dart';
import 'json_coercion.dart';

/// Content hash of the text a derived artifact was built from.
String sourceHashOf(String text) =>
    sha256.convert(utf8.encode(text)).toString().substring(0, 32);

/// Provenance. Attached to everything a model produced, so the origin of a
/// paragraph in someone's notes is never in doubt six months later.
class AiProvenance {
  const AiProvenance({
    required this.backend,
    required this.model,
    required this.createdAt,
  });

  /// The config label — "LAN · qwen3:4b", "Claude".
  final String backend;
  final String model;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'backend': backend,
        'model': model,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AiProvenance.fromJson(Map<String, dynamic> m) => AiProvenance(
        backend: asStringOr(m['backend'], 'unknown'),
        model: asStringOr(m['model']),
        createdAt: asDateTime(m['createdAt'], DateTime.now()),
      );
}

/// A cached summary of one page — the "context" that makes later questions and
/// quiz generation fast.
class NoteSummary {
  const NoteSummary({
    required this.pageId,
    required this.sourceHash,
    required this.summary,
    this.keyPoints = const [],
    required this.provenance,
  });

  final String pageId;

  /// Hash of the note text this was built from. See the library doc.
  final String sourceHash;

  final String summary;
  final List<String> keyPoints;
  final AiProvenance provenance;

  /// True when [currentText] still matches what this summary describes.
  bool matches(String currentText) => sourceHash == sourceHashOf(currentText);

  Map<String, dynamic> toJson() => {
        'pageId': pageId,
        'sourceHash': sourceHash,
        'summary': summary,
        'keyPoints': keyPoints,
        'provenance': provenance.toJson(),
      };

  factory NoteSummary.fromJson(Map<String, dynamic> m) => NoteSummary(
        pageId: asStringOr(m['pageId']),
        sourceHash: asStringOr(m['sourceHash']),
        summary: asStringOr(m['summary']),
        keyPoints: asStringList(m['keyPoints']),
        provenance: AiProvenance.fromJson(asMap(m['provenance']) ?? const {}),
      );
}

/// One saved /ask exchange.
class AskEntry {
  const AskEntry({
    required this.id,
    required this.pageId,
    required this.question,
    required this.answer,
    this.sources = const [],
    this.usedWeb = false,
    this.insertedIntoPage = false,
    required this.provenance,
  });

  final String id;
  final String pageId;
  final String question;
  final String answer;
  final List<AiSource> sources;
  final bool usedWeb;

  /// Whether the user chose to write this exchange into the note itself. Kept
  /// so the panel can show what is already in the page and not offer to insert
  /// the same answer twice.
  final bool insertedIntoPage;

  final AiProvenance provenance;

  AskEntry copyWith({bool? insertedIntoPage}) => AskEntry(
        id: id,
        pageId: pageId,
        question: question,
        answer: answer,
        sources: sources,
        usedWeb: usedWeb,
        insertedIntoPage: insertedIntoPage ?? this.insertedIntoPage,
        provenance: provenance,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageId': pageId,
        'question': question,
        'answer': answer,
        'sources': [for (final s in sources) s.toJson()],
        'usedWeb': usedWeb,
        'insertedIntoPage': insertedIntoPage,
        'provenance': provenance.toJson(),
      };

  factory AskEntry.fromJson(Map<String, dynamic> m) => AskEntry(
        id: asStringOr(m['id']),
        pageId: asStringOr(m['pageId']),
        question: asStringOr(m['question']),
        answer: asStringOr(m['answer']),
        sources: [
          for (final s in asMapList(m['sources'])) AiSource.fromJson(s),
        ],
        usedWeb: asBool(m['usedWeb']),
        insertedIntoPage: asBool(m['insertedIntoPage']),
        provenance: AiProvenance.fromJson(asMap(m['provenance']) ?? const {}),
      );
}

enum QuizItemKind { mcq, essay }

/// One question.
///
/// [sourceBlockIds] is the part that keeps a quiz honest: every item records
/// which blocks of the note it came from, so a disputed answer can be checked
/// against the source instead of argued with the model.
class QuizItem {
  const QuizItem({
    required this.id,
    required this.kind,
    required this.question,
    this.options = const [],
    this.correctIndex,
    this.expectedPoints = const [],
    this.explanation = '',
    this.sourceBlockIds = const [],
    this.marks = 1,
  });

  final String id;
  final QuizItemKind kind;
  final String question;

  /// MCQ only.
  final List<String> options;
  final int? correctIndex;

  /// Essay only — the rubric. Points a good answer should make, which is what
  /// grading is scored against rather than the grader's free opinion.
  final List<String> expectedPoints;

  final String explanation;
  final List<String> sourceBlockIds;
  final int marks;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'question': question,
        if (options.isNotEmpty) 'options': options,
        if (correctIndex != null) 'correctIndex': correctIndex,
        if (expectedPoints.isNotEmpty) 'expectedPoints': expectedPoints,
        if (explanation.isNotEmpty) 'explanation': explanation,
        if (sourceBlockIds.isNotEmpty) 'sourceBlockIds': sourceBlockIds,
        'marks': marks,
      };

  factory QuizItem.fromJson(Map<String, dynamic> m) => QuizItem(
        id: asStringOr(m['id']),
        kind: m['kind'] == 'essay' ? QuizItemKind.essay : QuizItemKind.mcq,
        question: asStringOr(m['question']),
        options: asStringList(m['options']),
        correctIndex: asInt(m['correctIndex']),
        expectedPoints: asStringList(m['expectedPoints']),
        explanation: asStringOr(m['explanation']),
        sourceBlockIds: asStringList(m['sourceBlockIds']),
        marks: asInt(m['marks']) ?? 1,
      );
}

/// What the quiz was generated from.
enum QuizScope { page, section, selection }

class Quiz {
  const Quiz({
    required this.id,
    required this.title,
    required this.scope,
    required this.scopeId,
    required this.items,
    required this.sourceHash,
    required this.provenance,
    this.pageIds = const [],
  });

  final String id;
  final String title;
  final QuizScope scope;

  /// Page id or section id, depending on [scope].
  final String scopeId;

  final List<QuizItem> items;

  /// Hash of the combined source text, so the panel can say "the notes changed
  /// since this quiz was made" instead of silently testing old material.
  final String sourceHash;

  final List<String> pageIds;
  final AiProvenance provenance;

  int get totalMarks => items.fold(0, (sum, i) => sum + i.marks);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'scope': scope.name,
        'scopeId': scopeId,
        'items': [for (final i in items) i.toJson()],
        'sourceHash': sourceHash,
        'pageIds': pageIds,
        'provenance': provenance.toJson(),
      };

  factory Quiz.fromJson(Map<String, dynamic> m) => Quiz(
        id: asStringOr(m['id']),
        title: asStringOr(m['title'], 'Quiz'),
        scope: QuizScope.values.firstWhere(
          (s) => s.name == m['scope'],
          orElse: () => QuizScope.page,
        ),
        scopeId: asStringOr(m['scopeId']),
        items: [
          for (final i in asMapList(m['items'])) QuizItem.fromJson(i),
        ],
        sourceHash: asStringOr(m['sourceHash']),
        pageIds: asStringList(m['pageIds']),
        provenance: AiProvenance.fromJson(asMap(m['provenance']) ?? const {}),
      );
}

/// The mark one answer earned.
///
/// [awarded] is deliberately a double so an essay can score 2.5/4, and
/// [isProvisional] exists because a small model's mark is a draft opinion, not
/// a result — the UI says so, and [userOverride] is what the student's own
/// correction lands in.
class QuizGrade {
  const QuizGrade({
    required this.itemId,
    required this.awarded,
    required this.outOf,
    this.feedback = '',
    this.matchedPoints = const [],
    this.missedPoints = const [],
    this.isProvisional = true,
    this.userOverride,
  });

  final String itemId;
  final double awarded;
  final int outOf;
  final String feedback;

  /// Which rubric points the answer hit and missed — the evidence for the
  /// mark, so the student can check the reasoning rather than trust a number.
  final List<String> matchedPoints;
  final List<String> missedPoints;

  final bool isProvisional;
  final double? userOverride;

  double get effective => userOverride ?? awarded;

  QuizGrade copyWith({double? userOverride}) => QuizGrade(
        itemId: itemId,
        awarded: awarded,
        outOf: outOf,
        feedback: feedback,
        matchedPoints: matchedPoints,
        missedPoints: missedPoints,
        isProvisional: isProvisional,
        userOverride: userOverride ?? this.userOverride,
      );

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'awarded': awarded,
        'outOf': outOf,
        if (feedback.isNotEmpty) 'feedback': feedback,
        if (matchedPoints.isNotEmpty) 'matchedPoints': matchedPoints,
        if (missedPoints.isNotEmpty) 'missedPoints': missedPoints,
        'isProvisional': isProvisional,
        if (userOverride != null) 'userOverride': userOverride,
      };

  factory QuizGrade.fromJson(Map<String, dynamic> m) => QuizGrade(
        itemId: asStringOr(m['itemId']),
        awarded: asDouble(m['awarded']) ?? 0,
        outOf: asInt(m['outOf']) ?? 1,
        feedback: asStringOr(m['feedback']),
        matchedPoints: asStringList(m['matchedPoints']),
        missedPoints: asStringList(m['missedPoints']),
        isProvisional: asBool(m['isProvisional'], fallback: true),
        userOverride: asDouble(m['userOverride']),
      );
}

/// One sitting of a quiz.
class QuizAttempt {
  const QuizAttempt({
    required this.id,
    required this.quizId,
    required this.answers,
    this.grades = const {},
    required this.startedAt,
    this.submittedAt,
  });

  final String id;
  final String quizId;

  /// itemId -> the student's answer. MCQ answers are the option index as a
  /// string; essays are the text.
  final Map<String, String> answers;

  /// itemId -> mark.
  final Map<String, QuizGrade> grades;

  final DateTime startedAt;
  final DateTime? submittedAt;

  bool get isGraded => grades.isNotEmpty;

  double get totalAwarded =>
      grades.values.fold(0.0, (sum, g) => sum + g.effective);

  int get totalOutOf => grades.values.fold(0, (sum, g) => sum + g.outOf);

  QuizAttempt copyWith({
    Map<String, String>? answers,
    Map<String, QuizGrade>? grades,
    DateTime? submittedAt,
  }) =>
      QuizAttempt(
        id: id,
        quizId: quizId,
        answers: answers ?? this.answers,
        grades: grades ?? this.grades,
        startedAt: startedAt,
        submittedAt: submittedAt ?? this.submittedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'quizId': quizId,
        'answers': answers,
        'grades': {
          for (final e in grades.entries) e.key: e.value.toJson(),
        },
        'startedAt': startedAt.toIso8601String(),
        if (submittedAt != null) 'submittedAt': submittedAt!.toIso8601String(),
      };

  factory QuizAttempt.fromJson(Map<String, dynamic> m) => QuizAttempt(
        id: asStringOr(m['id']),
        quizId: asStringOr(m['quizId']),
        answers: {
          for (final e in (asMap(m['answers']) ?? const {}).entries)
            e.key: asStringOr(e.value),
        },
        grades: {
          for (final e in (asMap(m['grades']) ?? const {}).entries)
            if (asMap(e.value) != null)
              e.key: QuizGrade.fromJson(asMap(e.value)!),
        },
        startedAt: asDateTime(m['startedAt'], DateTime.now()),
        submittedAt: asString(m['submittedAt']) == null
            ? null
            : DateTime.tryParse(asString(m['submittedAt'])!),
      );
}

/// One saved Do run — an instruction, and what it did.
///
/// A Do run has no answer to keep; its transcript is the list of steps it
/// applied, and the page holds the result. So that list is what is saved,
/// with the model's own one-line summary of the plan above it.
class DoEntry {
  const DoEntry({
    required this.id,
    required this.pageId,
    required this.instruction,
    required this.summary,
    this.applied = const [],
    this.failed = 0,
    this.dropped = 0,
    required this.provenance,
  });

  final String id;
  final String pageId;
  final String instruction;

  /// The model's one sentence on what the plan did.
  final String summary;

  /// One line per applied step — "Added a 4x3 table", "Renamed the page".
  final List<String> applied;

  final int failed;
  final int dropped;
  final AiProvenance provenance;

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageId': pageId,
        'instruction': instruction,
        'summary': summary,
        'applied': applied,
        'failed': failed,
        'dropped': dropped,
        'provenance': provenance.toJson(),
      };

  factory DoEntry.fromJson(Map<String, dynamic> m) => DoEntry(
        id: asStringOr(m['id']),
        pageId: asStringOr(m['pageId']),
        instruction: asStringOr(m['instruction']),
        summary: asStringOr(m['summary']),
        applied: asStringList(m['applied']),
        failed: asInt(m['failed']) ?? 0,
        dropped: asInt(m['dropped']) ?? 0,
        provenance: AiProvenance.fromJson(asMap(m['provenance']) ?? const {}),
      );
}

/// Everything the AI features have stored for one notebook.
class NotebookAiData {
  const NotebookAiData({
    this.summaries = const {},
    this.asks = const [],
    this.dos = const [],
    this.quizzes = const [],
    this.attempts = const [],
    this.deleted = const [],
  });

  /// pageId -> its cached summary.
  final Map<String, NoteSummary> summaries;

  final List<AskEntry> asks;
  final List<DoEntry> dos;
  final List<Quiz> quizzes;
  final List<QuizAttempt> attempts;

  /// Ids of entries the user deleted, kept so that another device's copy of
  /// this file, which may still hold them, cannot bring them back when the
  /// two are merged. Bounded — see [_remember].
  final List<String> deleted;

  NotebookAiData copyWith({
    Map<String, NoteSummary>? summaries,
    List<AskEntry>? asks,
    List<DoEntry>? dos,
    List<Quiz>? quizzes,
    List<QuizAttempt>? attempts,
    List<String>? deleted,
  }) =>
      NotebookAiData(
        summaries: summaries ?? this.summaries,
        asks: asks ?? this.asks,
        dos: dos ?? this.dos,
        quizzes: quizzes ?? this.quizzes,
        attempts: attempts ?? this.attempts,
        deleted: deleted ?? this.deleted,
      );

  /// Drops everything belonging to [pageId].
  ///
  /// Called when a page is deleted: a quiz about a note that no longer exists
  /// is unanswerable, and a summary of it is a lie.
  NotebookAiData withoutPage(String pageId) {
    final keptQuizzes = [
      for (final q in quizzes)
        if (!(q.scope == QuizScope.page && q.scopeId == pageId) &&
            !(q.pageIds.length == 1 && q.pageIds.first == pageId))
          q,
    ];
    final keptQuizIds = {for (final q in keptQuizzes) q.id};
    final gone = [
      for (final a in asks)
        if (a.pageId == pageId) a.id,
      for (final d in dos)
        if (d.pageId == pageId) d.id,
      for (final q in quizzes)
        if (!keptQuizIds.contains(q.id)) q.id,
      for (final a in attempts)
        if (!keptQuizIds.contains(a.quizId)) a.id,
    ];
    return NotebookAiData(
      summaries: {
        for (final e in summaries.entries)
          if (e.key != pageId) e.key: e.value,
      },
      asks: [
        for (final a in asks)
          if (a.pageId != pageId) a,
      ],
      dos: [
        for (final d in dos)
          if (d.pageId != pageId) d,
      ],
      quizzes: keptQuizzes,
      attempts: [
        for (final a in attempts)
          if (keptQuizIds.contains(a.quizId)) a,
      ],
      deleted: _remember(deleted, gone),
    );
  }

  /// Drops one saved chat — an Ask or a Do entry — and remembers its id.
  NotebookAiData withoutEntry(String id) => copyWith(
        asks: [
          for (final a in asks)
            if (a.id != id) a,
        ],
        dos: [
          for (final d in dos)
            if (d.id != id) d,
        ],
        deleted: _remember(deleted, [id]),
      );

  /// This copy and [other], combined.
  ///
  /// Two devices each hold a copy of the same file, and each may have added
  /// entries and deleted some since they last agreed. Everything either copy
  /// holds is kept, unless either copy deleted it; a page's summary is taken
  /// from whichever copy wrote it later. Creation order is restored by time,
  /// because a merge interleaves two histories.
  ///
  /// Merging by id is what makes a deletion stick across devices. The rule
  /// before this — adopt the remote copy only when it holds strictly more —
  /// kept a deleted entry alive on the device that still had it, and pushed
  /// it back to the one that had removed it on their next save.
  NotebookAiData merge(NotebookAiData other) {
    final gone = {...deleted, ...other.deleted};

    List<T> union<T>(
      List<T> mine,
      List<T> theirs,
      String Function(T) idOf, [
      DateTime Function(T)? timeOf,
    ]) {
      final seen = <String>{};
      final out = <T>[
        for (final e in [...mine, ...theirs])
          if (!gone.contains(idOf(e)) && seen.add(idOf(e))) e,
      ];
      if (timeOf != null) out.sort((a, b) => timeOf(a).compareTo(timeOf(b)));
      return out;
    }

    final summaries = {...other.summaries};
    for (final e in this.summaries.entries) {
      final theirs = summaries[e.key];
      if (theirs == null ||
          !theirs.provenance.createdAt.isAfter(e.value.provenance.createdAt)) {
        summaries[e.key] = e.value;
      }
    }

    return NotebookAiData(
      summaries: summaries,
      asks: union(asks, other.asks, (a) => a.id, (a) => a.provenance.createdAt),
      dos: union(dos, other.dos, (d) => d.id, (d) => d.provenance.createdAt),
      quizzes: union(
          quizzes, other.quizzes, (q) => q.id, (q) => q.provenance.createdAt),
      attempts: union(attempts, other.attempts, (a) => a.id),
      deleted: _remember(deleted, other.deleted),
    );
  }

  /// [existing] plus [more], newest last, capped at the most recent 500.
  ///
  /// Tombstones only need to outlive the copies that might still hold the
  /// entry, and every copy is refreshed on its next load; a few hundred is
  /// years of deletions for a feature nobody deletes from daily.
  static List<String> _remember(List<String> existing, Iterable<String> more) {
    final out = [...existing];
    for (final id in more) {
      if (!out.contains(id)) out.add(id);
    }
    return out.length <= 500 ? out : out.sublist(out.length - 500);
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'summaries': {
          for (final e in summaries.entries) e.key: e.value.toJson(),
        },
        'asks': [for (final a in asks) a.toJson()],
        'dos': [for (final d in dos) d.toJson()],
        'quizzes': [for (final q in quizzes) q.toJson()],
        'attempts': [for (final a in attempts) a.toJson()],
        'deleted': deleted,
      };

  factory NotebookAiData.fromJson(Map<String, dynamic> m) => NotebookAiData(
        summaries: {
          for (final e in (asMap(m['summaries']) ?? const {}).entries)
            if (asMap(e.value) != null)
              e.key: NoteSummary.fromJson(asMap(e.value)!),
        },
        asks: [for (final a in asMapList(m['asks'])) AskEntry.fromJson(a)],
        dos: [for (final d in asMapList(m['dos'])) DoEntry.fromJson(d)],
        quizzes: [for (final q in asMapList(m['quizzes'])) Quiz.fromJson(q)],
        attempts: [
          for (final a in asMapList(m['attempts'])) QuizAttempt.fromJson(a),
        ],
        deleted: asStringList(m['deleted']),
      );
}
