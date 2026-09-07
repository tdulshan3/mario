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
import 'ai_markdown_blocks.dart';

/// The document as it was before a run, so it can be put back exactly.
class AgentSnapshot {
  const AgentSnapshot({
    required this.document,
    required this.title,
    this.htmlArtifact,
  });

  final Map<String, dynamic> document;
  final String title;

  /// The page's verbatim HTML artifact, which lives beside the AppFlowy
  /// document in the Drive payload rather than inside its block tree.
  final String? htmlArtifact;
}

/// Applies agent actions to an [afe.EditorState].
class AgentExecutor {
  AgentExecutor(this.editorState);

  final afe.EditorState editorState;

  /// The top-level block order as the run began.
  ///
  /// A rewrite deletes several blocks and then inserts their replacements, so
  /// by the time a gap has to be resolved its neighbours may be gone too. The
  /// original order is the only thing that still says where each block SAT;
  /// the live tree no longer does.
  List<String> _orderAtRunStart = const [];

  /// Where a deleted block used to sit, as the id of the block before it in
  /// [_orderAtRunStart] (null when it was the first).
  ///
  /// A rewrite is often "delete the old, insert the new in its place", and the
  /// insert names the deleted block in `afterBlockId` — which by then resolves
  /// to nothing, so the replacement landed at the END of the page. That is the
  /// "it stacked underneath instead of replacing" behaviour.
  ///
  /// Ids rather than paths: paths shift under every edit that follows.
  final Map<String, String?> _deletedAfter = {};

  /// What has since been inserted into a deleted block's gap.
  ///
  /// Without this a whole-page rewrite came out REVERSED: every replacement
  /// chained back to a deleted first block and so landed at the top, each one
  /// pushing the last one down. Once a gap has been filled, the block that
  /// filled it is where the next one belongs.
  final Map<String, String> _replacedBy = {};

  /// Called once per run, before any action — so it doubles as the point to
  /// forget the previous run's bookkeeping.
  AgentSnapshot snapshot(String title, {String? htmlArtifact}) {
    _orderAtRunStart = [
      for (final n in editorState.document.root.children) n.id,
    ];
    _deletedAfter.clear();
    _replacedBy.clear();
    return AgentSnapshot(
      document: editorState.document.toJson(),
      title: title,
      htmlArtifact: htmlArtifact,
    );
  }

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
      case AgentActionKind.moveBlock:
        return _moveBlock(action);
      case AgentActionKind.writePage:
        // Only the current page reaches here; the panel sends a named page
        // to the tools, which write through the content repository.
        return _writeWhole(action);
      case AgentActionKind.renamePage:
      case AgentActionKind.createPage:
      case AgentActionKind.createSection:
      case AgentActionKind.renameSection:
      case AgentActionKind.createNotebook:
      case AgentActionKind.setting:
      case AgentActionKind.htmlArtifact:
      case AgentActionKind.readPage:
      case AgentActionKind.listNotebooks:
      case AgentActionKind.listPages:
      case AgentActionKind.searchNotes:
      case AgentActionKind.webSearch:
      case AgentActionKind.openPage:
      case AgentActionKind.askUser:
        // Handled by the caller: none of these lives in the document.
        return true;
      default:
        final nodes = _nodesFor(action);
        if (nodes.isEmpty) return false;
        return _insert(nodes, action.afterBlockId);
    }
  }

  Future<bool> _insert(List<afe.Node> nodes, String? afterBlockId) async {
    final path = _insertionPath(afterBlockId);
    final ok =
        await safeApply(editorState, (tx) => tx.insertNodes(path, nodes));

    // A gap that has now been filled: anything anchored to a LATER deleted
    // block belongs after this, not back at the original gap.
    //
    // The id is read back out of the DOCUMENT, not taken from `nodes`.
    // `insertNodes` deep-copies by default and `copyWith` mints a fresh id, so
    // the node that actually landed is not the one handed in — recording the
    // id of the outgoing copy left every lookup failing, and a whole-page
    // rewrite came out reversed.
    if (ok && afterBlockId != null && _deletedAfter.containsKey(afterBlockId)) {
      final children = editorState.document.root.children;
      final last = path.last + nodes.length - 1;
      if (last >= 0 && last < children.length) {
        _replacedBy[afterBlockId] = children[last].id;
      }
    }
    return ok;
  }

  /// Writes Markdown after, before, or instead of everything on the page.
  ///
  /// `replace` inserts first and deletes second, exactly as [restore] does:
  /// a page with no top-level block has nothing focusable.
  Future<bool> _writeWhole(AgentAction action) async {
    final nodes = marioMarkdownToNodes(action.text);
    if (nodes.isEmpty) return false;
    switch (action.mode) {
      case 'prepend':
        return safeApply(editorState, (tx) => tx.insertNodes([0], nodes));
      case 'replace':
        final existing = [...editorState.document.root.children];
        return safeApply(editorState, (tx) {
          tx.insertNodes([existing.length], nodes);
          for (final node in existing) {
            tx.deleteNode(node);
          }
        });
      default:
        return _insert(nodes, null);
    }
  }

  /// Where an insert anchored to [afterBlockId] should go.
  ///
  /// Falls back to the end of the page only when there is genuinely nowhere
  /// else — an anchor that has been DELETED this run resolves to the gap it
  /// left, so "delete the old paragraph, insert the rewritten one after it"
  /// puts the new text where the old text was.
  List<int> _insertionPath(String? afterBlockId, [Set<String>? seen]) {
    final end = [editorState.document.root.children.length];
    if (afterBlockId == null) return end;

    // Chains run strictly backwards through the run-start order, so they
    // terminate — but a malformed plan must not be able to spin here.
    final visited = seen ?? <String>{};
    if (!visited.add(afterBlockId)) return end;

    // Filled gaps first: the replacement stands in for the block that was
    // there, so later blocks queue up after it.
    final filler = _replacedBy[afterBlockId];
    if (filler != null) {
      final node = _findById(editorState.document.root, filler);
      if (node != null) return node.path.next;
    }

    final anchor = _findById(editorState.document.root, afterBlockId);
    if (anchor != null) return anchor.path.next;

    if (_deletedAfter.containsKey(afterBlockId)) {
      final before = _deletedAfter[afterBlockId];
      // It was the first block, so its gap is the top of the page.
      if (before == null) return [0];
      return _insertionPath(before, visited);
    }

    return end;
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
        tx.insertNode(
          node.path.next,
          afe.paragraphNode(delta: marioInlineDelta(action.text)),
        );
        tx.deleteNode(node);
      });
    }
    // Styled, for the same reason the insert path is: "rewrite this line as
    // **X**" otherwise leaves the asterisks in the page.
    //
    // The whole delta is swapped rather than going through `replaceText`,
    // which applies ONE set of attributes across the span it writes and so
    // cannot express a line that is partly bold. Replacing the delta is also a
    // single operation, which keeps the action a single undo step.
    return safeApply(editorState, (tx) {
      tx.updateNode(node, {
        afe.blockComponentDelta: marioInlineDelta(action.text).toJson(),
      });
    });
  }

  Future<bool> _deleteBlock(AgentAction action) async {
    final node = _findById(editorState.document.root, action.blockId!);
    if (node == null) return false;
    _rememberGap(action.blockId!, node);
    // Never leave the document empty; see restore().
    if (editorState.document.root.children.length <= 1) {
      return safeApply(editorState, (tx) {
        tx.insertNode(node.path.next, _paragraph(''));
        tx.deleteNode(node);
      });
    }
    return safeApply(editorState, (tx) => tx.deleteNode(node));
  }

  /// Notes which block a deleted one sat after, so an insert aimed at it can
  /// still find the gap. Top-level blocks only: [_insertionPath] resolves
  /// against the root's children.
  ///
  /// Read from the RUN-START order, not from the live tree. By the time the
  /// third block of a rewrite is deleted its neighbours are already gone, and
  /// the live tree would report "nothing before me" for all of them — which is
  /// how every replacement ended up at the top of the page.
  void _rememberGap(String id, afe.Node node) {
    final original = _orderAtRunStart.indexOf(id);
    if (original >= 0) {
      _deletedAfter[id] = original == 0 ? null : _orderAtRunStart[original - 1];
      return;
    }

    // Created during this run, so the run-start order knows nothing about it;
    // its surviving neighbour is the best answer available.
    final siblings = editorState.document.root.children;
    final index = siblings.indexOf(node);
    if (index < 0) return;
    _deletedAfter[id] = index == 0 ? null : siblings[index - 1].id;
  }

  /// Moves an existing block to just after another — how the agent puts a
  /// picture beside the text that discusses it.
  ///
  /// Copy-insert-then-delete rather than a move operation: AppFlowy's
  /// `moveNode` needs the destination path to be correct *after* the removal,
  /// which is a different index depending on whether the target sits before or
  /// after the source. Getting that off by one silently puts the block in the
  /// wrong place, and the copy costs nothing at this size.
  Future<bool> _moveBlock(AgentAction action) async {
    final node = _findById(editorState.document.root, action.blockId!);
    if (node == null) return false;

    final afterId = action.afterBlockId;
    final anchor =
        afterId == null ? null : _findById(editorState.document.root, afterId);
    if (afterId != null && anchor == null) return false;
    if (identical(anchor, node)) return false;

    final copy = node.copyWith();
    return safeApply(editorState, (tx) {
      tx.insertNode(
        anchor?.path.next ?? [editorState.document.root.children.length],
        copy,
      );
      tx.deleteNode(node);
    });
  }

  /// Builds the nodes one action inserts.
  ///
  /// Text-bearing nodes take a STYLED delta. Models write markdown even when
  /// the plan already says "this is a heading" — a paragraph action whose text
  /// is "the **key** point" was landing in the page with the asterisks
  /// visible, because the delta was a single unstyled insert of the literal
  /// string. [marioInlineDelta] pulls the styling out and leaves the block
  /// structure alone, which is what these actions have already decided.
  ///
  /// Code, formulas and spreadsheet cells are exempt: their content is
  /// literal, and "styling" a snippet would eat the very characters that make
  /// it a snippet.
  List<afe.Node> _nodesFor(AgentAction a) {
    switch (a.kind) {
      case AgentActionKind.paragraph:
        return [afe.paragraphNode(delta: marioInlineDelta(a.text))];
      case AgentActionKind.heading:
        return [
          afe.headingNode(level: a.level, delta: marioInlineDelta(a.text)),
        ];
      case AgentActionKind.quote:
        return [afe.quoteNode(delta: marioInlineDelta(a.text))];
      case AgentActionKind.divider:
        return [afe.dividerNode()];
      case AgentActionKind.bullets:
        return [
          for (final i in a.items)
            afe.bulletedListNode(delta: marioInlineDelta(i)),
        ];
      case AgentActionKind.numbered:
        return [
          for (final i in a.items)
            afe.numberedListNode(delta: marioInlineDelta(i)),
        ];
      case AgentActionKind.todo:
        return [
          for (final i in a.items)
            afe.todoListNode(checked: false, delta: marioInlineDelta(i)),
        ];
      case AgentActionKind.code:
        return [codeBlockNode(code: a.text, language: a.language)];
      case AgentActionKind.math:
        return [mathEquationNode(formula: a.text)];
      case AgentActionKind.table:
        return [_tableNode(a.rows)];
      case AgentActionKind.spreadsheet:
        return [spreadsheetNode(workbook: _workbook(a.rows, a.text))];
      case AgentActionKind.markdown:
        return marioMarkdownToNodes(a.text);
      case AgentActionKind.htmlArtifact:
      case AgentActionKind.renamePage:
      case AgentActionKind.createPage:
      case AgentActionKind.createSection:
      case AgentActionKind.renameSection:
      case AgentActionKind.createNotebook:
      case AgentActionKind.writePage:
      case AgentActionKind.readPage:
      case AgentActionKind.listNotebooks:
      case AgentActionKind.listPages:
      case AgentActionKind.searchNotes:
      case AgentActionKind.webSearch:
      case AgentActionKind.openPage:
      case AgentActionKind.askUser:
      case AgentActionKind.replaceBlock:
      case AgentActionKind.deleteBlock:
      case AgentActionKind.moveBlock:
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
