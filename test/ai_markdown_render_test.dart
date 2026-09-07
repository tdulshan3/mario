/// A model's answer has to arrive as prose, not as punctuation.
///
/// Models reply in Markdown everywhere — the Ask answer, the reasoning
/// channel, a quiz question, a proofreader's reason, and the text an agent
/// action writes into the page. Anywhere that lands as a plain string, the
/// reader ends up parsing `**`, `` ` `` and `#` by eye.
///
/// Two separate failures are covered here:
///
///  * fenced code was DROPPED on the way into a page, because AppFlowy's
///    markdown decoder ships no parser for it and the unclaimed element was
///    discarded — so "insert this answer" silently lost the snippet it was
///    mostly about;
///  * inline emphasis was written LITERALLY by the agent, because every
///    text-bearing node was built from `Delta()..insert(text)`.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/agent_actions.dart';
import 'package:mario/features/ai/agent_executor.dart';
import 'package:mario/features/ai/ai_markdown.dart';
import 'package:mario/features/ai/ai_markdown_blocks.dart';
import 'package:mario/features/editor/blocks/code_block.dart';
import 'package:mario/features/editor/blocks/math_block.dart';
import 'package:mario/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fenced code survives the trip into a page', () {
    test('a fence becomes a code block, with its language', () {
      final nodes = marioMarkdownToNodes(
        'Here is how:\n\n```dart\nvar x = 1;\n```\n\nThat is all.',
      );

      final code = nodes.where((n) => n.type == CodeBlockKeys.type).toList();
      expect(code, hasLength(1), reason: 'the fence was dropped');
      expect(code.single.attributes[CodeBlockKeys.code], 'var x = 1;');
      expect(code.single.attributes[CodeBlockKeys.language], 'dart');

      // And the prose around it is still there.
      expect(nodes.length, greaterThanOrEqualTo(3));
    });

    test('a fence with no language lands as plaintext', () {
      final nodes = marioMarkdownToNodes('```\nplain\n```');
      final code = nodes.singleWhere((n) => n.type == CodeBlockKeys.type);
      expect(code.attributes[CodeBlockKeys.language], 'plaintext');
      expect(code.attributes[CodeBlockKeys.code], 'plain');
    });

    test('entities inside a fence are unescaped, not doubled', () {
      // The element tree carries `&lt;` / `&amp;`; writing that into the page
      // would show the entity instead of the character.
      final nodes = marioMarkdownToNodes('```\nif (a < b && c) {}\n```');
      final code = nodes.singleWhere((n) => n.type == CodeBlockKeys.type);
      expect(code.attributes[CodeBlockKeys.code], 'if (a < b && c) {}');
    });
  });

  group('callouts survive the trip into a page', () {
    test('a [!TIP] becomes a quote with a bold title', () {
      final nodes = marioMarkdownToNodes(
        '> [!TIP]\n> **How to study:** scan the highlights first.\n\nThen more.',
      );
      final quotes = nodes.where((n) => n.type == afe.QuoteBlockKeys.type);
      expect(quotes, hasLength(1), reason: 'the callout was dropped');
      final delta = quotes.single.delta!;
      expect(
          delta.toPlainText(), 'Tip\nHow to study: scan the highlights first.');
      final ops = delta.whereType<afe.TextInsert>().toList();
      expect(ops.first.text, 'Tip');
      expect(ops.first.attributes?['bold'], isTrue);
      // The paragraph after it is still a paragraph of its own.
      expect(nodes.last.type, afe.ParagraphBlockKeys.type);
    });

    test('every callout kind is titled', () {
      for (final kind in ['NOTE', 'IMPORTANT', 'WARNING', 'CAUTION']) {
        final nodes = marioMarkdownToNodes('> [!$kind]\n> body');
        final quote =
            nodes.singleWhere((n) => n.type == afe.QuoteBlockKeys.type);
        expect(
            quote.delta!.toPlainText().split('\n').first.toUpperCase(), kind);
      }
    });

    test('a plain quote is untouched', () {
      final nodes = marioMarkdownToNodes('> just a quote');
      final quote = nodes.singleWhere((n) => n.type == afe.QuoteBlockKeys.type);
      expect(quote.delta!.toPlainText(), 'just a quote');
    });
  });

  group('display maths survives the trip into a page', () {
    test(r'a $$ block becomes a formula block', () {
      final nodes = marioMarkdownToNodes(
        'Energy:\n\n\$\$\nE = mc^2\n\$\$\n\nThat is all.',
      );
      final math = nodes.where((n) => n.type == MathBlockKeys.type).toList();
      expect(math, hasLength(1), reason: 'the block landed as a paragraph');
      expect(math.single.attributes[MathBlockKeys.formula], 'E = mc^2');
      expect(nodes.length, greaterThanOrEqualTo(3));
    });

    test('a math fence becomes a formula block too', () {
      final nodes = marioMarkdownToNodes('```math\n\\frac{a}{b}\n```');
      final math = nodes.singleWhere((n) => n.type == MathBlockKeys.type);
      expect(math.attributes[MathBlockKeys.formula], r'\frac{a}{b}');
    });

    test(r'a one-line $$ … $$ is a formula as well', () {
      final nodes = marioMarkdownToNodes(r'$$ x^2 $$');
      final math = nodes.singleWhere((n) => n.type == MathBlockKeys.type);
      expect(math.attributes[MathBlockKeys.formula], 'x^2');
    });

    test(r'inline $x$ and a $$ inside a code fence are left alone', () {
      const src = 'Let \$x\$ be small.\n\n```sh\necho \$\$\n\$\$\n```';
      expect(displayMathAsFences(src), src);
      final nodes = marioMarkdownToNodes(src);
      expect(nodes.where((n) => n.type == MathBlockKeys.type), isEmpty);
      final code = nodes.singleWhere((n) => n.type == CodeBlockKeys.type);
      expect(code.attributes[CodeBlockKeys.code], 'echo \$\$\n\$\$');
    });

    test(r'an unclosed $$ is not a formula', () {
      const src = 'start\n\$\$\nno end here';
      expect(displayMathAsFences(src), src);
    });
  });

  group('inline markdown becomes styling, losslessly', () {
    test('emphasis, code and links are attributes, not characters', () {
      final delta =
          marioInlineDelta('the **key** point, `foo()`, [docs](https://x.com)');
      final plain = delta.toPlainText();

      expect(plain, isNot(contains('**')));
      expect(plain, isNot(contains('`')));
      expect(plain, contains('key'));
      expect(plain, contains('foo()'));

      final attrs = [
        for (final op in delta)
          if (op is afe.TextInsert) op.attributes,
      ].whereType<Map<String, dynamic>>();
      expect(attrs.any((a) => a['bold'] == true), isTrue);
      expect(attrs.any((a) => a['code'] == true), isTrue);
      expect(attrs.any((a) => a['href'] == 'https://x.com'), isTrue);
    });

    test('plain text is left exactly as it was', () {
      const s = 'nothing special here';
      expect(marioInlineDelta(s).toPlainText(), s);
    });

    test('multi-line text is never re-blocked, so nothing can be lost', () {
      // Taking the first parsed block of a multi-block string would silently
      // drop the rest. Visible asterisks are a cosmetic problem; a vanished
      // paragraph is a data-loss one.
      const s = '# Title\n\nbody with **bold**\n\n```\ncode\n```';
      expect(marioInlineDelta(s).toPlainText(), s);
    });

    test('an empty string stays empty', () {
      expect(marioInlineDelta('').toPlainText(), isEmpty);
    });
  });

  group('the agent writes styled text into the page', () {
    Future<afe.Node> applyAndRead(AgentAction action) async {
      final editorState = afe.EditorState(document: afe.Document.blank());
      final ok = await AgentExecutor(editorState).apply(action);
      expect(ok, isTrue);
      return editorState.document.root.children.last;
    }

    test('a paragraph action does not leave asterisks in the page', () async {
      final node = await applyAndRead(
        const AgentAction(
          kind: AgentActionKind.paragraph,
          text: 'the **key** point',
        ),
      );
      expect(node.delta!.toPlainText(), 'the key point');
      expect(node.delta!.toPlainText(), isNot(contains('*')));
    });

    test('a heading keeps its level and gains its styling', () async {
      final node = await applyAndRead(
        const AgentAction(
          kind: AgentActionKind.heading,
          level: 3,
          text: 'A `code` heading',
        ),
      );
      expect(node.attributes['level'], 3);
      expect(node.delta!.toPlainText(), 'A code heading');
    });

    test('bullets are styled item by item', () async {
      final editorState = afe.EditorState(document: afe.Document.blank());
      await AgentExecutor(editorState).apply(
        const AgentAction(
          kind: AgentActionKind.bullets,
          items: ['plain one', 'a **bold** one'],
        ),
      );
      final texts = [
        for (final n in editorState.document.root.children)
          if (n.type == 'bulleted_list') n.delta!.toPlainText(),
      ];
      expect(texts, ['plain one', 'a bold one']);
    });

    test('code is left literal — styling it would eat the snippet', () async {
      final node = await applyAndRead(
        const AgentAction(
          kind: AgentActionKind.code,
          language: 'dart',
          // Markdown metacharacters that are ordinary code.
          text: 'a * b, c ** d, `x`',
        ),
      );
      expect(node.attributes[CodeBlockKeys.code], 'a * b, c ** d, `x`');
    });
  });

  group('AiInlineMarkdown', () {
    Future<void> pump(WidgetTester tester, String data) async {
      await tester.pumpWidget(MaterialApp(
        theme: MarioTheme.light(),
        home: Scaffold(body: AiInlineMarkdown(data)),
      ));
      await tester.pump();
    }

    testWidgets('renders emphasis rather than the characters', (tester) async {
      await pump(tester, 'What does `foo()` return, **exactly**?');

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.byType(Text));
      final rendered = text.textSpan!.toPlainText();
      expect(rendered, 'What does foo() return, exactly?');
      expect(rendered, isNot(contains('`')));
      expect(rendered, isNot(contains('**')));
    });

    testWidgets('a plain line skips the span machinery', (tester) async {
      await pump(tester, 'a perfectly ordinary question');

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.data, 'a perfectly ordinary question',
          reason: 'no markdown means no rich text is needed');
    });
  });

  group('the panel renders as a Markdown preview does', () {
    Future<void> pump(WidgetTester tester, String data,
        {double fontSize = 13}) async {
      await tester.pumpWidget(MaterialApp(
        theme: MarioTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiMarkdown(data, fontSize: fontSize),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets(':smile: is an emoji, not punctuation', (tester) async {
      await pump(tester, 'Nice :smile: and :+1:');

      expect(tester.takeException(), isNull);
      expect(find.textContaining('😄'), findsWidgets);
      expect(find.textContaining('👍'), findsWidgets);
      expect(find.textContaining(':smile:'), findsNothing);
    });

    testWidgets('an unknown shortcode is left as typed', (tester) async {
      await pump(tester, 'at :nosuchthing: o\'clock');
      expect(find.textContaining(':nosuchthing:'), findsWidgets);
    });

    testWidgets('--- is a rule with room around it', (tester) async {
      await pump(tester, 'above\n\n---\n\nbelow');

      // flutter_markdown draws an hr as a childless Container with the
      // stylesheet's decoration and nothing else, so that decoration is the
      // whole rule: a box as tall as its (clear) border, painted by a
      // gradient that is opaque only for the two pixels in the middle.
      final rule = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient != null);
      expect(rule, findsOneWidget);
      final height = tester.getSize(rule).height;
      expect(height, greaterThan(2), reason: 'margin above and below');
      expect(height, lessThan(13 * 1.5), reason: 'but under a line of it');
    });

    testWidgets('a level-1 heading is ruled and keeps its emphasis',
        (tester) async {
      await pump(tester, '# The **key** `point`\n\nbody');

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('ai-markdown-h1-rule')), findsOneWidget);
      // The builder replaces the package's rendering of the heading, so the
      // inline runs are set by hand — and must still be there, as text, not
      // as asterisks.
      expect(find.textContaining('The key point'), findsWidgets);
      expect(find.textContaining('**'), findsNothing);
      // Only the top heading is ruled; the rest have no decoration slot.
      await pump(tester, '## second');
      expect(find.byKey(const ValueKey('ai-markdown-h1-rule')), findsNothing);
    });

    testWidgets('list items sit a line apart, paragraphs further',
        (tester) async {
      // The complaint this guards: list items were a line and a half apart,
      // because every block had the paragraph gap after it.
      await pump(tester, '- one\n- two\n\nalpha\n\nbeta');

      double top(String s) =>
          tester.getTopLeft(find.textContaining(s).first).dy;
      final listPitch = top('two') - top('one');
      final paragraphPitch = top('beta') - top('alpha');

      // 13px on a 1.5 line is 19.5px; the floor between blocks is 0.2em.
      expect(listPitch, lessThanOrEqualTo(13 * 1.5 + 13 * 0.2 + 0.5));
      expect(paragraphPitch, greaterThan(listPitch));
    });
  });
}
