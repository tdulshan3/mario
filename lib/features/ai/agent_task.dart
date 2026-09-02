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
import '../../core/services/ai/web_search_service.dart';
import 'agent_actions.dart';
import 'ai_progress.dart';
import 'note_context.dart';
import 'note_images.dart';
import 'note_style.dart';
import 'search_planner.dart';

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
  AgentTask(this.llm, this.search);

  final LlmService llm;

  /// Editing a page and needing facts from outside it are not exclusive.
  /// "Add a section on the current EU AI rules" cannot be written from a page
  /// that says nothing about them, and before this the agent had no way to
  /// find out — it planned from the note alone and filled the gap itself.
  final WebSearchService search;

  /// Deliberately capped. A plan is not a loop, so this is not runaway
  /// protection — it stops a model from turning one instruction into forty
  /// edits to somebody's page.
  static const maxActions = 25;

  /// The instruction the model plans against.
  ///
  /// Exposed so the change-versus-add rules can be asserted: they are the only
  /// thing standing between "rewrite this" and a page that says everything
  /// twice, and they are prose, so nothing else would catch them going away.
  static String get systemPrompt => _system;

  static const _system =
      'You edit a student\'s notes page directly, by returning a list of '
      'actions to perform on it.\n'
      'Do exactly what is asked, and nothing else. Do not tidy, reformat or '
      '"improve" parts of the page you were not asked about — it is their page '
      'and they did not ask.\n'
      'FIRST decide whether you are being asked to CHANGE what is on the page '
      'or to ADD to it.\n'
      'Rewrite, reword, rephrase, restyle, arrange, rearrange, reorganise, '
      'reorder, tidy, format, shorten, expand, simplify, translate, correct, '
      'fix and improve all mean CHANGE. The new version must REPLACE the '
      'blocks it is about — replace_block with their ids, or delete_block and '
      'an insert when the shape changes. Do NOT leave the old wording in place '
      'and put a new version underneath it: that leaves the page saying the '
      'same thing twice, which is never what was asked for.\n'
      'Add, insert, append, write, create, note down and "give me" mean ADD. '
      'Leave what is there and insert the new blocks.\n'
      'Every block in the notes below is labelled [id:xxxxxx]. To change, '
      'remove or move one, use that exact id in blockId. Never invent an id. '
      'To add or move something to a particular place, put the id of the block '
      'it should follow in afterBlockId; omit it for the end.\n'
      'When you delete a block and insert its replacement, give the insert an '
      'afterBlockId so the new text lands where the old text was. An insert '
      'with no afterBlockId goes to the very end of the page, which for a '
      'rewrite is the wrong place.\n'
      'When the shape does not change, one replace_block per block beats a '
      'delete and an insert.\n'
      'Images are blocks like any other. Use move_block to put a picture beside '
      'the text that discusses it — any text detected inside the images is '
      'listed below, labelled with the same ids.\n'
      'Write real content, not placeholders. A table gets actual rows, a code '
      'block gets code that runs, a formula gets LaTeX.\n'
      'Tables and spreadsheets take "rows", the first row being the header, '
      'and every row must have the same number of cells.\n'
      'Keep the plan short. Several small, clear actions beat one enormous '
      'one.';

  /// Looks up what the page cannot answer, and renders it for the prompt.
  ///
  /// The instruction is a poor query on its own — "add a section on the new
  /// rules" carries its subject in the page, not in the sentence — so the
  /// model writes the query, with the labelled page as context and the
  /// instruction as the fallback. Same planner the Ask tab uses.
  ///
  /// A failed or unavailable search never sinks the run: the page alone is
  /// what the agent had before, and saying so beats an error where an edit
  /// was expected.
  Future<String> _search(
    AiRun run,
    String instruction,
    String pageContext,
    bool? useWeb,
  ) async {
    final status = await search.status();
    if (status != WebSearchStatus.ready) {
      run.begin(AiStepKind.searchingWeb,
          detail: '${status.reason} — planning from the page only');
      run.skip(AiStepKind.searchingWeb);
      return '';
    }

    run.begin(AiStepKind.searchingWeb, detail: 'working out what to look up');
    final plan = await planSearch(
      llm: llm,
      task: instruction,
      fallback: instruction,
      context: pageContext,
      cancel: run.cancelToken,
    );

    // The model's judgement, but only where the user left the choice to it.
    // An explicit "Web: on" is an instruction, not a suggestion.
    if (!plan.needsSearch && useWeb != true) {
      run.detail('nothing here needs looking up');
      run.skip(AiStepKind.searchingWeb);
      return '';
    }

    run.setSearchQuery(plan.queries.join(' · '));
    run.detail(plan.queries.join(' · '));

    final sources = <AiSource>[];
    final seen = <String>{};
    for (final q in plan.queries) {
      try {
        for (final r in await search.search(q, cancel: run.cancelToken)) {
          if (seen.add(r.url)) sources.add(r);
        }
      } on LlmCancelled {
        rethrow;
      } on LlmException catch (e) {
        run.detail('search unavailable (${e.message})');
      }
    }

    if (sources.isEmpty) {
      run.detail('no results — planning from the page only');
      return '';
    }
    run.addSources(sources);
    run.detail('${sources.length} result(s)');
    return renderSourcesForPrompt(sources);
  }

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
    bool? useWeb,
  }) {
    // Tri-state, as on Ask: null lets the instruction decide, true forces a
    // look-up, false forbids one.
    final wantsWeb = useWeb ?? looksLikeItNeedsSearch(instruction);
    final agentRun = AiRun([
      AiStepKind.readingNote,
      if (wantsWeb) AiStepKind.searchingWeb,
      AiStepKind.thinking,
      AiStepKind.checking,
      AiStepKind.answering,
    ]);
    unawaited(_run(agentRun, instruction, note, onPlanned, applyAction, images,
        wantsWeb, useWeb));
    return agentRun;
  }

  Future<void> _run(
    AiRun run,
    String instruction,
    NoteText note,
    void Function(AgentPlan plan) onPlanned,
    Future<bool> Function(AgentAction action) applyAction,
    List<NoteImage> images,
    bool wantsWeb,
    bool? useWeb,
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

      final webContext =
          wantsWeb ? await _search(run, instruction, labelled, useWeb) : '';

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
                '${webContext.isEmpty ? '' : '$webContext\n'}'
                '---\n\nDo this: $instruction'),
          ],
          maxTokens: 3000,
          // Planning an edit to someone's page is user-facing work, so it
          // follows the depth they chose.
          effort: llm.userEffort,
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
