/// A rewrite has to REPLACE, not pile up underneath.
///
/// "Rewrite this", "arrange this", "restyle this" were leaving the original
/// text in place and adding a new version below it, so the page ended up
/// saying the same thing twice. Two separate causes:
///
///  * the system prompt told the model "Prefer adding to rewriting", which is
///    the opposite of what those verbs ask for;
///  * a plan that deleted the old block and then inserted the new one named
///    the deleted block in `afterBlockId`. By then it resolved to nothing, so
///    the insert fell back to the end of the page — which is exactly the
///    "stacked at the bottom" symptom.
///
/// The prompt is asserted as text because it is the only place the first
/// behaviour is decided; the executor is driven for real.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/agent_actions.dart';
import 'package:mario/features/ai/agent_executor.dart';
import 'package:mario/features/ai/agent_task.dart';

/// A page of three paragraphs, with their ids.
({afe.EditorState state, AgentExecutor agent, List<String> ids}) page() {
  final doc = afe.Document.blank();
  final nodes = [
    for (final t in ['one', 'two', 'three'])
      afe.paragraphNode(delta: afe.Delta()..insert(t)),
  ];
  final state = afe.EditorState(document: doc);
  final tx = state.transaction..insertNodes([0], nodes);
  state.apply(tx);

  final agent = AgentExecutor(state);
  // A run always begins with a snapshot; that is also what clears the
  // previous run's deletions.
  agent.snapshot('Page');
  return (
    state: state,
    agent: agent,
    ids: [for (final n in state.document.root.children) n.id],
  );
}

List<String> textsOf(afe.EditorState s) => [
      for (final n in s.document.root.children)
        if (n.delta != null) n.delta!.toPlainText(),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the instruction the model is given', () {
    test('names the verbs that mean replace, not add', () {
      final p = AgentTask.systemPrompt;
      for (final verb in [
        'Rewrite',
        'restyle',
        'arrange',
        'reorganise',
        'shorten',
        'translate',
      ]) {
        expect(p, contains(verb),
            reason: '"$verb" has to be named as a CHANGE, or the model adds');
      }
      expect(p, contains('REPLACE'));
      expect(p, contains('html action'));
      expect(p, isNot(contains('Prefer adding to rewriting')),
          reason: 'the old wording is what caused the stacking');
    });

    test('says an anchorless insert goes to the end', () {
      // The model has to know that omitting afterBlockId is a choice with a
      // consequence, or a rewrite quietly lands at the bottom.
      expect(AgentTask.systemPrompt, contains('afterBlockId'));
      expect(AgentTask.systemPrompt, contains('end of the page'));
    });
  });

  group('delete-then-insert lands in the gap, not at the end', () {
    test('the replacement takes the deleted block\'s place', () async {
      final p = page();

      await p.agent.apply(
        AgentAction(kind: AgentActionKind.deleteBlock, blockId: p.ids[1]),
      );
      await p.agent.apply(
        AgentAction(
          kind: AgentActionKind.paragraph,
          text: 'TWO, rewritten',
          // Anchored to the block that has just been deleted — which is what
          // a model plans, and what used to fall through to the end.
          afterBlockId: p.ids[1],
        ),
      );

      expect(textsOf(p.state), ['one', 'TWO, rewritten', 'three']);
    });

    test('deleting the FIRST block puts the replacement at the top', () async {
      final p = page();

      await p.agent.apply(
        AgentAction(kind: AgentActionKind.deleteBlock, blockId: p.ids[0]),
      );
      await p.agent.apply(
        AgentAction(
          kind: AgentActionKind.paragraph,
          text: 'ONE, rewritten',
          afterBlockId: p.ids[0],
        ),
      );

      expect(textsOf(p.state), ['ONE, rewritten', 'two', 'three']);
    });

    test('a whole-page rewrite keeps its order', () async {
      final p = page();

      // Delete everything, then insert each replacement after the block it
      // replaces — the shape a "rewrite this page" plan takes.
      for (final id in p.ids) {
        await p.agent
            .apply(AgentAction(kind: AgentActionKind.deleteBlock, blockId: id));
      }
      for (var i = 0; i < p.ids.length; i++) {
        await p.agent.apply(AgentAction(
          kind: AgentActionKind.paragraph,
          text: 'new ${i + 1}',
          afterBlockId: p.ids[i],
        ));
      }

      // The trailing empty block is the executor's "never leave the document
      // with nothing focusable" guard firing as the last original block goes.
      // It is a place to keep typing, not a stray.
      expect(textsOf(p.state), ['new 1', 'new 2', 'new 3', '']);
    });

    test('an insert with no anchor still goes to the end', () async {
      // The fallback has to survive: "add a note at the bottom" is a real
      // request, and it must not be captured by the gap-tracking.
      final p = page();
      await p.agent.apply(
        const AgentAction(kind: AgentActionKind.paragraph, text: 'appended'),
      );
      expect(textsOf(p.state), ['one', 'two', 'three', 'appended']);
    });

    test('an unknown anchor still goes to the end', () async {
      final p = page();
      await p.agent.apply(
        const AgentAction(
          kind: AgentActionKind.paragraph,
          text: 'appended',
          afterBlockId: 'never-existed',
        ),
      );
      expect(textsOf(p.state), ['one', 'two', 'three', 'appended']);
    });

    test('a new run forgets the last one\'s gaps', () async {
      final p = page();
      await p.agent.apply(
        AgentAction(kind: AgentActionKind.deleteBlock, blockId: p.ids[1]),
      );

      // Next run: the snapshot is what marks the boundary.
      p.agent.snapshot('Page');
      await p.agent.apply(
        AgentAction(
          kind: AgentActionKind.paragraph,
          text: 'later',
          afterBlockId: p.ids[1],
        ),
      );

      expect(textsOf(p.state), ['one', 'three', 'later'],
          reason: 'a gap from a finished run must not steer a later insert');
    });
  });

  group('replace_block, the simpler path', () {
    test('swaps the text and leaves the order alone', () async {
      final p = page();
      await p.agent.apply(AgentAction(
        kind: AgentActionKind.replaceBlock,
        blockId: p.ids[1],
        text: 'TWO, rewritten',
      ));
      expect(textsOf(p.state), ['one', 'TWO, rewritten', 'three']);
    });
  });
}
