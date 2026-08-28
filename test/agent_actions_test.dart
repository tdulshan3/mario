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

  group('the bug that made a plan come back as nothing but headings', () {
    // A blockId on an insert almost always means "put it here" — the model
    // reaching for the only id field it can see. Treating it as a *target*
    // dropped the whole action, so a plan survived only in the few actions
    // that happened to carry no id at all.

    test('an insert carrying a stray blockId is kept, not dropped', () {
      final p = parseAgentPlan(
        plan([
          {'kind': 'paragraph', 'text': 'body text', 'blockId': 'abc123'},
          {'kind': 'code', 'text': 'print(1)', 'blockId': 'abc123'},
          {'kind': 'heading', 'text': 'A heading'},
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions, hasLength(3));
      expect(p.dropped, 0);
    });

    test('that stray id is read as placement, which is what it meant', () {
      final p = parseAgentPlan(
        plan([
          {'kind': 'paragraph', 'text': 'body', 'blockId': 'abc123'},
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions.single.afterBlockId, 'abc123');
      expect(p.actions.single.blockId, isNull);
    });

    test('an unknown stray id appends rather than dropping the content', () {
      final p = parseAgentPlan(
        plan([
          {'kind': 'paragraph', 'text': 'body', 'blockId': 'invented'},
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions, hasLength(1));
      expect(p.actions.single.afterBlockId, isNull);
    });

    test('a real target is still required where one is needed', () {
      // The rule has to stay strict for the kinds that act *on* a block.
      final p = parseAgentPlan(
        plan([
          {'kind': 'delete_block', 'blockId': 'invented'},
          {'kind': 'replace_block', 'blockId': 'invented', 'text': 'x'},
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions, isEmpty);
    });
  });

  group('field aliases, since the schema is advisory on many backends', () {
    test('body text under content, body or value', () {
      for (final key in ['content', 'body', 'value']) {
        final p = parseAgentPlan(plan([
          {'kind': 'paragraph', key: 'the actual text'}
        ]));
        expect(p.actions.single.text, 'the actual text', reason: key);
      }
    });

    test('list items under list or bullets', () {
      for (final key in ['list', 'bullets']) {
        final p = parseAgentPlan(plan([
          {'kind': 'bullets', key: ['a', 'b']}
        ]));
        expect(p.actions.single.items, ['a', 'b'], reason: key);
      }
    });

    test('snake_case id fields', () {
      final p = parseAgentPlan(
        plan([
          {'kind': 'delete_block', 'block_id': 'abc123'},
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions.single.blockId, 'abc123');
    });

    test('a paragraph whose body arrived as a list is joined, not lost', () {
      final p = parseAgentPlan(plan([
        {'kind': 'paragraph', 'items': ['line one', 'line two']}
      ]));
      expect(p.actions.single.text, 'line one\nline two');
    });

    test('a code block whose body arrived as lines is joined', () {
      final p = parseAgentPlan(plan([
        {'kind': 'code', 'items': ['def f():', '    return 1'],
         'language': 'python'}
      ]));
      expect(p.actions.single.text, 'def f():\n    return 1');
      expect(p.actions.single.language, 'python');
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
