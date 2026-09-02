/// Applying agent actions to a real document.
///
/// The validation layer decides what is *allowed*; this decides whether it
/// actually works. The most important test is the last group: a snapshot has to
/// restore the page exactly, because it is the only thing making an agent run
/// reversible — Ctrl-Z would be one press per action, and the user cannot know
/// how many a plan made.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/agent_actions.dart';
import 'package:mario/features/ai/agent_executor.dart';
import 'package:mario/features/ai/note_context.dart';

void main() {
  afe.EditorState editorWith(List<String> paragraphs) {
    return afe.EditorState(
      document: afe.Document.fromJson({
        'document': {
          'type': 'page',
          'children': [
            for (final p in paragraphs)
              {
                'type': 'paragraph',
                'data': {
                  'delta': [
                    {'insert': p}
                  ]
                },
              },
          ],
        }
      }),
    );
  }

  List<String> blockTexts(afe.EditorState state) => [
        for (final b in extractNoteText(state.document).blocks) b.text,
      ];

  group('inserting', () {
    test('appends a paragraph at the end by default', () async {
      final state = editorWith(['first']);
      final ok = await AgentExecutor(state)
          .apply(const AgentAction(kind: AgentActionKind.paragraph, text: 'second'));
      expect(ok, isTrue);
      expect(blockTexts(state), ['first', 'second']);
    });

    test('inserts after a named block', () async {
      final state = editorWith(['first', 'third']);
      final firstId = state.document.root.children.first.id;
      await AgentExecutor(state).apply(AgentAction(
        kind: AgentActionKind.paragraph,
        text: 'second',
        afterBlockId: firstId,
      ));
      expect(blockTexts(state), ['first', 'second', 'third']);
    });

    test('a heading keeps its level', () async {
      final state = editorWith(['x']);
      await AgentExecutor(state).apply(
        const AgentAction(
            kind: AgentActionKind.heading, text: 'Cells', level: 2),
      );
      final note = extractNoteText(state.document);
      expect(note.blocks.last.headingLevel, 2);
      expect(note.blocks.last.text, '## Cells');
    });

    test('a list becomes one block per item', () async {
      final state = editorWith(['x']);
      await AgentExecutor(state).apply(const AgentAction(
        kind: AgentActionKind.bullets,
        items: ['alpha', 'beta', 'gamma'],
      ));
      expect(blockTexts(state), ['x', '- alpha', '- beta', '- gamma']);
    });

    test('a code block keeps its language and body', () async {
      final state = editorWith(['x']);
      await AgentExecutor(state).apply(const AgentAction(
        kind: AgentActionKind.code,
        text: 'print("hi")',
        language: 'python',
      ));
      expect(blockTexts(state).last, '```python\nprint("hi")\n```');
    });

    test('a formula becomes a math block', () async {
      final state = editorWith(['x']);
      await AgentExecutor(state).apply(
        const AgentAction(kind: AgentActionKind.math, text: 'E = mc^2'),
      );
      expect(blockTexts(state).last, r'$$E = mc^2$$');
    });

    test('a wrapped formula is stored without nested math delimiters',
        () async {
      final state = editorWith(['x']);
      await AgentExecutor(state).apply(
        const AgentAction(kind: AgentActionKind.math, text: r'$$E = mc^2$$'),
      );
      final node = state.document.root.children.last;
      expect(node.attributes['formula'], r'E = mc^2');
      expect(blockTexts(state).last, r'$$E = mc^2$$');
    });

    test('a table is transposed into AppFlowy column-major form', () async {
      // The model writes rows, as a person would; AppFlowy's table is columns.
      // Getting this backwards produces a table with the axes swapped, which
      // looks plausible and is wrong.
      final state = editorWith(['x']);
      final ok = await AgentExecutor(state).apply(const AgentAction(
        kind: AgentActionKind.table,
        rows: [
          ['Method', 'Cost'],
          ['A', 'low'],
          ['B', 'high'],
        ],
      ));
      expect(ok, isTrue);

      final table = state.document.root.children.last;
      expect(table.type, afe.TableBlockKeys.type);
      expect(table.attributes[afe.TableBlockKeys.colsLen], 2);
      expect(table.attributes[afe.TableBlockKeys.rowsLen], 3);
      // Read the cells back by their own row/col attributes: if rows and
      // columns were swapped, "Cost" would land at (row 1, col 0) instead.
      String? cellAt(int col, int row) => table.children
          .where((c) =>
              c.attributes[afe.TableCellBlockKeys.colPosition] == col &&
              c.attributes[afe.TableCellBlockKeys.rowPosition] == row)
          .firstOrNull
          ?.children
          .first
          .delta
          ?.toPlainText();

      expect(cellAt(0, 0), 'Method');
      expect(cellAt(1, 0), 'Cost');
      expect(cellAt(0, 2), 'B');
      expect(cellAt(1, 2), 'high');
    });

    test('a spreadsheet carries its cells', () async {
      final state = editorWith(['x']);
      await AgentExecutor(state).apply(const AgentAction(
        kind: AgentActionKind.spreadsheet,
        text: 'Results',
        rows: [
          ['Trial', 'Mass'],
          ['1', '4.2'],
        ],
      ));
      final rendered = blockTexts(state).last;
      expect(rendered, contains('Results'));
      expect(rendered, contains('Trial\tMass'));
      expect(rendered, contains('1\t4.2'));
    });
  });

  group('changing what is already there', () {
    test('replaces a block by id', () async {
      final state = editorWith(['old text', 'other']);
      final id = state.document.root.children.first.id;
      final ok = await AgentExecutor(state).apply(
        AgentAction(
            kind: AgentActionKind.replaceBlock,
            blockId: id,
            text: 'new text'),
      );
      expect(ok, isTrue);
      expect(blockTexts(state), ['new text', 'other']);
    });

    test('deletes a block by id', () async {
      final state = editorWith(['keep', 'remove', 'keep too']);
      final id = state.document.root.children[1].id;
      await AgentExecutor(state)
          .apply(AgentAction(kind: AgentActionKind.deleteBlock, blockId: id));
      expect(blockTexts(state), ['keep', 'keep too']);
    });

    test('deleting the last block leaves the page typeable', () async {
      // A document with zero top-level children has nothing focusable, and the
      // canvas becomes unclickable — the bug _ensureNonEmptyDocument heals.
      final state = editorWith(['only one']);
      final id = state.document.root.children.first.id;
      await AgentExecutor(state)
          .apply(AgentAction(kind: AgentActionKind.deleteBlock, blockId: id));
      expect(state.document.root.children, isNotEmpty);
    });

    test('a target that has since gone reports failure rather than guessing',
        () async {
      final state = editorWith(['a']);
      final ok = await AgentExecutor(state).apply(
        const AgentAction(
            kind: AgentActionKind.deleteBlock, blockId: 'vanished'),
      );
      expect(ok, isFalse);
      expect(blockTexts(state), ['a']);
    });
  });

  group('moving a block — how a picture ends up beside its text', () {
    test('moves a block to just after another', () async {
      final state = editorWith(['intro', 'picture', 'about the picture']);
      final pictureId = state.document.root.children[1].id;
      final aboutId = state.document.root.children[2].id;

      final ok = await AgentExecutor(state).apply(AgentAction(
        kind: AgentActionKind.moveBlock,
        blockId: pictureId,
        afterBlockId: aboutId,
      ));
      expect(ok, isTrue);
      expect(blockTexts(state), ['intro', 'about the picture', 'picture']);
    });

    test('moves backwards as well as forwards', () async {
      // The direction that an index-arithmetic move gets wrong: the
      // destination index differs depending on whether the target sits before
      // or after the source.
      final state = editorWith(['a', 'b', 'c']);
      final cId = state.document.root.children[2].id;
      final aId = state.document.root.children.first.id;

      await AgentExecutor(state).apply(AgentAction(
        kind: AgentActionKind.moveBlock,
        blockId: cId,
        afterBlockId: aId,
      ));
      expect(blockTexts(state), ['a', 'c', 'b']);
    });

    test('with no target, moves to the end', () async {
      final state = editorWith(['a', 'b', 'c']);
      final aId = state.document.root.children.first.id;
      await AgentExecutor(state).apply(
        AgentAction(kind: AgentActionKind.moveBlock, blockId: aId),
      );
      expect(blockTexts(state), ['b', 'c', 'a']);
    });

    test('a vanished source or target fails rather than guessing', () async {
      final state = editorWith(['a', 'b']);
      final aId = state.document.root.children.first.id;

      expect(
        await AgentExecutor(state).apply(const AgentAction(
            kind: AgentActionKind.moveBlock, blockId: 'gone')),
        isFalse,
      );
      expect(
        await AgentExecutor(state).apply(AgentAction(
          kind: AgentActionKind.moveBlock,
          blockId: aId,
          afterBlockId: 'gone',
        )),
        isFalse,
      );
      expect(blockTexts(state), ['a', 'b']);
    });

    test('a move is undone by the snapshot like anything else', () async {
      final state = editorWith(['a', 'b', 'c']);
      final executor = AgentExecutor(state);
      final before = executor.snapshot('t');

      await executor.apply(AgentAction(
        kind: AgentActionKind.moveBlock,
        blockId: state.document.root.children.first.id,
      ));
      expect(blockTexts(state), ['b', 'c', 'a']);

      await executor.restore(before);
      expect(blockTexts(state), ['a', 'b', 'c']);
    });
  });

  group('undo puts the page back exactly', () {
    test('after a run of several actions', () async {
      final state = editorWith(['original one', 'original two']);
      final executor = AgentExecutor(state);
      final before = executor.snapshot('My page');
      final textBefore = blockTexts(state);

      await executor.apply(
          const AgentAction(kind: AgentActionKind.paragraph, text: 'added'));
      await executor.apply(const AgentAction(
          kind: AgentActionKind.bullets, items: ['x', 'y']));
      await executor.apply(AgentAction(
        kind: AgentActionKind.replaceBlock,
        blockId: state.document.root.children.first.id,
        text: 'rewritten',
      ));
      expect(blockTexts(state), isNot(textBefore));

      expect(await executor.restore(before), isTrue);
      expect(blockTexts(state), textBefore);
    });

    test('after a deletion', () async {
      final state = editorWith(['a', 'b', 'c']);
      final executor = AgentExecutor(state);
      final before = executor.snapshot('t');

      await executor.apply(AgentAction(
        kind: AgentActionKind.deleteBlock,
        blockId: state.document.root.children[1].id,
      ));
      expect(blockTexts(state), ['a', 'c']);

      await executor.restore(before);
      expect(blockTexts(state), ['a', 'b', 'c']);
    });

    test('the restored page is never left empty', () async {
      final state = editorWith(['a']);
      final executor = AgentExecutor(state);
      final before = executor.snapshot('t');
      await executor.restore(before);
      expect(state.document.root.children, isNotEmpty);
      expect(blockTexts(state), ['a']);
    });

    test('the snapshot keeps the title, which lives outside the document',
        () async {
      final state = editorWith(['a']);
      expect(AgentExecutor(state).snapshot('Chapter 4').title, 'Chapter 4');
    });
  });
}
