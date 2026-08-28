/// `/ask`, `/summary` and `/quiz` — the AI entries in the editor's slash menu.
///
/// Unlike every other item in that menu, these insert nothing. `mathSelection
/// MenuItem` and friends use `SelectionMenuItem.node`, which builds a node and
/// commits it in one transaction; these open the side panel instead, and the
/// answer only reaches the document if the user presses Insert. That ordering
/// is the point: a model's output should not appear in someone's notes before
/// they have read it.
///
/// They also have to clean up after themselves. `SelectionMenuItem.node`
/// deletes the typed "/" via its own machinery, but the plain constructor's
/// `deleteSlash` only removes the slash character — the "ask" the user typed
/// after it stays behind. [_removeSlashCommand] strips the whole token.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';

import '../editor/blocks/_safe_transaction.dart';

/// Builds the menu items, given a way to reach the panel.
///
/// [onAsk] receives whatever the user typed after the command, so
/// `/ask what is a monad` submits that question directly instead of making
/// them retype it in the panel.
List<afe.SelectionMenuItem> aiSelectionMenuItems({
  required void Function(String question) onAsk,
  required VoidCallback onSummary,
  required VoidCallback onQuiz,
}) =>
    [
      afe.SelectionMenuItem(
        getName: () => 'Ask AI',
        icon: (editorState, onSelected, style) => Icon(
          Icons.auto_awesome,
          size: 18,
          color: onSelected
              ? style.selectionMenuItemSelectedIconColor
              : style.selectionMenuItemIconColor,
        ),
        keywords: const ['ask', 'ai', 'question', 'chat'],
        handler: (editorState, _, __) async {
          final trailing = await _removeSlashCommand(editorState, 'ask');
          onAsk(trailing);
        },
      ),
      afe.SelectionMenuItem(
        getName: () => 'Summarise above',
        icon: (editorState, onSelected, style) => Icon(
          Icons.subject,
          size: 18,
          color: onSelected
              ? style.selectionMenuItemSelectedIconColor
              : style.selectionMenuItemIconColor,
        ),
        keywords: const ['summary', 'summarise', 'summarize', 'tldr', 'recap'],
        handler: (editorState, _, __) async {
          await _removeSlashCommand(editorState, 'summary');
          onSummary();
        },
      ),
      afe.SelectionMenuItem(
        getName: () => 'Quiz me',
        icon: (editorState, onSelected, style) => Icon(
          Icons.quiz_outlined,
          size: 18,
          color: onSelected
              ? style.selectionMenuItemSelectedIconColor
              : style.selectionMenuItemIconColor,
        ),
        keywords: const ['quiz', 'test', 'exam', 'mcq', 'revise'],
        handler: (editorState, _, __) async {
          await _removeSlashCommand(editorState, 'quiz');
          onQuiz();
        },
      ),
    ];

/// Deletes the `/command…` text the user typed and returns anything they wrote
/// after the command name.
///
/// The menu is still filtering on that text when the handler fires, so it is
/// sitting in the paragraph and has to come out. Returns '' when there was
/// nothing beyond the command itself.
Future<String> _removeSlashCommand(
    afe.EditorState editorState, String command) async {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) return '';
  final node = editorState.getNodeAtPath(selection.end.path);
  final delta = node?.delta;
  if (node == null || delta == null) return '';

  final text = delta.toPlainText();
  final caret = selection.end.offset;
  final slash = text.lastIndexOf('/', caret == 0 ? 0 : caret - 1);
  if (slash < 0) return '';

  final typed = text.substring(slash + 1, caret);
  // Everything after the command word is the user's question.
  final trailing = typed.length > command.length
      ? typed.substring(command.length).trim()
      : '';

  await safeApply(editorState, (tx) {
    tx.deleteText(node, slash, caret - slash);
  });
  return trailing;
}

/// Inserts [markdown] into the document after the current block.
///
/// Goes through [safeApply] and through `markdownToDocument` rather than
/// building nodes by hand: the answer may contain headings, lists and code
/// fences, and hand-rolling that conversion is how you end up with a paragraph
/// containing literal asterisks.
///
/// Returns false when the editor was disposed mid-flight — the panel outlives
/// the page, so by the time a slow local model finishes the user may well have
/// navigated away.
Future<bool> insertMarkdownIntoDocument(
  afe.EditorState editorState,
  String markdown,
) async {
  if (editorState.isDisposed) return false;

  final parsed = afe.markdownToDocument(markdown);
  // copyWith detaches each node from the parsed document's root. Inserting a
  // node that still has a parent leaves it in two trees at once, and its
  // `path` then resolves against the wrong one.
  final nodes = [
    for (final n in parsed.root.children) n.copyWith(),
  ];
  if (nodes.isEmpty) return false;

  // Anchor at the caret when there is one; otherwise append to the end, which
  // is what "insert into the page" should mean when the page has no focus.
  final selection = editorState.selection;
  final anchor =
      selection == null ? null : editorState.getNodeAtPath(selection.end.path);
  final path = anchor?.path.next ?? [editorState.document.root.children.length];

  return safeApply(editorState, (tx) {
    tx.insertNodes(path, nodes);
  });
}
