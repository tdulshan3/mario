/// A block is a line.
///
/// The page is a stack of blocks and Enter makes a new one, so a page written
/// the way notes are written — one thought per line — is a stack of one-line
/// blocks. Any padding a block carries then shows up between every line and
/// the next, which is what "the line height is too much" meant: 8px of
/// editor padding on every block put 16px between each line of a list. The
/// spacing model is therefore the thing to pin down, not the look.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/editor/editor_typography.dart';
import 'package:mario/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  afe.EditorState editorWith(List<afe.Node> nodes) => afe.EditorState(
        document: afe.Document(root: afe.pageNode(children: nodes)),
      );

  group('text blocks carry no padding of their own', () {
    test('a paragraph, a list item and a quote are set flush', () {
      final flush = [
        afe.paragraphNode(text: 'a'),
        afe.bulletedListNode(text: 'a'),
        afe.numberedListNode(delta: afe.Delta()..insert('a')),
        afe.todoListNode(checked: false, text: 'a'),
        afe.quoteNode(delta: afe.Delta()..insert('a')),
      ];
      for (final node in flush) {
        expect(editorBlockPadding(node), EdgeInsets.zero, reason: node.type);
      }
    });

    test('a heading takes its band above, except at the top of the page', () {
      final state = editorWith([
        afe.headingNode(level: 2, text: 'First'),
        afe.paragraphNode(text: 'p'),
        afe.headingNode(level: 2, text: 'Second'),
      ]);
      final children = state.document.root.children.toList();
      // Under the page title, which already holds it off.
      expect(editorBlockPadding(children.first).top, 0);
      expect(editorBlockPadding(children.last).top, kHeadingSpaceAbove);
      // The band below is drawn by the wrapper, so a level-1 rule can sit
      // between the text and the space.
      expect(editorBlockPadding(children.last).bottom, 0);
    });

    test('a run of list items is set off from the prose around it', () {
      final state = editorWith([
        afe.paragraphNode(text: 'lead-in'),
        afe.bulletedListNode(text: 'one'),
        afe.bulletedListNode(text: 'two'),
        afe.bulletedListNode(text: 'three'),
        afe.paragraphNode(text: 'after'),
        afe.quoteNode(delta: afe.Delta()..insert('q')),
      ]);
      final blocks = state.document.root.children.toList();
      final pads = [for (final b in blocks) editorBlockPadding(b)];

      expect(pads[0], EdgeInsets.zero);
      // The run's edges carry the space; the item in the middle none.
      expect(pads[1], const EdgeInsets.only(top: kRunSpace));
      expect(pads[2], EdgeInsets.zero);
      expect(pads[3], const EdgeInsets.only(bottom: kRunSpace));
      expect(pads[4], EdgeInsets.zero);
      // A lone quote is a run of one.
      expect(pads[5], const EdgeInsets.only(top: kRunSpace, bottom: kRunSpace));
    });

    test('a run at the top of the page keeps no space above it', () {
      final state = editorWith([
        afe.bulletedListNode(text: 'one'),
        afe.bulletedListNode(text: 'two'),
      ]);
      final blocks = state.document.root.children.toList();
      expect(editorBlockPadding(blocks.first).top, 0);
      expect(editorBlockPadding(blocks.last).bottom, kRunSpace);
    });

    test('a nested list is spaced by its parent, not itself', () {
      final child = afe.bulletedListNode(text: 'inner');
      final state = editorWith([
        afe.bulletedListNode(text: 'outer', children: [child]),
      ]);
      final outer = state.document.root.children.first;
      expect(editorBlockPadding(outer.children.first), EdgeInsets.zero);
    });

    test('a divider claims the margin a preview gives an hr', () {
      expect(editorBlockPadding(afe.dividerNode()).vertical, greaterThan(0));
    });

    testWidgets('the line box is the whole spacing', (tester) async {
      late afe.TextStyleConfiguration styles;
      await tester.pumpWidget(MaterialApp(
        theme: MarioTheme.light(),
        home: Builder(builder: (context) {
          styles = editorTextStyles(context, ink: Colors.black);
          return const SizedBox();
        }),
      ));
      // Height applied to the first ascent and last descent is what makes a
      // one-line block one full line tall — without it, lines inside a block
      // sit 22px apart and lines across blocks 17px apart.
      expect(styles.lineHeight, kEditorLineHeight);
      expect(styles.applyHeightToFirstAscent, isTrue);
      expect(styles.applyHeightToLastDescent, isTrue);
      expect(styles.text.fontSize, kEditorFontSize);
    });
  });

  group('headings', () {
    test('follow the browser scale a preview inherits', () {
      expect(editorHeadingStyle(1).fontSize, 28);
      expect(editorHeadingStyle(2).fontSize, 21);
      expect(editorHeadingStyle(3).fontSize, closeTo(16.5, 0.01));
      expect(editorHeadingStyle(4).fontSize, kEditorFontSize);
    });

    test('never come out smaller than the text', () {
      for (final level in [5, 6]) {
        expect(editorHeadingStyle(level).fontSize,
            greaterThanOrEqualTo(kEditorFontSize));
      }
    });

    testWidgets('only a level-1 heading is ruled', (tester) async {
      Widget wrapped(int level) => Builder(
            builder: (context) => editorHeadingWrapper(
              context,
              afe.headingNode(level: level, text: 'h'),
              const SizedBox(width: 10, height: 10),
            ),
          );
      await tester.pumpWidget(MaterialApp(
        theme: MarioTheme.light(),
        home: Column(children: [wrapped(1), wrapped(2)]),
      ));

      final containers = tester.widgetList<Container>(find.byType(Container));
      final ruled = containers.where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.border != null;
      });
      expect(ruled, hasLength(1));
    });
  });

  group(':shortcode: converts under the keys', () {
    (afe.EditorState, afe.Node) typed(String text) {
      final state = editorWith([afe.paragraphNode(text: text)]);
      state.selection = afe.Selection.collapsed(
        afe.Position(path: [0], offset: text.length),
      );
      return (state, state.document.root.children.first);
    }

    test('the closing colon turns :smile into its emoji', () async {
      final (state, node) = typed('hello :smile');
      expect(await convertEmojiShortcode(state), isTrue);
      expect(node.delta!.toPlainText(), 'hello 😄');
      expect(state.selection!.end.offset, 'hello 😄'.length,
          reason: 'the caret stays after what was typed');
    });

    test('+1 and -1 are aliases too', () async {
      final (state, node) = typed(':+1');
      expect(await convertEmojiShortcode(state), isTrue);
      expect(node.delta!.toPlainText(), '👍');
    });

    test('a time, a word before a colon and an unknown alias are left alone',
        () async {
      for (final text in ['10:30', 'note', 'a: b', 'see :nosuchemoji', '']) {
        final (state, node) = typed(text);
        expect(await convertEmojiShortcode(state), isFalse, reason: text);
        expect(node.delta!.toPlainText(), text);
      }
    });

    test('nothing happens over a range selection', () async {
      final (state, node) = typed('x :smile');
      state.selection = afe.Selection(
        start: afe.Position(path: [0], offset: 0),
        end: afe.Position(path: [0], offset: 8),
      );
      expect(await convertEmojiShortcode(state), isFalse);
      expect(node.delta!.toPlainText(), 'x :smile');
    });
  });
}
