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
}
