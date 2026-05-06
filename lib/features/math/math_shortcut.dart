/// math_shortcut — CharacterShortcutEvent that runs the tokenizer + auto-calc on space.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;

import 'math_evaluator.dart';
import 'math_tokenizer.dart';

/// Trigger character for both tokenizer and auto-calc.
const _trigger = ' ';

/// Detect `<expression>=` immediately before the cursor (no space between
/// expression and `=`). Returns the start index of the expression or -1.
int _findEqualsExpression(String text, int cursor) {
  if (cursor < 2) return -1;
  if (text[cursor - 1] != '=') return -1;
  // Walk left until whitespace or start of string. Allow digits, letters,
  // operators, parens, dot.
  final allowed = RegExp(r'[0-9a-zA-Z+\-*/^().,]');
  int i = cursor - 2;
  while (i >= 0 && allowed.hasMatch(text[i])) {
    i--;
  }
  final start = i + 1;
  if (start >= cursor - 1) return -1;
  return start;
}

/// The math shortcut. Place it at the head of [characterShortcutEvents] so it
/// runs before the markdown shortcuts that also trigger on space.
final afe.CharacterShortcutEvent marioMathShortcut = afe.CharacterShortcutEvent(
  key: 'mario.math.space',
  character: _trigger,
  handler: _handle,
);

Future<bool> _handle(afe.EditorState editorState) async {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) return false;

  final node = editorState.getNodeAtPath(selection.end.path);
  final delta = node?.delta;
  if (node == null || delta == null) return false;

  final plain = delta.toPlainText();
  final cursor = selection.end.offset;
  if (cursor < 0 || cursor > plain.length) return false;

  // 1. Auto-calc on `<expr>=` followed by space.
  final exprStart = _findEqualsExpression(plain, cursor);
  if (exprStart >= 0) {
    final expression = plain.substring(exprStart, cursor - 1);
    final result = MathEvaluator.tryEvaluate(expression);
    if (result != null) {
      // Insert " <result>" after the `=`. We consume the user's space.
      final insertion = ' $result';
      final tx = editorState.transaction
        ..insertText(node, cursor, insertion)
        ..afterSelection = afe.Selection.collapsed(
          selection.end.copyWith(offset: cursor + insertion.length),
        );
      editorState.apply(tx);
      return true;
    }
  }

  // 2. Symbol tokenizer on the trailing token.
  final token = MathTokenizer.tryTokenize(plain, cursor);
  if (token != null) {
    final tx = editorState.transaction
      ..deleteText(node, token.start, token.length)
      ..insertText(node, token.start, token.replacement);
    final newOffset = token.start + token.replacement.length;
    tx.afterSelection = afe.Selection.collapsed(
      selection.end.copyWith(offset: newOffset),
    );
    editorState.apply(tx);
    // Let the space pass through normally so the user keeps typing.
    return false;
  }

  return false;
}
