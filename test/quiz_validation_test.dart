/// Throwing away the questions a small model gets wrong.
///
/// Every rejection tested here is a real failure mode: a `correctIndex` that
/// counted from one, two options that say the same thing, an essay with no
/// rubric to mark against. Each is decidable in plain code, and a dropped
/// question is much better than one with no right answer — so the suite also
/// pins the other direction, that a good question is never discarded.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/ai_artifacts.dart';
import 'package:mario/features/ai/ai_tasks.dart';

void main() {
  // Parameters are deliberately Object? — the point of these tests is what
  // happens when a model puts the wrong *type* in a field.
  Map<String, dynamic> mcq({
    Object? question = 'What is the capital of France?',
    Object? options = const ['Paris', 'Lyon', 'Marseille', 'Nice'],
    Object? correctIndex = 0,
  }) =>
      {
        'kind': 'mcq',
        'question': question,
        'options': options,
        if (correctIndex != null) 'correctIndex': correctIndex,
      };

  group('validateQuizItems — multiple choice', () {
    test('keeps a well-formed question', () {
      final items = validateQuizItems([mcq()]);
      expect(items, hasLength(1));
      expect(items.first.kind, QuizItemKind.mcq);
      expect(items.first.correctIndex, 0);
      expect(items.first.options, hasLength(4));
    });

    test('drops an out-of-range correctIndex', () {
      // The classic small-model error: 1-based counting into a 0-based list.
      expect(validateQuizItems([mcq(correctIndex: 4)]), isEmpty);
      expect(validateQuizItems([mcq(correctIndex: -1)]), isEmpty);
    });

    test('drops a question with no correctIndex at all', () {
      expect(validateQuizItems([mcq(correctIndex: null)]), isEmpty);
    });

    test('drops duplicate options, which would make two answers correct', () {
      expect(
        validateQuizItems([
          mcq(options: const ['Paris', 'Paris', 'Lyon', 'Nice']),
        ]),
        isEmpty,
      );
    });

    test('treats options differing only in case as duplicates', () {
      expect(
        validateQuizItems([
          mcq(options: const ['Paris', 'paris', 'Lyon', 'Nice']),
        ]),
        isEmpty,
      );
    });

    test('drops a question without exactly four options', () {
      expect(
        validateQuizItems([mcq(options: const ['Paris', 'Lyon', 'Nice'])]),
        isEmpty,
      );
      expect(
        validateQuizItems([
          mcq(options: const ['a', 'b', 'c', 'd', 'e']),
        ]),
        isEmpty,
      );
    });

    test('drops a blank option', () {
      expect(
        validateQuizItems([mcq(options: const ['Paris', '', 'Lyon', 'Nice'])]),
        isEmpty,
      );
    });

    test('drops a blank question', () {
      expect(validateQuizItems([mcq(question: '   ')]), isEmpty);
    });

    test('keeps the good questions and drops only the bad ones', () {
      final items = validateQuizItems([
        mcq(),
        mcq(correctIndex: 9),
        mcq(question: 'What is 2+2?', options: const ['3', '4', '5', '6'],
            correctIndex: 1),
      ]);
      expect(items, hasLength(2));
      expect(items.map((i) => i.question),
          ['What is the capital of France?', 'What is 2+2?']);
    });

    test('gives every kept item a distinct id', () {
      final items = validateQuizItems([
        mcq(),
        mcq(question: 'What is 2+2?', options: const ['3', '4', '5', '6']),
      ]);
      expect(items.map((i) => i.id).toSet(), hasLength(2));
    });
  });

  group('validateQuizItems survives wrong-typed model output', () {
    // This is the crash the user hit: "type 'List<dynamic>' is not a subtype of
    // type 'num?' in type cast", thrown out of quiz generation and killing the
    // whole batch. A malformed field must cost one question, never the run.

    test('correctIndex as a single-element list is understood', () {
      // `[0]` unambiguously means `0`.
      final items = validateQuizItems([mcq(correctIndex: [0])]);
      expect(items, hasLength(1));
      expect(items.single.correctIndex, 0);
    });

    test('correctIndex as a multi-element list drops the question', () {
      // Two correct answers is a broken item, not an item with the first one.
      expect(validateQuizItems([mcq(correctIndex: [0, 2])]), isEmpty);
    });

    test('correctIndex as a quoted number is understood', () {
      expect(validateQuizItems([mcq(correctIndex: '1')]).single.correctIndex, 1);
    });

    test('correctIndex as an object drops the question, not the batch', () {
      expect(
        validateQuizItems([
          mcq(correctIndex: {'index': 0})
        ]),
        isEmpty,
      );
    });

    test('a question given as a number is still usable text', () {
      final items = validateQuizItems([mcq(question: 2024)]);
      expect(items.single.question, '2024');
    });

    test('options given as numbers are stringified', () {
      final items =
          validateQuizItems([mcq(options: [1, 2, 3, 4], correctIndex: 0)]);
      expect(items.single.options, ['1', '2', '3', '4']);
    });

    test('options as a bare string drops the question', () {
      // Not four options, so not a usable MCQ.
      expect(validateQuizItems([mcq(options: 'Paris')]), isEmpty);
    });

    // Non-object entries never reach here — asMapList filters them upstream,
    // which json_field_coercion_test covers.
    test('a bad question never takes the good ones down with it', () {
      final items = validateQuizItems([
        mcq(correctIndex: [0, 1]),
        mcq(question: 'What is 2+2?', options: const ['3', '4', '5', '6'],
            correctIndex: 1),
        {'kind': 'mcq'},
      ]);
      expect(items, hasLength(1));
      expect(items.single.question, 'What is 2+2?');
    });

    test('essay rubric given as a bare string is accepted as one point', () {
      final items = validateQuizItems([
        {
          'kind': 'essay',
          'question': 'Explain.',
          'expectedPoints': 'light is absorbed',
        }
      ]);
      expect(items.single.expectedPoints, ['light is absorbed']);
    });

    test('marks as a list falls back to the rubric length', () {
      final items = validateQuizItems([
        {
          'kind': 'essay',
          'question': 'Explain.',
          'expectedPoints': ['a', 'b'],
          'marks': [5],
        }
      ]);
      expect(items.single.marks, 2);
    });

    test('an entirely empty reply yields no questions and no crash', () {
      expect(validateQuizItems([]), isEmpty);
      expect(validateQuizItems([{}]), isEmpty);
    });
  });

  group('validateQuizItems — essay', () {
    test('keeps an essay that has a rubric', () {
      final items = validateQuizItems([
        {
          'kind': 'essay',
          'question': 'Explain photosynthesis.',
          'expectedPoints': ['light is absorbed', 'CO2 is fixed', 'sugar out'],
        }
      ]);
      expect(items, hasLength(1));
      expect(items.first.kind, QuizItemKind.essay);
      expect(items.first.expectedPoints, hasLength(3));
      // One mark per rubric point, so partial credit means something.
      expect(items.first.marks, 3);
    });

    test('drops an essay with no rubric, which cannot be marked honestly', () {
      expect(
        validateQuizItems([
          {'kind': 'essay', 'question': 'Discuss.'}
        ]),
        isEmpty,
      );
      expect(
        validateQuizItems([
          {'kind': 'essay', 'question': 'Discuss.', 'expectedPoints': <String>[]}
        ]),
        isEmpty,
      );
    });

    test('ignores blank rubric points', () {
      final items = validateQuizItems([
        {
          'kind': 'essay',
          'question': 'Explain.',
          'expectedPoints': ['a real point', '', '   '],
        }
      ]);
      expect(items.first.expectedPoints, ['a real point']);
      expect(items.first.marks, 1);
    });

    test('caps marks so one rambling rubric cannot dominate the total', () {
      final items = validateQuizItems([
        {
          'kind': 'essay',
          'question': 'Explain everything.',
          'expectedPoints': [for (var i = 0; i < 30; i++) 'point $i'],
        }
      ]);
      expect(items.first.marks, 10);
    });
  });

  group('questionKey catches near-duplicate questions across batches', () {
    // A long paper is generated in several rounds, so the model never sees its
    // own earlier output in full and near-repeats are the normal failure.

    test('ignores case, punctuation and spacing', () {
      expect(questionKey('What is the capital of France?'),
          questionKey('what is the Capital of  France'));
    });

    test('keeps genuinely different questions apart', () {
      expect(questionKey('What is the capital of France?'),
          isNot(questionKey('What is the capital of Spain?')));
    });

    test('does not collapse a question into its own negation', () {
      expect(questionKey('Which of these is a mammal?'),
          isNot(questionKey('Which of these is not a mammal?')));
    });

    test('a blank question keys to empty rather than throwing', () {
      expect(questionKey('   '), '');
      expect(questionKey('?!'), '');
    });

    test('keeps non-Latin questions distinct', () {
      // The ASCII-only version deleted every Sinhala codepoint, so every
      // question keyed to '' , the second always looked like a repeat, and a
      // whole quiz came back with one item.
      const a = 'ජීව විද්‍යාව යනු කුමක්ද?';
      const b = 'සෛලයේ කාර්යය කුමක්ද?';
      expect(questionKey(a), isNotEmpty);
      expect(questionKey(a), isNot(questionKey(b)));
    });

    test('keeps Tamil, Devanagari and CJK questions distinct', () {
      expect(questionKey('உயிரியல் என்றால் என்ன?'),
          isNot(questionKey('செல் என்றால் என்ன?')));
      expect(questionKey('जीव विज्ञान क्या है?'),
          isNot(questionKey('कोशिका क्या है?')));
      expect(questionKey('細胞とは何ですか'), isNot(questionKey('生物学とは何ですか')));
    });

    test('still normalises punctuation within a non-Latin question', () {
      expect(questionKey('細胞とは何ですか？'), questionKey('細胞とは何ですか'));
    });
  });

  group('looksLikeANonAnswer spots a stall worth retrying', () {
    // From a real failure: asked to "explain the note", the model replied that
    // the notes "do not contain the answer to the question" — it went looking
    // for an answer inside the material instead of explaining it.

    test('catches the disclaimer-only reply', () {
      expect(
        looksLikeANonAnswer(
            'The notes provided do not contain the answer to the question.'),
        isTrue,
      );
      expect(looksLikeANonAnswer('I cannot answer that from these notes.'),
          isTrue);
      expect(looksLikeANonAnswer('There is no specific question in the notes.'),
          isTrue);
    });

    test('an empty reply counts as a stall', () {
      expect(looksLikeANonAnswer(''), isTrue);
      expect(looksLikeANonAnswer('   \n '), isTrue);
    });

    test('leaves a real explanation alone', () {
      expect(
        looksLikeANonAnswer(
            'The evaluation matrix scores each opportunity on four criteria. '
            'Market size carries the most weight, then feasibility.'),
        isFalse,
      );
    });

    test('does not discard a long answer that mentions a gap in passing', () {
      // The dangerous false positive: re-running this would throw away a good
      // answer because it was honest about the notes' limits.
      final good = 'The matrix scores opportunities on four axes. '
          '${'Each axis is weighted and summed to a total. ' * 12}'
          'The notes do not contain the weighting used, so I have assumed '
          'equal weights.';
      expect(good.length, greaterThan(400));
      expect(looksLikeANonAnswer(good), isFalse);
    });
  });

  group('gradeMcq marks in plain code', () {
    final item = QuizItem(
      id: 'q1',
      kind: QuizItemKind.mcq,
      question: 'Capital of France?',
      options: const ['Paris', 'Lyon', 'Marseille', 'Nice'],
      correctIndex: 0,
      explanation: 'Paris has been the capital since 987.',
    );

    test('awards full marks for the right option', () {
      final g = gradeMcq(item, '0');
      expect(g.awarded, 1);
      expect(g.outOf, 1);
      expect(g.isProvisional, isFalse); // comparing two ints is not an opinion
    });

    test('awards nothing for a wrong option and names the right one', () {
      final g = gradeMcq(item, '2');
      expect(g.awarded, 0);
      expect(g.feedback, contains('Paris'));
      expect(g.isProvisional, isFalse);
    });

    test('treats a missing or unparseable answer as wrong, not as a crash', () {
      expect(gradeMcq(item, '').awarded, 0);
      expect(gradeMcq(item, 'Paris').awarded, 0);
    });
  });

  group('parseGrade keeps a model mark inside the possible range', () {
    test('reads a well-formed grade', () {
      final g = parseGrade(
        '{"awarded": 2, "feedback": "good", "matchedPoints": ["a"], '
        '"missedPoints": ["b"]}',
        itemId: 'q1',
        outOf: 3,
      );
      expect(g.awarded, 2);
      expect(g.matchedPoints, ['a']);
      expect(g.missedPoints, ['b']);
      expect(g.isProvisional, isTrue); // an essay mark is always a draft
    });

    test('clamps a mark above the maximum', () {
      // Models overshoot; a student must never see 7/4.
      expect(parseGrade('{"awarded": 7}', itemId: 'q', outOf: 4).awarded, 4);
    });

    test('clamps a negative mark', () {
      expect(parseGrade('{"awarded": -2}', itemId: 'q', outOf: 4).awarded, 0);
    });

    test('reads a mark written as "3/4"', () {
      expect(parseGrade('{"awarded": "3/4"}', itemId: 'q', outOf: 4).awarded, 3);
    });

    test('accepts score and marks as aliases for awarded', () {
      expect(parseGrade('{"score": 2}', itemId: 'q', outOf: 4).awarded, 2);
      expect(parseGrade('{"marks": 1}', itemId: 'q', outOf: 4).awarded, 1);
    });

    test('unparseable output scores zero and says so, rather than guessing', () {
      final g = parseGrade('I think this is pretty good!', itemId: 'q', outOf: 4);
      expect(g.awarded, 0);
      expect(g.feedback, contains('did not return'));
    });

    test('a user override wins over the model mark', () {
      final g = parseGrade('{"awarded": 1}', itemId: 'q', outOf: 4)
          .copyWith(userOverride: 4);
      expect(g.awarded, 1);
      expect(g.effective, 4);
    });
  });
}
