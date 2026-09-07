/// The agent works in turns: it may ask to see something, and what it saw
/// decides the next step.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider.dart';
import 'package:mario/core/services/ai/llm_service.dart';
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/core/services/ai/web_search_service.dart';
import 'package:mario/features/ai/agent_actions.dart';
import 'package:mario/features/ai/agent_task.dart';
import 'package:mario/features/ai/ai_progress.dart';
import 'package:mario/features/ai/note_context.dart';

void main() {
  const note = NoteText(
    title: 'Page',
    blocks: [
      NoteBlock(nodeId: 'a', path: [0], type: 'paragraph', text: 'Original'),
    ],
  );

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 500 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(condition(), isTrue);
  }

  Future<AgentOutcome> outcomeOf(AiRun run) async {
    await until(() => run.value.status != AiRunStatus.running);
    expect(run.value.status, AiRunStatus.done, reason: run.value.error);
    return run.value.result as AgentOutcome;
  }

  test('a read comes back to the model, and the next turn uses it', () async {
    final llm = _TurnLlm([
      {
        'summary': 'Look first',
        'actions': [
          {'kind': 'read_page', 'page': 'Krebs cycle'},
        ],
        'done': false,
      },
      {
        'summary': 'Wrote the summary',
        'actions': [
          {'kind': 'paragraph', 'text': 'Summary of Krebs'},
        ],
        'done': true,
        'followUps': ['Add a quiz for this page'],
      },
    ]);
    final performed = <AgentActionKind>[];
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Summarise the Krebs cycle page here',
      note: note,
      useWeb: false,
      onPlanned: (_) async => true,
      applyAction: (a) async {
        performed.add(a.kind);
        if (a.kind == AgentActionKind.readPage) {
          return const AgentActionResult.ok(
              'Page "Krebs cycle"\n\nThe cycle has eight steps.');
        }
        return const AgentActionResult.ok();
      },
    );

    final outcome = await outcomeOf(run);
    expect(llm.requests, hasLength(2));
    // The second request carries the first plan, as the model wrote it, and
    // what the read returned.
    final second = llm.requests[1].messages;
    expect(second[second.length - 2].role, LlmRole.assistant);
    expect(second[second.length - 2].content, contains('read_page'));
    expect(second.last.role, LlmRole.user);
    expect(second.last.content, contains('eight steps'));
    expect(performed, [AgentActionKind.readPage, AgentActionKind.paragraph]);
    expect(outcome.turns, 2);
    expect(outcome.followUps, ['Add a quiz for this page']);
    expect(outcome.applied, ['Read page "Krebs cycle"', 'Added a paragraph']);
    expect(outcome.summary, 'Wrote the summary');
    run.dispose();
  });

  test('a finished plan with no reads is one turn, as before', () async {
    final llm = _TurnLlm([
      {
        'summary': 'Added',
        'actions': [
          {'kind': 'paragraph', 'text': 'x'},
        ],
      },
    ]);
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Add a line',
      note: note,
      useWeb: false,
      onPlanned: (_) async => true,
      applyAction: (_) async => const AgentActionResult.ok(),
    );
    final outcome = await outcomeOf(run);
    expect(llm.requests, hasLength(1));
    expect(outcome.turns, 1);
    run.dispose();
  });

  test('a question stops the run and is kept for the reply', () async {
    final llm = _TurnLlm([
      {
        'summary': 'Need to know',
        'actions': [
          {'kind': 'ask_user', 'text': 'Which section?'},
          {'kind': 'paragraph', 'text': 'never'},
        ],
        'done': false,
      },
    ]);
    final performed = <AgentActionKind>[];
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Make a page',
      note: note,
      useWeb: false,
      onPlanned: (_) async => true,
      applyAction: (a) async {
        performed.add(a.kind);
        return const AgentActionResult.ok();
      },
    );
    final outcome = await outcomeOf(run);
    expect(performed, [AgentActionKind.askUser],
        reason: 'nothing runs after a question');
    expect(outcome.question, 'Which section?');
    expect(llm.requests, hasLength(1), reason: 'no turn without the answer');
    run.dispose();
  });

  test('opening a page is the last thing a run does', () async {
    final llm = _TurnLlm([
      {
        'summary': 'Go there',
        'actions': [
          {'kind': 'open_page', 'page': 'Other'},
          {'kind': 'paragraph', 'text': 'never'},
        ],
      },
    ]);
    final performed = <AgentActionKind>[];
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Open the other page',
      note: note,
      useWeb: false,
      onPlanned: (_) async => true,
      applyAction: (a) async {
        performed.add(a.kind);
        return const AgentActionResult.ok();
      },
    );
    await outcomeOf(run);
    expect(performed, [AgentActionKind.openPage]);
    run.dispose();
  });

  test('a failed tool tells the model why, and the loop goes on', () async {
    final llm = _TurnLlm([
      {
        'summary': 'Read it',
        'actions': [
          {'kind': 'read_page', 'page': 'Nope'},
        ],
        'done': false,
      },
      {
        'summary': 'Did without',
        'actions': [
          {'kind': 'paragraph', 'text': 'x'},
        ],
      },
    ]);
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Use the Nope page',
      note: note,
      useWeb: false,
      onPlanned: (_) async => true,
      applyAction: (a) async => a.kind == AgentActionKind.readPage
          ? const AgentActionResult.failed('No page called "Nope".')
          : const AgentActionResult.ok(),
    );
    final outcome = await outcomeOf(run);
    expect(llm.requests[1].messages.last.content, contains('No page called'));
    expect(outcome.failed, 1);
    expect(outcome.applied, ['Added a paragraph']);
    run.dispose();
  });

  test('a plan Mario refuses goes back to the model to fix', () async {
    final llm = _TurnLlm([
      {
        'summary': 'Strip the tags',
        'actions': [
          // No block to rewrite: refused by the validator.
          {'kind': 'replace_block', 'text': 'x'},
        ],
      },
      {
        'summary': 'Removed the tag line',
        'actions': [
          {'kind': 'delete_block', 'blockId': 'a'},
        ],
      },
    ]);
    final performed = <AgentActionKind>[];
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Remove the HTML tags',
      note: note,
      useWeb: false,
      onPlanned: (_) async => true,
      applyAction: (a) async {
        performed.add(a.kind);
        return const AgentActionResult.ok();
      },
    );
    final outcome = await outcomeOf(run);
    expect(llm.requests, hasLength(2));
    expect(
        llm.requests[1].messages.last.content, contains('no block to rewrite'));
    expect(performed, [AgentActionKind.deleteBlock]);
    expect(outcome.applied, ['Deleted a block']);
    expect(outcome.dropped, 1, reason: 'the refusal is still reported');
    run.dispose();
  });

  test('a step that fails on the page gets one more try', () async {
    final llm = _TurnLlm([
      {
        'summary': 'Rewrite it',
        'actions': [
          {'kind': 'replace_block', 'blockId': 'a', 'text': 'new'},
        ],
      },
      {
        'summary': 'Added it instead',
        'actions': [
          {'kind': 'paragraph', 'text': 'new'},
        ],
      },
    ]);
    var attempt = 0;
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Rewrite the first block',
      note: note,
      useWeb: false,
      onPlanned: (_) async => true,
      applyAction: (a) async {
        attempt++;
        return attempt == 1
            ? const AgentActionResult.failed('block a is not on this page')
            : const AgentActionResult.ok();
      },
    );
    final outcome = await outcomeOf(run);
    expect(llm.requests, hasLength(2));
    expect(llm.requests[1].messages.last.content, contains('not on this page'));
    expect(outcome.applied, ['Added a paragraph']);
    expect(outcome.failed, 1);
    run.dispose();
  });

  test('refusals are not retried for ever', () async {
    final llm = _TurnLlm([
      {
        'summary': 'Try',
        'actions': [
          {'kind': 'replace_block', 'text': 'x'},
        ],
      },
    ]);
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Do the impossible',
      note: note,
      useWeb: false,
      onPlanned: (_) async => true,
      applyAction: (_) async => const AgentActionResult.ok(),
    );
    await until(() => run.value.status != AiRunStatus.running);
    expect(run.value.status, AiRunStatus.failed);
    expect(run.value.error, contains('none could be used'));
    expect(llm.requests, hasLength(1 + AgentTask.maxRepairs));
    run.dispose();
  });

  test('"nothing to change" is an answer, not an error', () async {
    final llm = _TurnLlm([
      {'summary': 'The page has no HTML tags already.', 'actions': []},
    ]);
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Remove the HTML tags',
      note: note,
      useWeb: false,
      onPlanned: (_) async => true,
      applyAction: (_) async => const AgentActionResult.ok(),
    );
    final outcome = await outcomeOf(run);
    expect(outcome.summary, 'The page has no HTML tags already.');
    expect(outcome.applied, isEmpty);
    run.dispose();
  });

  test('the loop stops at the turn limit', () async {
    // A different page every turn, so the repeat guard does not end it first.
    final llm = _TurnLlm([
      for (var i = 1; i <= AgentTask.maxTurns + 2; i++)
        {
          'summary': 'One more look',
          'actions': [
            {'kind': 'read_page', 'page': 'Page $i'},
          ],
          'done': false,
        },
    ]);
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Keep reading',
      note: note,
      useWeb: false,
      onPlanned: (_) async => true,
      applyAction: (_) async => const AgentActionResult.ok('text'),
    );
    final outcome = await outcomeOf(run);
    expect(llm.requests, hasLength(AgentTask.maxTurns));
    expect(outcome.turns, AgentTask.maxTurns);
    run.dispose();
  });

  test('asking for the same thing again is answered from memory, then ended',
      () async {
    final llm = _TurnLlm([
      {
        'summary': 'List',
        'actions': [
          {'kind': 'list_pages'},
        ],
        'done': false,
      },
    ]);
    var listed = 0;
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Find the page',
      note: note,
      useWeb: false,
      onPlanned: (_) async => true,
      applyAction: (_) async {
        listed++;
        return const AgentActionResult.ok('(no pages)');
      },
    );
    final outcome = await outcomeOf(run);
    expect(listed, 1, reason: 'the listing is run once, not on every turn');
    // Turn 1 lists; turn 2 repeats and is told so; turn 3 repeats and ends.
    expect(llm.requests, hasLength(3));
    expect(llm.requests[2].messages.last.content, contains('already asked'));
    expect(outcome.turns, 3);
    run.dispose();
  });

  test('a preview is asked for only when it is on, and only for writes',
      () async {
    final llm = _TurnLlm([
      {
        'summary': 'Look',
        'actions': [
          {'kind': 'read_page', 'page': 'A'},
        ],
        'done': false,
      },
      {
        'summary': 'Write',
        'actions': [
          {'kind': 'paragraph', 'text': 'x'},
        ],
      },
    ]);
    var previews = 0;
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Do it',
      note: note,
      useWeb: false,
      reviewBeforeWriting: true,
      onPlanned: (_) async {
        previews++;
        return true;
      },
      applyAction: (_) async => const AgentActionResult.ok('text'),
    );
    await outcomeOf(run);
    expect(previews, 1, reason: 'the read-only turn needs no approval');
    run.dispose();

    final llm2 = _TurnLlm([
      {
        'summary': 'Write',
        'actions': [
          {'kind': 'paragraph', 'text': 'x'},
        ],
      },
    ]);
    var previewedOff = false;
    final run2 = AgentTask(llm2, _NoSearch()).run(
      instruction: 'Do it',
      note: note,
      useWeb: false,
      onPlanned: (_) async {
        previewedOff = true;
        return true;
      },
      applyAction: (_) async => const AgentActionResult.ok(),
    );
    await outcomeOf(run2);
    expect(previewedOff, isFalse);
    run2.dispose();
  });

  test('earlier exchanges ride along as the conversation', () async {
    final llm = _TurnLlm([
      {
        'summary': 'Made it',
        'actions': [
          {'kind': 'paragraph', 'text': 'x'},
        ],
      },
    ]);
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Cells',
      note: note,
      useWeb: false,
      history: const [
        AgentExchange(
          instruction: 'Make a page for it',
          summary: 'Started',
          question: 'Which section?',
        ),
      ],
      onPlanned: (_) async => true,
      applyAction: (_) async => const AgentActionResult.ok(),
    );
    await outcomeOf(run);
    final messages = llm.requests.single.messages;
    expect(messages, hasLength(3));
    expect(messages[0].role, LlmRole.user);
    expect(messages[0].content, contains('Make a page for it'));
    expect(messages[1].role, LlmRole.assistant);
    expect(messages[1].content, contains('Which section?'));
    expect(messages[2].content, endsWith('Do this: Cells'));
    run.dispose();
  });

  test('the prompt is the skills, and a user skill is in it', () async {
    final llm = _TurnLlm([
      {'summary': 'ok', 'actions': []},
    ]);
    final run = AgentTask(llm, _NoSearch()).run(
      instruction: 'Anything',
      note: note,
      useWeb: false,
      userSkills: const ['# Lab notebook\nAlways date entries.'],
      onPlanned: (_) async => true,
      applyAction: (_) async => const AgentActionResult.ok(),
    );
    await until(() => run.value.status != AiRunStatus.running);
    final system = llm.requests.single.system!;
    expect(system, contains("You are Mario's agent"));
    expect(system, contains('Skill: read and search'));
    expect(system, contains('Always date entries.'));
    run.dispose();
  });
}

class _TurnLlm implements LlmService {
  _TurnLlm(this.replies);

  /// One reply per turn; the last repeats when the loop outruns the list.
  final List<Map<String, dynamic>> replies;
  final requests = <LlmRequest>[];
  var _turn = 0;

  @override
  Future<LlmProvider> requireProvider([String? id]) async => _StubProvider();

  @override
  LlmEffort get userEffort => LlmEffort.medium;

  @override
  Future<Map<String, dynamic>> structured({
    required LlmRequest request,
    required String schemaName,
    required Map<String, dynamic> schema,
    CancelToken? cancel,
    bool describeSchema = true,
    int repairAttempts = 1,
  }) async {
    requests.add(request);
    final reply = replies[_turn < replies.length ? _turn : replies.length - 1];
    _turn++;
    return reply;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubProvider implements LlmProvider {
  @override
  String get displayName => 'Test model';

  @override
  LlmCapabilities get capabilities =>
      const LlmCapabilities(contextTokens: 32000);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSearch implements WebSearchService {
  @override
  Future<WebSearchStatus> status() async => WebSearchStatus.turnedOff;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
