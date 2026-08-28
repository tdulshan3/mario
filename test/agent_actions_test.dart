/// The gate between what a model proposes and what touches someone's notes.
///
/// This is the only thing standing between a plausible-looking plan and the
/// user's page, so the tests are mostly about what gets *rejected*. Every
/// rejection here is decidable in Dart without asking a model — a hallucinated
/// block id, a ragged table, a setting outside the allowlist — and a dropped
/// action costs one step, where an action executed on a guess costs notes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/agent_actions.dart';

void main() {
  Map<String, dynamic> plan(List<Map<String, dynamic>> actions,
          {String summary = 'did a thing'}) =>
      {'summary': summary, 'actions': actions};

  group('what it accepts', () {
    test('a paragraph', () {
      final p = parseAgentPlan(plan([
        {'kind': 'paragraph', 'text': 'Mitochondria make ATP.'}
      ]));
      expect(p.actions.single.kind, AgentActionKind.paragraph);
      expect(p.actions.single.text, 'Mitochondria make ATP.');
      expect(p.dropped, 0);
    });

    test('a heading, clamping the level into range', () {
      final p = parseAgentPlan(plan([
        {'kind': 'heading', 'text': 'Cells', 'level': 99}
      ]));
      expect(p.actions.single.level, 6);
    });

    test('lists of every flavour', () {
      final p = parseAgentPlan(plan([
        {'kind': 'bullets', 'items': ['a', 'b']},
        {'kind': 'numbered', 'items': ['one']},
        {'kind': 'todo', 'items': ['revise']},
      ]));
      expect(p.actions.map((a) => a.kind), [
        AgentActionKind.bullets,
        AgentActionKind.numbered,
        AgentActionKind.todo,
      ]);
    });

    test('a code block, defaulting the language', () {
      final p = parseAgentPlan(plan([
        {'kind': 'code', 'text': 'print(1)'}
      ]));
      expect(p.actions.single.language, 'plaintext');
    });

    test('a square table', () {
      final p = parseAgentPlan(plan([
        {
          'kind': 'table',
          'rows': [
            ['Method', 'Cost'],
            ['A', 'low'],
          ],
        }
      ]));
      expect(p.actions.single.rows, hasLength(2));
      expect(p.actions.single.rows.first, ['Method', 'Cost']);
    });

    test('a rename, reduced to one line', () {
      // A title is one line; a paragraph here would name the page something
      // nothing can display.
      final p = parseAgentPlan(plan([
        {'kind': 'rename_page', 'text': 'Cell Biology\nand more'}
      ]));
      expect(p.actions.single.text, 'Cell Biology');
    });

    test('a setting on the allowlist', () {
      final p = parseAgentPlan(plan([
        {'kind': 'setting', 'settingKey': 'theme', 'settingValue': 'dark'}
      ]));
      expect(p.actions.single.settingKey, 'theme');
    });
  });

  group('what it refuses', () {
    test('an invented action kind', () {
      final p = parseAgentPlan(plan([
        {'kind': 'delete_notebook'},
        {'kind': 'send_email', 'text': 'hi'},
      ]));
      expect(p.actions, isEmpty);
      expect(p.dropped, 2);
    });

    test('a setting outside the allowlist', () {
      // The one that matters: an agent that could write an API key would be a
      // way to talk someone's notes into reconfiguring their own backend.
      final p = parseAgentPlan(plan([
        {
          'kind': 'setting',
          'settingKey': 'anthropic_api_key',
          'settingValue': 'sk-ant-stolen',
        },
        {
          'kind': 'setting',
          'settingKey': 'baseUrl',
          'settingValue': 'http://evil.example/v1',
        },
      ]));
      expect(p.actions, isEmpty);
      expect(p.dropped, 2);
    });

    test('empty content', () {
      final p = parseAgentPlan(plan([
        {'kind': 'paragraph', 'text': '   '},
        {'kind': 'heading', 'text': ''},
        {'kind': 'bullets', 'items': <String>[]},
        {'kind': 'code', 'text': ''},
      ]));
      expect(p.actions, isEmpty);
      expect(p.dropped, 4);
    });

    test('a ragged table, which has no safe repair', () {
      // A short row could be missing a leading or a trailing cell, and padding
      // the wrong end shifts every value into the wrong column.
      final p = parseAgentPlan(plan([
        {
          'kind': 'table',
          'rows': [
            ['a', 'b', 'c'],
            ['d', 'e'],
          ],
        }
      ]));
      expect(p.actions, isEmpty);
    });

    test('an absurdly large table', () {
      final p = parseAgentPlan(plan([
        {
          'kind': 'table',
          'rows': [for (var i = 0; i < 500; i++) ['x', 'y']],
        }
      ]));
      expect(p.actions, isEmpty);
    });

    test('a delete or replace with no target', () {
      final p = parseAgentPlan(plan([
        {'kind': 'delete_block'},
        {'kind': 'replace_block', 'text': 'new text'},
      ]));
      expect(p.actions, isEmpty);
    });

    test('a hallucinated block id', () {
      // Acting on an id that does not exist would hit whatever block happens
      // to be there.
      final p = parseAgentPlan(
        plan([
          {'kind': 'delete_block', 'blockId': 'nope99'},
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions, isEmpty);
      expect(p.dropped, 1);
    });

    test('a known block id is accepted', () {
      final p = parseAgentPlan(
        plan([
          {'kind': 'delete_block', 'blockId': 'abc123'},
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions.single.blockId, 'abc123');
    });

    test('an unknown afterBlockId appends rather than dropping the content',
        () {
      // Losing the paragraph entirely would be a worse outcome than putting it
      // at the end.
      final p = parseAgentPlan(
        plan([
          {
            'kind': 'paragraph',
            'text': 'still useful',
            'afterBlockId': 'nope99',
          },
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions.single.afterBlockId, isNull);
      expect(p.actions.single.text, 'still useful');
    });
  });

  group('surviving wrong-typed fields', () {
    test('a level given as a string', () {
      final p = parseAgentPlan(plan([
        {'kind': 'heading', 'text': 'x', 'level': '3'}
      ]));
      expect(p.actions.single.level, 3);
    });

    test('items given as a bare string', () {
      final p = parseAgentPlan(plan([
        {'kind': 'bullets', 'items': 'just one'}
      ]));
      expect(p.actions.single.items, ['just one']);
    });

    test('junk entries never take the good ones down', () {
      final p = parseAgentPlan(plan([
        {'kind': 'nonsense'},
        {'kind': 'paragraph', 'text': 'keep me'},
        <String, dynamic>{},
      ]));
      expect(p.actions, hasLength(1));
      expect(p.actions.single.text, 'keep me');
      expect(p.dropped, 2);
    });

    test('an entirely malformed reply yields an empty plan, not a crash', () {
      expect(parseAgentPlan(const {}).isEmpty, isTrue);
      expect(parseAgentPlan({'actions': 'nope'}).isEmpty, isTrue);
    });
  });

  group('what the UI needs to tell the user', () {
    test('destructive actions are counted apart from additions', () {
      final p = parseAgentPlan(
        plan([
          {'kind': 'paragraph', 'text': 'added'},
          {'kind': 'delete_block', 'blockId': 'a'},
          {'kind': 'replace_block', 'blockId': 'b', 'text': 'rewritten'},
        ]),
        knownBlockIds: {'a', 'b'},
      );
      expect(p.actions, hasLength(3));
      expect(p.destructiveCount, 2);
    });

    test('every action can describe itself', () {
      final p = parseAgentPlan(plan([
        {'kind': 'table', 'rows': [['a', 'b'], ['c', 'd']]},
        {'kind': 'code', 'text': 'x', 'language': 'python'},
        {'kind': 'rename_page', 'text': 'New title'},
      ]));
      expect(p.actions[0].summary, contains('2x2'));
      expect(p.actions[1].summary, contains('python'));
      expect(p.actions[2].summary, contains('New title'));
    });

    test('the summary survives', () {
      final p = parseAgentPlan(plan(
        [{'kind': 'paragraph', 'text': 'x'}],
        summary: 'Added a comparison table',
      ));
      expect(p.summary, 'Added a comparison table');
    });
  });
}
