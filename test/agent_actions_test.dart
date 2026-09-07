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
        {
          'kind': 'bullets',
          'items': ['a', 'b']
        },
        {
          'kind': 'numbered',
          'items': ['one']
        },
        {
          'kind': 'todo',
          'items': ['revise']
        },
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

    test('a math block loses Markdown delimiters before execution', () {
      final p = parseAgentPlan(plan([
        {'kind': 'math', 'text': r'$$E = mc^2$$'}
      ]));
      expect(p.actions.single.text, r'E = mc^2');
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
          'rows': [
            for (var i = 0; i < 500; i++) ['x', 'y']
          ],
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
          {
            'kind': 'bullets',
            key: ['a', 'b']
          }
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

    test('rewrite replacement text under common replacement field names', () {
      for (final key in [
        'replacement',
        'replacementText',
        'replacement_text',
        'newText',
        'new_text',
        'replacementContent',
        'replacement_content',
        'newContent',
        'new_content',
      ]) {
        final p = parseAgentPlan(
          plan([
            {
              'kind': 'replace_block',
              'blockId': 'abc123',
              key: 'the rewritten text',
            },
          ]),
          knownBlockIds: {'abc123'},
        );
        expect(p.actions.single.text, 'the rewritten text', reason: key);
      }
    });

    test('rewrite replacement can be wrapped in an object', () {
      final p = parseAgentPlan(
        plan([
          {
            'kind': 'replace_block',
            'blockId': 'abc123',
            'replacement': {'text': 'the rewritten text'},
          },
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions.single.text, 'the rewritten text');
    });

    test('a blank schema text does not hide populated replacement text', () {
      final p = parseAgentPlan(
        plan([
          {
            'kind': 'replace_block',
            'blockId': 'abc123',
            'text': '',
            'replacement': 'the rewritten text',
          },
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions.single.text, 'the rewritten text');
    });

    test('a paragraph whose body arrived as a list is joined, not lost', () {
      final p = parseAgentPlan(plan([
        {
          'kind': 'paragraph',
          'items': ['line one', 'line two']
        }
      ]));
      expect(p.actions.single.text, 'line one\nline two');
    });

    test('a code block whose body arrived as lines is joined', () {
      final p = parseAgentPlan(plan([
        {
          'kind': 'code',
          'items': ['def f():', '    return 1'],
          'language': 'python'
        }
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
    test('a complete HTML artifact is a first-class action', () {
      final p = parseAgentPlan(plan([
        {
          'kind': 'html',
          'text': '<!doctype html><html><body>Hi</body></html>',
        },
      ]));

      expect(p.actions.single.kind, AgentActionKind.htmlArtifact);
      expect(p.actions.single.summary, contains('HTML artifact'));
    });

    test('plain prose mislabeled as HTML is rejected', () {
      final p = parseAgentPlan(plan([
        {'kind': 'html', 'text': 'this is not markup'},
      ]));
      expect(p.actions, isEmpty);
      expect(p.rejectionSummary.single, contains('no HTML'));
    });

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
        {
          'kind': 'table',
          'rows': [
            ['a', 'b'],
            ['c', 'd']
          ]
        },
        {'kind': 'code', 'text': 'x', 'language': 'python'},
        {'kind': 'rename_page', 'text': 'New title'},
      ]));
      expect(p.actions[0].summary, contains('2x2'));
      expect(p.actions[1].summary, contains('python'));
      expect(p.actions[2].summary, contains('New title'));
    });

    test('pages and sections can describe themselves', () {
      final p = parseAgentPlan(plan([
        {'kind': 'create_page', 'text': 'Krebs cycle'},
        {'kind': 'create_page', 'text': 'Glycolysis', 'section': 'Cells'},
        {'kind': 'create_section', 'text': 'Genetics'},
        {'kind': 'rename_section', 'text': 'Cell biology'},
      ]));
      expect(p.actions, hasLength(4));
      expect(p.actions[0].summary, 'Created page "Krebs cycle"');
      expect(p.actions[1].summary, 'Created page "Glycolysis" in Cells');
      expect(p.actions[2].summary, 'Created section "Genetics"');
      expect(p.actions[3].summary, 'Renamed this section to "Cell biology"');
      // None of these touches the user's existing words.
      expect(p.destructiveCount, 0);
    });

    test('the summary survives', () {
      final p = parseAgentPlan(plan(
        [
          {'kind': 'paragraph', 'text': 'x'}
        ],
        summary: 'Added a comparison table',
      ));
      expect(p.summary, 'Added a comparison table');
    });
  });

  group('the shapes a model actually writes for a "To do" section', () {
    // Reconstructed from a real failure. The instruction was "identify the core
    // task and action required to complete the To do section"; the panel showed
    // one heading and "2 proposed change(s) were rejected as unsafe". Both
    // rejections were the same rule: a list whose entries did not arrive as a
    // flat array of plain strings had no recovery at all, where a paragraph and
    // a code block both did.

    test('a to-do whose single entry arrived as text', () {
      // One task is a string, not an array of one. This is the exact shape
      // that produced the user's report.
      final p = parseAgentPlan(plan([
        {'kind': 'heading', 'text': 'To do'},
        {'kind': 'todo', 'text': 'Draft the summary section'},
        {'kind': 'bullets', 'text': 'Send it to Sam'},
      ]));
      expect(p.actions, hasLength(3));
      expect(p.dropped, 0);
      expect(p.actions[1].items, ['Draft the summary section']);
    });

    test('list entries delivered as objects, the way a to-do really looks', () {
      // A to-do has a done flag, so an object per entry is the natural echo of
      // any note app's own JSON.
      final p = parseAgentPlan(plan([
        {
          'kind': 'todo',
          'items': [
            {'text': 'Draft it', 'checked': false},
            {'text': 'Send it', 'checked': false},
          ],
        }
      ]));
      expect(p.actions.single.items, ['Draft it', 'Send it']);
    });

    test('a multi-line body becomes one entry per line', () {
      final p = parseAgentPlan(plan([
        {'kind': 'todo', 'text': '- Draft it\n- Review it\n- Send it'}
      ]));
      expect(p.actions.single.items, ['Draft it', 'Review it', 'Send it']);
    });

    test('a numbered body loses its numbers, not its entries', () {
      final p = parseAgentPlan(plan([
        {'kind': 'numbered', 'text': '1. First\n2. Second'}
      ]));
      expect(p.actions.single.items, ['First', 'Second']);
    });

    test('a genuinely empty list is still dropped, with a reason', () {
      final p = parseAgentPlan(plan([
        {'kind': 'todo', 'items': <String>[], 'text': '  '}
      ]));
      expect(p.actions, isEmpty);
      expect(p.rejected.single.reason, contains('no entries'));
    });
  });

  group('the names a model reaches for instead of ours', () {
    // The schema lists sixteen names, but on a backend without strict decoding
    // the schema is advice. A model that has seen AppFlowy or Notion JSON
    // writes what it saw — and this app's own blocks are called
    // bulleted_list, numbered_list and todo_list.

    test('AppFlowy and Notion list names', () {
      for (final entry in {
        'todo_list': AgentActionKind.todo,
        'to_do': AgentActionKind.todo,
        'checklist': AgentActionKind.todo,
        'checkbox': AgentActionKind.todo,
        'task': AgentActionKind.todo,
        'bulleted_list': AgentActionKind.bullets,
        'bullet_list': AgentActionKind.bullets,
        'unordered_list': AgentActionKind.bullets,
        'numbered_list': AgentActionKind.numbered,
        'ordered_list': AgentActionKind.numbered,
      }.entries) {
        final p = parseAgentPlan(plan([
          {
            'kind': entry.key,
            'items': ['a']
          }
        ]));
        expect(p.actions.single.kind, entry.value, reason: entry.key);
      }
    });

    test('why the failure looked like "only headings"', () {
      // heading and paragraph are spelled the same in both vocabularies, so a
      // model using the other names loses precisely its lists and keeps its
      // headings — which is what the user saw.
      final p = parseAgentPlan(plan([
        {'kind': 'heading', 'text': 'To do'},
        {
          'kind': 'todo_list',
          'items': ['Draft it']
        },
        {
          'kind': 'bulleted_list',
          'items': ['Send it']
        },
      ]));
      expect(p.actions, hasLength(3));
      expect(p.dropped, 0);
    });

    test('markdown heading names, carrying their own level', () {
      final p = parseAgentPlan(plan([
        {'kind': 'h3', 'text': 'Method'}
      ]));
      expect(p.actions.single.kind, AgentActionKind.heading);
    });

    test('the discriminator itself under type, action or op', () {
      for (final key in ['type', 'action', 'op']) {
        final p = parseAgentPlan(plan([
          {key: 'paragraph', 'text': 'body'}
        ]));
        expect(p.actions.single.kind, AgentActionKind.paragraph, reason: key);
      }
    });

    test('a name that is genuinely not ours is still refused', () {
      final p = parseAgentPlan(plan([
        {'kind': 'delete_notebook'},
        {'kind': 'send_email', 'text': 'hi'},
      ]));
      expect(p.actions, isEmpty);
      expect(p.dropped, 2);
    });

    test('"title" stays unmapped, because guessing it would be worse', () {
      // It is at least as likely to mean the page title, and turning an
      // intended rename into an inserted heading is a wrong edit, not a
      // missing one.
      final p = parseAgentPlan(plan([
        {'kind': 'title', 'text': 'Cell Biology'}
      ]));
      expect(p.actions, isEmpty);
    });
  });

  group('ids as the model copies them back', () {
    // The prompt prints every block as "[id:ab12cd]", so a model reaching for
    // an id copies the decoration with it. Stripping what the prompt itself
    // added is not a guess.

    test('the bracketed form the prompt prints', () {
      final p = parseAgentPlan(
        plan([
          {'kind': 'delete_block', 'blockId': '[id:abc123]'},
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions.single.blockId, 'abc123');
    });

    test('a bare id: prefix, and trailing punctuation', () {
      for (final written in ['id:abc123', 'abc123.', '"abc123"', ' abc123 ']) {
        final p = parseAgentPlan(
          plan([
            {'kind': 'delete_block', 'blockId': written},
          ]),
          knownBlockIds: {'abc123'},
        );
        expect(p.actions.single.blockId, 'abc123', reason: written);
      }
    });

    test('a case-flipped id resolves when only one block could be meant', () {
      final p = parseAgentPlan(
        plan([
          {'kind': 'delete_block', 'blockId': 'ABC123'},
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions.single.blockId, 'abc123');
    });

    test('an ambiguous case-flip is refused, not guessed', () {
      // nanoid is case-sensitive, so two live blocks really can differ only by
      // case. Picking one would be the wrong-block edit this all guards.
      final p = parseAgentPlan(
        plan([
          {'kind': 'delete_block', 'blockId': 'ABC123'},
        ]),
        knownBlockIds: {'abc123', 'aBc123'},
      );
      expect(p.actions, isEmpty);
    });

    test('a hallucinated id is still refused', () {
      final p = parseAgentPlan(
        plan([
          {'kind': 'delete_block', 'blockId': '[id:nope99]'},
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions, isEmpty);
      expect(p.rejected.single.reason, contains('not on this page'));
    });
  });

  group('a rewrite whose replacement arrived as a list', () {
    test('is joined rather than dropped', () {
      final p = parseAgentPlan(
        plan([
          {
            'kind': 'replace_block',
            'blockId': 'abc123',
            'items': ['Core task: finish the draft'],
          },
        ]),
        knownBlockIds: {'abc123'},
      );
      expect(p.actions.single.text, 'Core task: finish the draft');
    });

    test('a rewrite with no target is still refused', () {
      final p = parseAgentPlan(plan([
        {'kind': 'replace_block', 'text': 'new text'}
      ]));
      expect(p.actions, isEmpty);
      expect(p.rejected.single.reason, contains('no block to rewrite'));
    });
  });

  group('headings start below the page title', () {
    test('an omitted level is 2, not 1', () {
      // level is optional, and defaulting it to 1 gave the page a second
      // title competing with its real one — contradicting the house style the
      // same prompt hands the model.
      final p = parseAgentPlan(plan([
        {'kind': 'heading', 'text': 'Method'}
      ]));
      expect(p.actions.single.level, 2);
    });

    test('level 1 is clamped up', () {
      final p = parseAgentPlan(plan([
        {'kind': 'heading', 'text': 'Method', 'level': 1}
      ]));
      expect(p.actions.single.level, 2);
    });

    test('the schema forbids level 1 too', () {
      final level = ((agentPlanSchema['properties'] as Map)['actions']
          as Map)['items'] as Map;
      final props = level['properties'] as Map;
      expect((props['level'] as Map)['minimum'], 2);
    });
  });

  group('move_block, which the prompt promised and the schema forbade', () {
    test('is in the schema the model is handed', () {
      // The system prompt says "use move_block to put a picture beside the
      // text that discusses it". On a strict backend the enum was the last
      // word, so that instruction could never be followed.
      final items = ((agentPlanSchema['properties'] as Map)['actions']
          as Map)['items'] as Map;
      final kinds =
          ((items['properties'] as Map)['kind'] as Map)['enum'] as List;
      expect(kinds, contains('move_block'));
    });

    test('the schema offers exactly the kinds the parser accepts', () {
      // Anything the parser knows but the schema omits is an action a strict
      // backend can never send, however plainly the prompt asks for it — and
      // anything the schema offers but the parser refuses is an action the
      // model will be dropped for using. move_block was the first kind; this
      // is what stops it being the last.
      final items = ((agentPlanSchema['properties'] as Map)['actions']
          as Map)['items'] as Map;
      final offered =
          (((items['properties'] as Map)['kind'] as Map)['enum'] as List)
              .cast<String>()
              .toSet();

      final accepted = <String>{};
      for (final name in offered) {
        final p = parseAgentPlan({
          'summary': '',
          'actions': [
            // Enough fields that only an unknown *kind* can reject it.
            {
              'kind': name,
              'text': '<p>x</p>',
              'items': ['x'],
              'rows': [
                ['a']
              ],
              'blockId': 'abc123',
              'settingKey': 'theme',
              'settingValue': 'dark',
            }
          ],
        }, knownBlockIds: {
          'abc123'
        });
        if (p.actions.isNotEmpty) accepted.add(name);
      }
      expect(accepted, offered,
          reason: 'a kind in the schema that the parser refuses is a trap');

      // And the other direction: every member of the enum has a wire name in
      // the schema, so none is unreachable.
      expect(offered, hasLength(AgentActionKind.values.length));
    });
  });

  group('every rejection says why', () {
    test('a reason accompanies each dropped action', () {
      final p = parseAgentPlan(plan([
        {'kind': 'nonsense'},
        {'kind': 'heading', 'text': ''},
        {
          'kind': 'setting',
          'settingKey': 'anthropic_api_key',
          'settingValue': 'sk-x'
        },
      ]));
      expect(p.rejected, hasLength(3));
      expect(p.dropped, 3, reason: 'the count derives from the reasons');
      for (final r in p.rejected) {
        expect(r.reason, isNotEmpty);
      }
    });

    test('the one that really is about safety says so', () {
      final p = parseAgentPlan(plan([
        {'kind': 'setting', 'settingKey': 'baseUrl', 'settingValue': 'x'},
      ]));
      expect(p.rejected.single.reason, contains('not a setting'));
    });

    test('actions that are not objects are counted, not vanished', () {
      // "actions": ["Add a todo list"] used to produce an empty plan with
      // dropped == 0, and the user was told the model proposed nothing.
      final p = parseAgentPlan({
        'summary': 'x',
        'actions': ['Add a todo list', 42],
      });
      expect(p.actions, isEmpty);
      expect(p.dropped, 2);
      expect(p.rejected.first.reason, contains('not an action object'));
    });

    test('repeated reasons are counted rather than repeated', () {
      final p = parseAgentPlan(plan([
        {'kind': 'nope1'},
        {'kind': 'nope2'},
      ]));
      expect(p.rejectionSummary.single, contains('x2'));
    });
  });

  group('pages and sections', () {
    test('a new page keeps its title, section and body apart', () {
      final p = parseAgentPlan(plan([
        {
          'kind': 'create_page',
          'text': 'Krebs cycle',
          'section': 'Cells',
          'content': '## Steps\n\n- one\n- two',
        },
      ]));
      final a = p.actions.single;
      expect(a.kind, AgentActionKind.createPage);
      expect(a.text, 'Krebs cycle');
      expect(a.section, 'Cells');
      expect(a.content, '## Steps\n\n- one\n- two');
    });

    test('a page whose only field is a body is not titled with that body', () {
      // `text` falls back to `content` for every other kind; a page must not
      // inherit that, or its title would be its first paragraph.
      final p = parseAgentPlan(plan([
        {'kind': 'create_page', 'content': 'A whole paragraph of notes.'},
      ]));
      expect(p.actions, isEmpty);
      expect(p.rejected.single.reason, contains('no title'));
    });

    test('a title is one line', () {
      final p = parseAgentPlan(plan([
        {'kind': 'create_page', 'title': 'Krebs cycle\nand more'},
        {'kind': 'create_section', 'name': 'Genetics\nagain'},
      ]));
      expect(p.actions[0].text, 'Krebs cycle');
      expect(p.actions[1].text, 'Genetics');
    });

    test('the obvious synonyms land', () {
      final p = parseAgentPlan(plan([
        {'kind': 'new_page', 'text': 'A'},
        {'kind': 'add_section', 'text': 'B'},
        {'kind': 'rename_section', 'new_name': 'C', 'section_name': 'Old'},
      ]));
      expect(p.actions.map((a) => a.kind), [
        AgentActionKind.createPage,
        AgentActionKind.createSection,
        AgentActionKind.renameSection,
      ]);
      expect(p.actions[2].text, 'C');
      expect(p.actions[2].section, 'Old');
    });

    test('an empty name is refused, with a reason', () {
      final p = parseAgentPlan(plan([
        {'kind': 'create_section'},
        {'kind': 'rename_section', 'text': '   '},
      ]));
      expect(p.actions, isEmpty);
      expect(p.rejected[0].reason, contains('no name'));
      expect(p.rejected[1].reason, contains('no new name'));
    });
  });

  group('the tools', () {
    test('reads, listings and searches come back to the model', () {
      expect(AgentActionKind.readPage.observes, isTrue);
      expect(AgentActionKind.searchNotes.observes, isTrue);
      expect(AgentActionKind.webSearch.observes, isTrue);
      expect(AgentActionKind.paragraph.observes, isFalse);
      // Writes are what a preview guards; a read, a question or a move to
      // another page changes nothing.
      expect(AgentActionKind.paragraph.isWrite, isTrue);
      expect(AgentActionKind.writePage.isWrite, isTrue);
      expect(AgentActionKind.readPage.isWrite, isFalse);
      expect(AgentActionKind.askUser.isWrite, isFalse);
      expect(AgentActionKind.openPage.isWrite, isFalse);
    });

    test('each tool parses with its arguments', () {
      final p = parseAgentPlan(plan([
        {'kind': 'markdown', 'text': '## Steps\n\n- one'},
        {
          'kind': 'write_page',
          'page': 'Krebs cycle',
          'text': 'more',
          'mode': 'overwrite',
        },
        {'kind': 'read_page', 'title': 'Glycolysis'},
        {'kind': 'list_notebooks'},
        {'kind': 'list_pages', 'notebook': 'Biology', 'section': 'Cells'},
        {'kind': 'search_notes', 'query': 'enzyme'},
        {'kind': 'web_search', 'q': 'Krebs cycle steps'},
        {'kind': 'create_notebook', 'name': 'Chemistry'},
        {'kind': 'open_page', 'page': 'Glycolysis'},
        {'kind': 'ask_user', 'question': 'Which section?'},
      ]));
      expect(p.rejected, isEmpty);
      final a = p.actions;
      expect(a[0].kind, AgentActionKind.markdown);
      expect(a[0].text, '## Steps\n\n- one');
      expect(a[1].kind, AgentActionKind.writePage);
      expect(a[1].page, 'Krebs cycle');
      expect(a[1].mode, 'replace');
      expect(a[1].isDestructive, isTrue, reason: 'replacing a body removes');
      expect(a[2].page, 'Glycolysis');
      expect(a[3].kind, AgentActionKind.listNotebooks);
      expect(a[4].notebook, 'Biology');
      expect(a[4].section, 'Cells');
      expect(a[5].text, 'enzyme');
      expect(a[6].text, 'Krebs cycle steps');
      expect(a[7].text, 'Chemistry');
      expect(a[8].kind, AgentActionKind.openPage);
      expect(a[9].text, 'Which section?');
    });

    test('a rewrite to nothing is a delete; a rewrite with nothing is refused',
        () {
      // "Remove the HTML tags" on a block that is only `</div>` comes back
      // as replace_block with text "" — the model means "gone".
      final p = parseAgentPlan(
          plan([
            {'kind': 'replace_block', 'blockId': 'a', 'text': ''},
            {'kind': 'replace_block', 'blockId': 'b', 'new_text': '   '},
            {'kind': 'replace_block', 'blockId': 'c'},
          ]),
          knownBlockIds: {'a', 'b', 'c'});
      expect(p.actions.map((a) => a.kind), [
        AgentActionKind.deleteBlock,
        AgentActionKind.deleteBlock,
      ]);
      expect(p.actions.map((a) => a.blockId), ['a', 'b']);
      expect(p.rejected.single.reason, contains('no replacement text'));
    });

    test('a write without a page means the current one, appended', () {
      final p = parseAgentPlan(plan([
        {'kind': 'write_page', 'text': 'x'},
      ]));
      expect(p.actions.single.page, isNull);
      expect(p.actions.single.mode, 'append');
      expect(p.actions.single.isDestructive, isFalse);
    });

    test('an empty search, read or question is refused', () {
      final p = parseAgentPlan(plan([
        {'kind': 'search_notes'},
        {'kind': 'read_page'},
        {'kind': 'ask_user', 'text': ' '},
        {'kind': 'markdown'},
      ]));
      expect(p.actions, isEmpty);
      expect(p.rejected, hasLength(4));
    });

    test('the synonyms a model reaches for land on the tool', () {
      final p = parseAgentPlan(plan([
        {'kind': 'search', 'text': 'x'},
        {'kind': 'navigate', 'page': 'P'},
        {'kind': 'insert_markdown', 'text': 'y'},
        {'kind': 'clarify', 'text': 'z?'},
      ]));
      expect(p.actions.map((a) => a.kind), [
        AgentActionKind.searchNotes,
        AgentActionKind.openPage,
        AgentActionKind.markdown,
        AgentActionKind.askUser,
      ]);
    });

    test('done and follow-ups ride on the plan', () {
      final p = parseAgentPlan({
        'summary': 's',
        'actions': [
          {'kind': 'read_page', 'page': 'P'},
        ],
        'done': false,
        'followUps': ['Add a quiz', '', 'Split it', 'Three', 'Four'],
      });
      expect(p.done, isFalse);
      expect(p.followUps, ['Add a quiz', 'Split it', 'Three']);
      // Omitted means finished, which is what every earlier plan meant.
      expect(parseAgentPlan(plan([])).done, isTrue);
    });

    test('every tool can describe itself', () {
      final p = parseAgentPlan(plan([
        {'kind': 'read_page', 'page': 'Krebs cycle'},
        {'kind': 'write_page', 'page': 'Krebs cycle', 'text': 'x'},
        {'kind': 'search_notes', 'text': 'enzyme'},
        {'kind': 'ask_user', 'text': 'Which one?'},
        {'kind': 'markdown', 'text': 'a\nb\n\nc'},
      ]));
      expect(p.actions[0].summary, 'Read page "Krebs cycle"');
      expect(p.actions[1].summary, 'Wrote into page "Krebs cycle"');
      expect(p.actions[2].summary, 'Searched the notes for "enzyme"');
      expect(p.actions[3].summary, 'Asked: Which one?');
      expect(p.actions[4].summary, 'Added 3 line(s)');
    });
  });
}
