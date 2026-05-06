/// math_shortcut — CharacterShortcutEvent that runs the tokenizer + auto-calc on space.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;

import 'math_evaluator.dart';
import 'math_tokenizer.dart';

/// Trigger character for both tokenizer and auto-calc.
const _trigger = ' ';

/// Detect `<expression>=` (with optional surrounding spaces) before the
/// cursor. Returns the (start, equalsIndex) pair or null.
///
/// Tolerates `2+2 = ` and `2+2= ` alike — Word/OneNote users routinely pad
/// the equals sign with spaces.
({int start, int equalsIdx})? _findEqualsExpression(String text, int cursor) {
  if (cursor < 2) return null;
  var equalsIdx = cursor - 1;
  while (equalsIdx >= 0 && (text[equalsIdx] == ' ' || text[equalsIdx] == '\t')) {
    equalsIdx--;
  }
  if (equalsIdx < 0 || text[equalsIdx] != '=') return null;
  final allowed = RegExp(r'[0-9a-zA-Z+\-*/^()., \t]');
  var i = equalsIdx - 1;
  while (i >= 0 && allowed.hasMatch(text[i])) {
    i--;
  }
  var start = i + 1;
  while (start < equalsIdx && (text[start] == ' ' || text[start] == '\t')) {
    start++;
  }
  if (start >= equalsIdx) return null;
  return (start: start, equalsIdx: equalsIdx);
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
  final eq = _findEqualsExpression(plain, cursor);
  if (eq != null) {
    final expression = plain.substring(eq.start, eq.equalsIdx);
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
