import 'package:flutter_test/flutter_test.dart';

import 'package:mario/features/math/math_evaluator.dart';
import 'package:mario/features/math/math_tokenizer.dart';

void main() {
  group('MathTokenizer', () {
    test('greek letters by name', () {
      final t = MathTokenizer.tryTokenize('alpha', 5);
      expect(t, isNotNull);
      expect(t!.replacement, 'α');
      expect(t.start, 0);
      expect(t.length, 5);
    });

    test('comparison operators (longest match first)', () {
      final t = MathTokenizer.tryTokenize('x>=', 3);
      expect(t!.replacement, '≥');
      final t2 = MathTokenizer.tryTokenize('x<->', 4);
      expect(t2!.replacement, '↔');
    });

    test('superscript single digit', () {
      final t = MathTokenizer.tryTokenize('x^2', 3);
      expect(t!.replacement, '²');
      expect(t.start, 1);
      expect(t.length, 2);
    });

    test('subscript', () {
      final t = MathTokenizer.tryTokenize('x_2', 3);
      expect(t!.replacement, '₂');
    });

    test('no match returns null', () {
      expect(MathTokenizer.tryTokenize('hello', 5), isNull);
    });
  });

  group('MathEvaluator', () {
    test('integer arithmetic', () {
      expect(MathEvaluator.tryEvaluate('2+3'), '5');
    });

    test('order of operations', () {
      expect(MathEvaluator.tryEvaluate('2+3*4'), '14');
    });

    test('parens', () {
      expect(MathEvaluator.tryEvaluate('(2+3)*4'), '20');
    });

    test('decimals trim trailing zeros', () {
      expect(MathEvaluator.tryEvaluate('1/2'), '0.5');
    });

    test('invalid expression returns null', () {
      expect(MathEvaluator.tryEvaluate('not math'), isNull);
    });

    // Regression: opening the `/` slash menu and dismissing it (Escape/click)
    // leaves the `/` in the line, so a following `2+2=` becomes `/2+2=`. The
    // leading stray operator must not break the calculation.
    test('tolerates a stray leading slash from the dismissed slash menu', () {
      expect(MathEvaluator.tryEvaluate('/2+2'), '4');
      expect(MathEvaluator.tryEvaluate('/2.5+2.5'), '5');
      expect(MathEvaluator.tryEvaluate('/10/4'), '2.5');
    });

    test('strips other leading binary operators left behind', () {
      expect(MathEvaluator.tryEvaluate('*3+1'), '4');
      expect(MathEvaluator.tryEvaluate('^2+2'), '4');
    });

    test('legitimate division is unaffected (does not start with an operator)',
        () {
      expect(MathEvaluator.tryEvaluate('10/2'), '5');
      expect(MathEvaluator.tryEvaluate('7/2'), '3.5');
    });

    test('valid leading characters are preserved', () {
      expect(MathEvaluator.tryEvaluate('-2.5+5'), '2.5'); // unary minus
      expect(MathEvaluator.tryEvaluate('(2+3)*2'), '10'); // paren
      expect(MathEvaluator.tryEvaluate('.5+.5'), '1'); // leading dot
    });
  });
}
