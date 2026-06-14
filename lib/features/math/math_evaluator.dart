/// MathEvaluator — wraps math_expressions for the auto-calc-on-equals feature.
library;

import 'package:math_expressions/math_expressions.dart';

class MathEvaluator {
  const MathEvaluator._();

  static final ShuntingYardParser _parser = ShuntingYardParser();
  static final ContextModel _ctx = ContextModel();

  // Characters that can never legally begin an arithmetic expression. A leading
  // one is almost always a stray operator left in the line — most commonly the
  // '/' from opening the slash-command menu and dismissing it (which leaves the
  // '/' behind), turning "2+2" into "/2+2". `(`, `.`, digits, letters (function
  // names / constants) and unary `+`/`-` are all valid starts, so they stay.
  static final RegExp _leadingJunk = RegExp(r'^[\s*/^,)]+');

  /// Evaluate [expression]. Returns a formatted string or null if the
  /// expression is invalid or contains free variables.
  static String? tryEvaluate(String expression) {
    final cleaned = expression.trim().replaceFirst(_leadingJunk, '');
    if (cleaned.isEmpty) return null;
    try {
      final exp = _parser.parse(cleaned);
      final result = exp.evaluate(EvaluationType.REAL, _ctx);
      if (result is num) return _format(result.toDouble());
      return result.toString();
    } catch (_) {
      return null;
    }
  }

  static String _format(double value) {
    if (value.isNaN || value.isInfinite) return value.toString();
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    final fixed = value.toStringAsFixed(6);
    return fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}
