/// The agent: ask for a plan, check it, carry it out.
///
/// Two phases with a validation gate between them. The model never touches the
/// document — it returns a list of actions, [parseAgentPlan] throws away
/// anything it cannot make safe, and only then does [AgentExecutor] run what
/// survived. A hallucinated block id, a ragged table, a setting outside the
/// allowlist: all decided in Dart, before any edit.
///
/// Progress is reported per action rather than as one long wait, because the
/// user is watching their own page change and deserves to see what changed.
library;

import 'dart:async';

import '../../core/services/ai/llm_service.dart';
import '../../core/services/ai/llm_types.dart';
import 'agent_actions.dart';
import 'ai_progress.dart';
import 'note_context.dart';
import 'note_images.dart';
import 'note_style.dart';

/// What the agent did, for the panel to show and offer to undo.
class AgentOutcome {
  const AgentOutcome({
    required this.summary,
    required this.applied,
    required this.failed,
    required this.dropped,
    this.dropReasons = const [],
    required this.destructive,
  });

  final String summary;
  final List<String> applied;

  /// Actions that could not be applied — usually a target block edited or
  /// deleted between planning and running.
  final int failed;

  /// Actions the plan proposed that validation rejected.
  final int dropped;

  /// Why, deduplicated. Empty when nothing was rejected.
  final List<String> dropReasons;

  final int destructive;

  bool get changedAnything => applied.isNotEmpty;
}

class AgentTask {
  AgentTask(this.llm);

  final LlmService llm;

  /// Deliberately capped. A plan is not a loop, so this is not runaway
  /// protection — it stops a model from turning one instruction into forty
  /// edits to somebody's page.
  static const maxActions = 25;

  static const _system =
      'You edit a student\'s notes page directly, by returning a list of '
      'actions to perform on it.\n'
      'Do exactly what is asked, and nothing else. Do not tidy, reformat or '
      '"improve" parts of the page you were not asked about — it is their page '
      'and they did not ask.\n'
      'Prefer adding to rewriting. Only use replace_block or delete_block when '
      'the request plainly calls for changing or removing something that is '
      'already there.\n'
      'Every block in the notes below is labelled [id:xxxxxx]. To change, '
      'remove or move one, use that exact id in blockId. Never invent an id. '
      'To add or move something to a particular place, put the id of the block '
      'it should follow in afterBlockId; omit it for the end.\n'
      'Images are blocks like any other. Use move_block to put a picture beside '
      'the text that discusses it — any text detected inside the images is '
      'listed below, labelled with the same ids.\n'
      'Write real content, not placeholders. A table gets actual rows, a code '
      'block gets code that runs, a formula gets LaTeX.\n'
      'Tables and spreadsheets take "rows", the first row being the header, '
      'and every row must have the same number of cells.\n'
      'Keep the plan short. Several small, clear actions beat one enormous '
      'one.';

  /// Plans a change to the page and returns the run driving it.
  ///
  /// [onPlanned] is called once the plan has been validated, so the caller can
  /// snapshot the document before anything is applied. [applyAction] performs
  /// one action and reports whether it landed.
  AiRun run({
    required String instruction,
    required NoteText note,
    required void Function(AgentPlan plan) onPlanned,
    required Future<bool> Function(AgentAction action) applyAction,
    List<NoteImage> images = const [],
  }) {
    final agentRun = AiRun(const [
      AiStepKind.readingNote,
      AiStepKind.thinking,
      AiStepKind.checking,
      AiStepKind.answering,
    ]);
    unawaited(
        _run(agentRun, instruction, note, onPlanned, applyAction, images));
    return agentRun;
  }

  Future<void> _run(
    AiRun run,
    String instruction,
    NoteText note,
    void Function(AgentPlan plan) onPlanned,
    Future<bool> Function(AgentAction action) applyAction,
    List<NoteImage> images,
  ) async {
    try {
      final provider = await llm.requireProvider();
      run.setBackend(provider.displayName);

      run.begin(AiStepKind.readingNote);
      // Ids go in the prompt so the model can target existing blocks. They are
      // session-scoped (see NoteBlock.nodeId), which is fine: the plan is made
      // and executed within one session.
      final labelled = _withBlockIds(note);
      final knownIds = {for (final b in note.blocks) b.nodeId};
      run.detail('${note.blocks.length} block(s)');

      run.begin(AiStepKind.thinking, detail: instruction);
      // The text found in each picture, labelled by the same block id the
      // agent uses to move things — which is what lets "put the diagram next
      // to the section it illustrates" resolve to a specific block.
      final imageText = renderImageTextForPrompt(images);
      final raw = await llm.structured(
        request: LlmRequest(
          system: '$_system\n\n${noteStyleFor(NoteStyleContext.agent)}',
          messages: [
            LlmMessage.user('Current page:\n$labelled\n\n'
                '${imageText.isEmpty ? '' : '$imageText\n'}'
                '---\n\nDo this: $instruction'),
          ],
          maxTokens: 3000,
          effort: LlmEffort.medium,
        ),
        schemaName: 'agent_plan',
        schema: agentPlanSchema,
        cancel: run.cancelToken,
      );

      run.begin(AiStepKind.checking);
      var plan = parseAgentPlan(raw, knownBlockIds: knownIds);
      if (plan.actions.length > maxActions) {
        final over = plan.actions.length - maxActions;
        plan = AgentPlan(
          summary: plan.summary,
          actions: plan.actions.take(maxActions).toList(),
          rejected: [
            ...plan.rejected,
            // Labelled apart from the validation rejections: these were fine,
            // there were simply too many of them.
            for (var i = 0; i < over; i++)
              const DroppedAction(
                  kind: '', reason: 'over the $maxActions-change limit'),
          ],
        );
      }

      if (plan.isEmpty) {
        // The reasons go in the message. This is the one case where the user
        // sees nothing else at all, so "none of them worked" without saying
        // why leaves them with no next move.
        throw LlmException(plan.dropped > 0
            ? 'The model proposed ${plan.dropped} change(s) and none could be '
                'used: ${plan.rejectionSummary.join('; ')}. Try phrasing the '
                'instruction more concretely.'
            : 'The model did not propose any changes.');
      }

      run.detail(plan.dropped == 0
          ? '${plan.actions.length} action(s)'
          : '${plan.actions.length} action(s), ${plan.dropped} not used '
              '(${plan.rejectionSummary.join('; ')})');

      // The caller snapshots here, between validation and the first edit.
      onPlanned(plan);

      run.begin(AiStepKind.answering);
      final applied = <String>[];
      var failed = 0;

      for (var i = 0; i < plan.actions.length; i++) {
        run.cancelToken.throwIfCancelled();
        final action = plan.actions[i];
        run.detail('${i + 1} of ${plan.actions.length} — ${action.summary}');
        if (await applyAction(action)) {
          applied.add(action.summary);
        } else {
          failed++;
        }
      }

      run.setResult(AgentOutcome(
        summary: plan.summary,
        applied: applied,
        failed: failed,
        dropped: plan.dropped,
        dropReasons: plan.rejectionSummary,
        destructive: plan.destructiveCount,
      ));
      run.appendAnswer(plan.summary);
      run.finish();
    } catch (e) {
      run.fail(e);
    }
  }

  /// The page, with each block labelled by id so the model can target it.
  String _withBlockIds(NoteText note) {
    final buf = StringBuffer();
    if (note.title.trim().isNotEmpty) {
      buf.writeln('Title: ${note.title}');
      buf.writeln();
    }
    for (final b in note.blocks) {
      if (b.isEmpty) continue;
      buf.writeln('[id:${b.nodeId}] ${b.text}');
    }
    return buf.toString().trimRight();
  }
}
