/// Not re-parsing an answer that is already finished.
///
/// This is the fix for "long responses get slower and then crash". Rendering a
/// growing string with MarkdownBody costs twice over, and both costs are
/// proportional to the whole answer and paid per token: the parser rebuilds the
/// entire document, and MarkdownBuilder stamps every block it emits with a
/// fresh UniqueKey, so Flutter unmounts and recreates every paragraph, heading
/// and list item rather than reusing any of them. Quadratic in the length of
/// the answer, which is exactly the reported shape — fine at first, unusable at
/// the end.
///
/// The cut point is the whole mechanism, so that is what these test: text above
/// the last blank line cannot be changed by anything appended after it, EXCEPT
/// where a construct spans the gap. Cut in the wrong place and the answer
/// renders wrong; refuse to cut and the crash comes back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/ai_markdown.dart';

void main() {
  group('settled text stops being rebuilt', () {
    testWidgets('the same widget instance is handed back as more arrives',
        (tester) async {
      // The mechanism: returning an identical instance makes
      // Element.updateChild short-circuit, so the settled half is not rebuilt
      // at all — no parse, no element teardown.
      Widget? first;
      Widget? later;

      await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: StreamingMarkdown('First paragraph.\n\nSecond par')),
      ));
      first = tester.widget<Column>(find.byType(Column).first).children.first;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StreamingMarkdown('First paragraph.\n\nSecond paragraph n')),
      ));
      later = tester.widget<Column>(find.byType(Column).first).children.first;

      expect(identical(first, later), isTrue,
          reason: 'a new instance here means the settled half re-parses');
    });

    testWidgets('the growing tail still renders', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StreamingMarkdown('Done.\n\nStill arriving here')),
      ));
      expect(find.textContaining('Still arriving'), findsOneWidget);
      expect(find.textContaining('Done.'), findsOneWidget);
    });

    testWidgets('a restarted answer is not stacked on the old one',
        (tester) async {
      // AiTasks clears the answer and re-streams a different one on the web
      // rescue. A cache keyed on an offset would reuse the old text under it.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StreamingMarkdown('Old answer.\n\nmore old')),
      ));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StreamingMarkdown('Totally new.\n\nnew tail')),
      ));
      await tester.pump();
      expect(find.textContaining('Old answer'), findsNothing);
      expect(find.textContaining('Totally new'), findsOneWidget);
    });

    testWidgets('a finished answer renders as one selectable piece',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StreamingMarkdown('All done.\n\nEvery bit.', done: true),
        ),
      ));
      await tester.pump();
      // One AiMarkdown, not a Column of two — so a selection can span the
      // whole answer and the final layout is exact.
      expect(find.byType(AiMarkdown), findsOneWidget);
    });

    testWidgets('an answer with no blank line yet still renders',
        (tester) async {
      // No safe cut: everything re-renders, exactly as before. Correct, just
      // not fast — and it must not render nothing.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StreamingMarkdown('One long unbroken sentence')),
      ));
      expect(find.textContaining('unbroken'), findsOneWidget);
    });

    testWidgets('no exception on an empty answer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StreamingMarkdown(''))),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('where the cut lands', () {
    // Tested directly rather than through rendered widgets: a widget test can
    // only observe that nothing crashed, and a cut in the wrong place renders
    // perfectly happily — it just renders the wrong thing.

    test('a blank line between paragraphs settles the text above it', () {
      const text = 'First paragraph.\n\nSecond, still arriving';
      expect(settlePoint(text), 'First paragraph.\n\n'.length);
    });

    test('the last blank line wins, not the first', () {
      const text = 'One.\n\nTwo.\n\nThree, arriving';
      expect(settlePoint(text), 'One.\n\nTwo.\n\n'.length);
    });

    test('no blank line means no cut', () {
      expect(settlePoint('One long unbroken sentence'), 0);
      expect(settlePoint(''), 0);
    });

    test('nothing is cut inside an unclosed code fence', () {
      // A blank line means nothing inside a fence, and the fence can still be
      // closed by text yet to arrive. Cutting here renders the first half of a
      // code block as prose.
      const partial = 'Here is code:\n\n```python\ndef f():\n\n    return 1';
      expect(settlePoint(partial), 'Here is code:\n\n'.length,
          reason: 'the blank line inside the fence must not be a cut point');
    });

    test('a closed fence settles, and text after it can be cut', () {
      const text =
          'Intro.\n\n```dart\nvar x = 1;\n```\n\nAfter the block.\n\ntail';
      expect(settlePoint(text),
          'Intro.\n\n```dart\nvar x = 1;\n```\n\nAfter the block.\n\n'.length);
    });

    test('a four-backtick fence is still a fence', () {
      // Counting the run rather than matching ``` exactly: a ````-fenced block
      // containing ``` would otherwise flip the state twice and settle inside
      // the code.
      const partial = 'Code:\n\n````\nline\n\nmore';
      expect(settlePoint(partial), 'Code:\n\n'.length);
    });

    test('a tilde fence counts too', () {
      const partial = 'Code:\n\n~~~\nline\n\nmore';
      expect(settlePoint(partial), 'Code:\n\n'.length);
    });

    test('no cut above trailing link definitions', () {
      // `[1]: https://…` resolves `[1]` anywhere in the document, so cutting
      // above them strips the destination off every citation in the settled
      // half and renders them as literal brackets.
      const withRefs = 'See [1] for detail.\n\nmore text\n\n[1]: https://x.com';
      expect(settlePoint(withRefs), 0);
    });

    test('a lone blank line at the end settles everything', () {
      const text = 'All of it.\n\n';
      expect(settlePoint(text), text.length);
    });
  });

  group('the split renders the same text as the whole', () {
    testWidgets('an unclosed fence is not split across two renderers',
        (tester) async {
      const partial = 'Here is code:\n\n```python\ndef f():\n\n    return 1';
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StreamingMarkdown(partial))),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('return 1'), findsOneWidget);
    });

    testWidgets('a link definition is never rendered literally',
        (tester) async {
      const withRefs = 'See [1] for detail.\n\n[1]: https://example.com\n';
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StreamingMarkdown(withRefs))),
      );
      await tester.pump();
      expect(find.textContaining('[1]:'), findsNothing,
          reason: 'rendered literally means the cut orphaned it');
    });
  });
}
