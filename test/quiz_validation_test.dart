/// Generated questions are kept when they can be marked, whatever shape the
/// model wrote them in — and a batch that is thrown away says why.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/ai_artifacts.dart';
import 'package:mario/features/ai/ai_tasks.dart';

void main() {
  Map<String, dynamic> mcq({
    Object? options = const ['Thylakoid', 'Stroma', 'Cytosol', 'Nucleus'],
    Object? correct,
    String key = 'correctIndex',
    String kind = 'mcq',
  }) =>
      {
        'kind': kind,
        'question': 'Where do the light reactions happen?',
        'options': options,
        if (correct != null) key: correct,
      };

  group('the answer, however it is pointed at', () {
    test('a 0-based index, as asked for', () {
      final v = validateQuizItemsDetailed([mcq(correct: 0)]);
      expect(v.items.single.correctIndex, 0);
    });

    test('a number in quotes, a letter, or the option text', () {
      expect(
          validateQuizItemsDetailed([mcq(correct: '2')])
              .items
              .single
              .correctIndex,
          2);
      expect(
          validateQuizItemsDetailed([mcq(correct: 'B')])
              .items
              .single
              .correctIndex,
          1);
      expect(
          validateQuizItemsDetailed([mcq(correct: '(c)')])
              .items
              .single
              .correctIndex,
          2);
      expect(
          validateQuizItemsDetailed([mcq(correct: 'stroma', key: 'answer')])
              .items
              .single
              .correctIndex,
          1);
      expect(
          validateQuizItemsDetailed(
                  [mcq(correct: 'Nucleus', key: 'correctAnswer')])
              .items
              .single
              .correctIndex,
          3);
    });

    test('1-based, one past the end, is read as the last option', () {
      expect(
          validateQuizItemsDetailed([mcq(correct: 4)])
              .items
              .single
              .correctIndex,
          3);
    });

    test('an answer that names no option is refused, and says so', () {
      final v = validateQuizItemsDetailed([
        mcq(correct: 7),
        mcq(correct: 'Mitochondrion', key: 'answer'),
        mcq(),
      ]);
      expect(v.items, isEmpty);
      expect(v.rejected, {'no correct answer': 3});
    });
  });

  group('the options, however they are written', () {
    test('labelled "A) …" throughout, the labels come off', () {
      final v = validateQuizItemsDetailed([
        mcq(
          options: ['A) Thylakoid', 'B) Stroma', 'C) Cytosol', 'D) Nucleus'],
          correct: 'B',
        ),
      ]);
      expect(v.items.single.options,
          ['Thylakoid', 'Stroma', 'Cytosol', 'Nucleus']);
      expect(v.items.single.correctIndex, 1);
    });

    test('objects with a text field are options too', () {
      final v = validateQuizItemsDetailed([
        mcq(
          options: [
            {'label': 'A', 'text': 'Thylakoid'},
            {'label': 'B', 'text': 'Stroma'},
            {'label': 'C', 'text': 'Cytosol'},
            {'label': 'D', 'text': 'Nucleus'},
          ],
          correct: 0,
        ),
      ]);
      expect(v.items.single.options, hasLength(4));
      expect(v.items.single.options.first, 'Thylakoid');
    });

    test('three to six choices are a question; two or seven are not', () {
      expect(
          validateQuizItemsDetailed([
            mcq(options: ['a', 'b', 'c'], correct: 0)
          ]).items,
          hasLength(1));
      expect(
          validateQuizItemsDetailed([
            mcq(options: ['a', 'b', 'c', 'd', 'e'], correct: 4)
          ]).items,
          hasLength(1));
      final v = validateQuizItemsDetailed([
        mcq(options: ['a', 'b'], correct: 0),
        mcq(options: ['a', 'b', 'c', 'd', 'e', 'f', 'g'], correct: 0),
      ]);
      expect(v.items, isEmpty);
      expect(v.rejected, {'not 3–6 options': 2});
    });

    test('blank or duplicated options are refused', () {
      final v = validateQuizItemsDetailed([
        mcq(options: ['a', '', 'c', 'd'], correct: 0),
        mcq(options: ['a', 'A', 'c', 'd'], correct: 0),
      ]);
      expect(v.items, isEmpty);
      expect(v.rejected, {'blank option': 1, 'duplicate options': 1});
    });
  });

  group('essays', () {
    test('a rubric under any of its names', () {
      for (final key in ['expectedPoints', 'rubric', 'keyPoints']) {
        final v = validateQuizItemsDetailed([
          {
            'kind': 'essay',
            'question': 'Explain the Calvin cycle.',
            key: ['Fixation', 'Reduction', 'Regeneration'],
          },
        ]);
        expect(v.items.single.kind, QuizItemKind.essay, reason: key);
        expect(v.items.single.marks, 3);
      }
    });

    test('a rubric with no options means essay even without a kind', () {
      final v = validateQuizItemsDetailed([
        {
          'question': 'Explain the Calvin cycle.',
          'expectedPoints': ['Fixation'],
        },
      ]);
      expect(v.items.single.kind, QuizItemKind.essay);
    });

    test('"short_answer" is an essay; one with no rubric is refused', () {
      final v = validateQuizItemsDetailed([
        {
          'type': 'short_answer',
          'question': 'Q?',
          'rubric': ['p']
        },
        {'kind': 'essay', 'question': 'Q2?'},
      ]);
      expect(v.items.single.kind, QuizItemKind.essay);
      expect(v.rejected, {'essay with no rubric': 1});
    });
  });

  test('the old entry point still returns the kept items', () {
    expect(validateQuizItems([mcq(correct: 1)]), hasLength(1));
  });
}
