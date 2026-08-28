/// How to write a quiz question, and what "hard" actually means.
///
/// Sits alongside `note_style.dart` and exists for the same reason: without
/// explicit rules a model writes recognisably bad exam items — stems that give
/// the answer away by grammar, three sensible options and one joke, "all of the
/// above", and questions that test whether you read the page rather than
/// whether you understood it.
///
/// The two difficulties are not "shorter" and "longer". They test different
/// things:
///
///  * **Easy** stays inside the notes. Recall and comprehension: definitions,
///    mechanisms, relationships stated on the page. A student who has read and
///    understood it should get most of these. This is the mode for checking you
///    have actually learnt the material.
///  * **Hard** goes past them. Application, analysis, evaluation: apply the
///    idea to a case the notes never mention, find the flaw, choose between two
///    defensible readings, work out what follows. These cannot be answered by
///    recognising a sentence, which is the point — and it is why hard mode also
///    consults the web, so the scenarios come from the real subject rather than
///    from a model's imagination.
library;

enum QuizDifficulty { easy, hard }

extension QuizDifficultyLabel on QuizDifficulty {
  String get label => switch (this) {
        QuizDifficulty.easy => 'Easy',
        QuizDifficulty.hard => 'Hard',
      };

  String get blurb => switch (this) {
        QuizDifficulty.easy =>
          'Recall and understanding, answerable from the notes.',
        QuizDifficulty.hard =>
          'Applying and analysing, beyond the notes. Looks things up.',
      };

  /// Whether this difficulty consults the web before writing questions.
  bool get usesWeb => this == QuizDifficulty.hard;
}

/// Item-writing rules that hold at any difficulty.
///
/// Each one corresponds to a flaw that shows up unprompted. Published studies
/// of machine-written items count one to two such flaws per question, and every
/// flaw below is one a student can exploit to answer without knowing anything.
const String quizStyleCore = '''
WRITING THE QUESTIONS

Stems
- A complete question, ending in a question mark. Not a sentence with a gap in it.
- Ask one thing. A stem with an "and" in it is usually two questions.
- No double negatives, and no "which is NOT" unless the NOT is capitalised.
- Do not give the answer away with grammar: if the stem ends in "an", every
  option must start with a vowel.

Options
- Exactly four, all plausible to someone who half-learned the material.
- Wrong options are real misconceptions — the mistake a student actually makes,
  the neighbouring term, the right idea applied to the wrong case. Never filler
  and never a joke.
- Parallel in length, structure and specificity. The longest, most qualified
  option must not be the answer, because that is a pattern students learn to
  spot instead of learning the subject.
- Never "all of the above", "none of the above", or "both A and B".
- Exactly one defensibly correct answer. If two could be argued, rewrite the
  question rather than picking a favourite.
- Vary which position is correct across the paper.

Explanations
- Say why the right answer is right, not merely restate it.
- Where a wrong option is a common misconception, name it.

Essays
- The rubric is the specific points a full-mark answer must make, drawn from the
  material — not "shows understanding", which cannot be marked.
- Three to six points. Each independently checkable.
''';

/// Extra rules for easy mode.
const String quizStyleEasy = '''
DIFFICULTY: EASY
- Everything is answerable from the notes alone. Do not require outside
  knowledge, and do not test anything the notes only mention in passing.
- Test recall and comprehension: definitions, mechanisms, causes, the
  relationships the notes state.
- Use the notes' own terminology. A student should recognise the vocabulary.
- Essay prompts ask the student to explain or describe something the notes
  cover.
''';

/// Extra rules for hard mode.
///
/// The instruction to stay *grounded* matters as much as the instruction to go
/// beyond: a hard question about material the notes never touched is not hard,
/// it is a different exam.
const String quizStyleHard = '''
DIFFICULTY: HARD
- Go beyond recall. Every question should need a step of reasoning that is not
  written on the page.
- Use these shapes:
  * apply the idea to a specific case the notes never mention;
  * given a scenario, work out what follows, or what went wrong;
  * compare two things the notes treat separately;
  * identify the flaw in a plausible-sounding statement;
  * choose between two defensible readings and say which the evidence supports.
- Stay anchored to the notes' subject. The reasoning may go beyond them; the
  topic may not. A question about material the notes never touch is not a hard
  question about these notes, it is a different exam.
- Where web results are supplied, use them for real examples, current figures
  and applications the notes lack — not to change the subject.
- Wrong options should be answers a good student would reach by reasoning
  *almost* correctly, not by failing to remember.
- Essay prompts ask the student to apply, evaluate, or argue — "why would X
  fail if Y", not "describe X".
''';

/// The style block for one difficulty, ready to append to a system prompt.
String quizStyleFor(QuizDifficulty difficulty) => switch (difficulty) {
      QuizDifficulty.easy => '$quizStyleCore\n$quizStyleEasy',
      QuizDifficulty.hard => '$quizStyleCore\n$quizStyleHard',
    };

/// A search query for hard mode, built from what the notes are about.
///
/// Headings first, then the title: a heading names the specific topic where a
/// page title is often just "Lecture 4". Capped short, because a search engine
/// given a paragraph returns worse results than one given a subject.
String searchTopicFor(String title, List<String> headings) {
  final parts = <String>[
    for (final h in headings.take(3))
      h.replaceAll(RegExp(r'^#+\s*'), '').trim(),
  ]..removeWhere((p) => p.isEmpty);

  final cleanTitle = title.trim();
  if (cleanTitle.isNotEmpty &&
      !cleanTitle.toLowerCase().startsWith('untitled')) {
    parts.insert(0, cleanTitle);
  }
  if (parts.isEmpty) return '';

  final query = parts.join(' ');
  return query.length <= 120 ? query : query.substring(0, 120);
}
