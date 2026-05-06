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
  });
}
