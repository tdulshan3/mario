/// Applying a validated plan to the open page.
///
/// The safety story is the snapshot. Before anything runs, the whole document
/// and the page title are captured; "Undo all" restores that exact state. That
/// is far better than relying on Ctrl-Z here, because a nine-action plan is
/// nine transactions and nine separate undo steps — a user who dislikes the
/// result would have to guess how many times to press it, and any typing in
/// between would break the chain.
///
/// Everything still goes through [safeApply], so a plan that finishes after the
/// user has navigated away is dropped rather than crashing, and machine edits
/// do not steal the caret.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;

import '../../features/spreadsheet/sheet_data.dart';
import '../editor/blocks/_safe_transaction.dart';
import '../editor/blocks/code_block.dart';
import '../editor/blocks/math_block.dart';
import '../editor/blocks/spreadsheet_block.dart';
import 'agent_actions.dart';

/// The document as it was before a run, so it can be put back exactly.
class AgentSnapshot {
  const AgentSnapshot({required this.document, required this.title});

  final Map<String, dynamic> document;
  final String title;
}

/// Applies agent actions to an [afe.EditorState].
class AgentExecutor {
  AgentExecutor(this.editorState);

  final afe.EditorState editorState;

  AgentSnapshot snapshot(String title) => AgentSnapshot(
        document: editorState.document.toJson(),
        title: title,
      );

  /// Restores a snapshot, discarding everything the run did.
  ///
  /// Replaces the children wholesale rather than trying to reverse each action:
  /// an inverse-operation approach has to be right about ordering, ids and
  /// nesting, and being wrong about any of them silently mangles the page.
  Future<bool> restore(AgentSnapshot snapshot) async {
    if (editorState.isDisposed) return false;
    final restored = afe.Document.fromJson(
      Map<String, dynamic>.from(snapshot.document),
    );
    final replacement = [
      for (final n in restored.root.children) n.copyWith(),
    ];
    final existing = [...editorState.document.root.children];

    return safeApply(editorState, (tx) {
      // Insert first, then delete: a document with zero top-level children has
      // nothing focusable and the canvas becomes untypeable — the bug
      // _ensureNonEmptyDocument exists to heal.
      tx.insertNodes([existing.length], replacement);
      for (final node in existing) {
        tx.deleteNode(node);
      }
    });
  }

  /// Runs one action. Returns false when it could not be applied — a target
  /// block that has since gone, or an editor that was torn down.
  Future<bool> apply(AgentAction action) async {
    if (editorState.isDisposed) return false;

    switch (action.kind) {
      case AgentActionKind.replaceBlock:
        return _replaceBlock(action);
      case AgentActionKind.deleteBlock:
        return _deleteBlock(action);
      case AgentActionKind.renamePage:
      case AgentActionKind.setting:
        // Handled by the caller: neither lives in the document.
        return true;
      default:
        final nodes = _nodesFor(action);
        if (nodes.isEmpty) return false;
        return _insert(nodes, action.afterBlockId);
    }
  }

  Future<bool> _insert(List<afe.Node> nodes, String? afterBlockId) async {
    final anchor = afterBlockId == null
        ? null
        : _findById(editorState.document.root, afterBlockId);
    final path =
        anchor?.path.next ?? [editorState.document.root.children.length];
    return safeApply(editorState, (tx) => tx.insertNodes(path, nodes));
  }

  Future<bool> _replaceBlock(AgentAction action) async {
    final node = _findById(editorState.document.root, action.blockId!);
    if (node == null) return false;
    final delta = node.delta;
    if (delta == null) {
      // Not a text block — swap it for a paragraph carrying the new text
      // rather than failing, which is what "rewrite this" means for a block
      // whose content is not a delta.
      return safeApply(editorState, (tx) {
        tx.insertNode(node.path.next, _paragraph(action.text));
        tx.deleteNode(node);
      });
    }
    return safeApply(editorState, (tx) {
      tx.replaceText(node, 0, delta.length, action.text);
    });
  }

  Future<bool> _deleteBlock(AgentAction action) async {
    final node = _findById(editorState.document.root, action.blockId!);
    if (node == null) return false;
    // Never leave the document empty; see restore().
    if (editorState.document.root.children.length <= 1) {
      return safeApply(editorState, (tx) {
        tx.insertNode(node.path.next, _paragraph(''));
        tx.deleteNode(node);
      });
    }
    return safeApply(editorState, (tx) => tx.deleteNode(node));
  }

  /// Builds the nodes one action inserts.
  List<afe.Node> _nodesFor(AgentAction a) {
    switch (a.kind) {
      case AgentActionKind.paragraph:
        return [_paragraph(a.text)];
      case AgentActionKind.heading:
        return [
          afe.headingNode(level: a.level, delta: afe.Delta()..insert(a.text)),
        ];
      case AgentActionKind.quote:
        return [afe.quoteNode(delta: afe.Delta()..insert(a.text))];
      case AgentActionKind.divider:
        return [afe.dividerNode()];
      case AgentActionKind.bullets:
        return [
          for (final i in a.items)
            afe.bulletedListNode(delta: afe.Delta()..insert(i)),
        ];
      case AgentActionKind.numbered:
        return [
          for (final i in a.items)
            afe.numberedListNode(delta: afe.Delta()..insert(i)),
        ];
      case AgentActionKind.todo:
        return [
          for (final i in a.items)
            afe.todoListNode(checked: false, delta: afe.Delta()..insert(i)),
        ];
      case AgentActionKind.code:
        return [codeBlockNode(code: a.text, language: a.language)];
      case AgentActionKind.math:
        return [mathEquationNode(formula: a.text)];
      case AgentActionKind.table:
        return [_tableNode(a.rows)];
      case AgentActionKind.spreadsheet:
        return [spreadsheetNode(workbook: _workbook(a.rows, a.text))];
      case AgentActionKind.renamePage:
      case AgentActionKind.replaceBlock:
      case AgentActionKind.deleteBlock:
      case AgentActionKind.setting:
        return const [];
    }
  }

  /// AppFlowy's table is column-major; a model writes rows, as a person would.
  afe.Node _tableNode(List<List<String>> rows) {
    final columnCount = rows.first.length;
    final cols = <List<String>>[
      for (var c = 0; c < columnCount; c++) [for (final row in rows) row[c]],
    ];
    return afe.TableNode.fromList(cols).node;
  }

  WorkbookData _workbook(List<List<String>> rows, String name) {
    final cells = <String, String>{};
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        final value = rows[r][c];
        if (value.trim().isEmpty) continue;
        cells[cellId(r + 1, c + 1)] = value;
      }
    }
    return WorkbookData(
      sheets: [
        SheetData(
          name: name.trim().isEmpty ? 'Sheet1' : name.trim(),
          // A little headroom so the sheet is editable around the data rather
          // than exactly filled by it.
          rows: (rows.length + 4).clamp(10, 200),
          cols: (rows.first.length + 2).clamp(10, 40),
          cells: cells,
        ),
      ],
    );
  }

  afe.Node _paragraph(String text) =>
      afe.paragraphNode(delta: afe.Delta()..insert(text));

  afe.Node? _findById(afe.Node root, String id) {
    for (final child in root.children) {
      if (child.id == id) return child;
      final found = _findById(child, id);
      if (found != null) return found;
    }
    return null;
  }
}
