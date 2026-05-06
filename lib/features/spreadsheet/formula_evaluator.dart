/// FormulaEvaluator — SUM/AVERAGE/COUNT + cell-ref arithmetic.
library;

import 'package:math_expressions/math_expressions.dart';

import 'sheet_data.dart';

class FormulaEvaluator {
  const FormulaEvaluator._();

  static final _parser = ShuntingYardParser();
  static final _ctx = ContextModel();

  static final _funcRe =
      RegExp(r'^=\s*(SUM|AVERAGE|AVG|COUNT)\s*\(([^)]*)\)\s*$', caseSensitive: false);
  static final _cellRefRe = RegExp(r'\b([A-Z]+)(\d+)\b');

  /// Evaluate a cell's [raw] text, looking up referenced cells in [sheet].
  ///
  /// - Non-formulas (raw text not starting with `=`) return [raw] verbatim.
  /// - Formulas return the formatted result, or '#ERR' on failure.
  static String evaluate(String raw, SheetData sheet) {
    if (raw.isEmpty || !raw.trimLeft().startsWith('=')) return raw;

    final trimmed = raw.trim();

    final funcMatch = _funcRe.firstMatch(trimmed);
    if (funcMatch != null) {
      final fn = funcMatch.group(1)!.toUpperCase();
      final argString = funcMatch.group(2)!;
      final values = _resolveArgs(argString, sheet);
      switch (fn) {
        case 'SUM':
          return _format(values.fold<double>(0, (a, b) => a + b));
        case 'AVERAGE':
        case 'AVG':
          if (values.isEmpty) return '#ERR';
          return _format(values.reduce((a, b) => a + b) / values.length);
        case 'COUNT':
          return _countNonEmpty(argString, sheet).toString();
      }
    }

    // Generic arithmetic: substitute cell refs with their numeric values.
    final substituted = trimmed.substring(1).replaceAllMapped(
      _cellRefRe,
      (m) {
        final id = '${m.group(1)}${m.group(2)}';
        final referenced = sheet.cells[id] ?? '';
        final value = evaluate(referenced, sheet);
        final n = double.tryParse(value);
        return n == null ? '0' : n.toString();
      },
    );

    try {
      final exp = _parser.parse(substituted);
      final result = exp.evaluate(EvaluationType.REAL, _ctx);
      if (result is num) return _format(result.toDouble());
      return result.toString();
    } catch (_) {
      return '#ERR';
    }
  }

  static List<double> _resolveArgs(String argString, SheetData sheet) {
    final values = <double>[];
    for (final part in argString.split(',')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      if (p.contains(':')) {
        final ends = p.split(':');
        if (ends.length != 2) continue;
        final start = parseCellId(ends[0]);
        final end = parseCellId(ends[1]);
        if (start == null || end == null) continue;
        for (var r = start.row; r <= end.row; r++) {
          for (var c = start.col; c <= end.col; c++) {
            final v = _numericAt(r, c, sheet);
            if (v != null) values.add(v);
          }
        }
      } else {
        final id = parseCellId(p);
        if (id != null) {
          final v = _numericAt(id.row, id.col, sheet);
          if (v != null) values.add(v);
        } else {
          final n = double.tryParse(p);
          if (n != null) values.add(n);
        }
      }
    }
    return values;
  }

  static int _countNonEmpty(String argString, SheetData sheet) {
    var count = 0;
    for (final part in argString.split(',')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      if (p.contains(':')) {
        final ends = p.split(':');
        if (ends.length != 2) continue;
        final start = parseCellId(ends[0]);
        final end = parseCellId(ends[1]);
        if (start == null || end == null) continue;
        for (var r = start.row; r <= end.row; r++) {
          for (var c = start.col; c <= end.col; c++) {
            final raw = sheet.raw(r, c);
            if (raw != null && raw.isNotEmpty) count++;
          }
        }
      } else {
        final id = parseCellId(p);
        if (id != null) {
          final raw = sheet.raw(id.row, id.col);
          if (raw != null && raw.isNotEmpty) count++;
        }
      }
    }
    return count;
  }

  static double? _numericAt(int row, int col, SheetData sheet) {
    final raw = sheet.raw(row, col);
    if (raw == null || raw.isEmpty) return null;
    final v = evaluate(raw, sheet);
    return double.tryParse(v);
  }

  static String _format(double value) {
    if (value.isNaN || value.isInfinite) return value.toString();
    if (value == value.truncateToDouble()) return value.toInt().toString();
    final fixed = value.toStringAsFixed(6);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
