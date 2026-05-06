import 'package:flutter_test/flutter_test.dart';

import 'package:mario/features/spreadsheet/formula_evaluator.dart';
import 'package:mario/features/spreadsheet/sheet_data.dart';

void main() {
  group('cell address helpers', () {
    test('column letters', () {
      expect(columnLetters(0), 'A');
      expect(columnLetters(25), 'Z');
      expect(columnLetters(26), 'AA');
      expect(columnLetters(701), 'ZZ');
    });

    test('round-trip', () {
      for (final id in ['A1', 'B2', 'Z9', 'AA10', 'AB100']) {
        final p = parseCellId(id);
        expect(p, isNotNull);
        expect(cellId(p!.row, p.col), id);
      }
    });

    test('parse rejects garbage', () {
      expect(parseCellId(''), isNull);
      expect(parseCellId('1A'), isNull);
      expect(parseCellId('A0'), isNull);
    });
  });

  group('FormulaEvaluator', () {
    SheetData seed() {
      var sheet = SheetData.blank();
      sheet = sheet.withCell(0, 0, '10'); // A1
      sheet = sheet.withCell(1, 0, '20'); // A2
      sheet = sheet.withCell(2, 0, '30'); // A3
      sheet = sheet.withCell(0, 1, 'hello'); // B1
      return sheet;
    }

    test('non-formula returns raw text', () {
      expect(FormulaEvaluator.evaluate('hello', seed()), 'hello');
    });

    test('SUM range', () {
      expect(FormulaEvaluator.evaluate('=SUM(A1:A3)', seed()), '60');
    });

    test('AVERAGE range', () {
      expect(FormulaEvaluator.evaluate('=AVERAGE(A1:A3)', seed()), '20');
    });

    test('COUNT counts non-empty', () {
      expect(FormulaEvaluator.evaluate('=COUNT(A1:A3,B1)', seed()), '4');
    });

    test('cell ref arithmetic', () {
      expect(FormulaEvaluator.evaluate('=A1+A2', seed()), '30');
      expect(FormulaEvaluator.evaluate('=A1*2', seed()), '20');
    });

    test('invalid formula returns #ERR', () {
      expect(FormulaEvaluator.evaluate('=garbage(', seed()), '#ERR');
    });
  });
}
