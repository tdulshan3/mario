/// The agent: work in turns until the job is done.
///
/// Each turn asks the model for a plan — a summary, a list of actions, and
/// whether it is finished — validates it in Dart, and carries it out. What
/// makes it an agent rather than a one-shot edit is what happens next: a turn
/// may ask to *see* something (a page, a listing, a search), and the result is
/// handed back for the next turn, so "find my notes on enzymes and make a
/// summary page" is a search, then a read, then a write, decided step by step
/// rather than guessed in one go.
///
/// Plan-then-execute, still, rather than native tool calls: a small local
/// model copies one flat JSON shape far more reliably than it drives a tool
/// protocol, and [parseAgentPlan] rejects whatever comes back wrong before
/// anything touches a page. The model never touches the document; it returns
/// actions, and [AgentExecutor] and the tools run what survived.
///
/// Progress is reported per action rather than as one long wait, because the
/// user is watching their own page change and deserves to see what changed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../../core/services/ai/llm_service.dart';
import '../../core/services/ai/llm_types.dart';
import '../../core/services/ai/web_search_service.dart';
import 'agent_actions.dart';
import 'ai_progress.dart';
import 'html_artifact.dart';
import 'mario_skills.dart';
import 'note_context.dart';
import 'note_images.dart';
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
    this.followUps = const [],
    this.question,
    this.turns = 1,
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

  /// Next instructions the model suggested, for the user to tap.
  final List<String> followUps;

  /// A question the model stopped to ask. The user's reply is the next
  /// instruction, and this exchange rides along as its context.
  final String? question;

  /// How many turns it took.
  final int turns;

  bool get changedAnything => applied.isNotEmpty;
}

/// One earlier instruction and what came of it, carried into the next run
/// so a follow-up ("also do it for the other section", the answer to a
/// question) lands in context.
class AgentExchange {
  const AgentExchange({
    required this.instruction,
    required this.summary,
    this.question,
  });

  final String instruction;
  final String summary;
  final String? question;
}

class AgentTask {
  AgentTask(this.llm, this.search);

  final LlmService llm;

  /// Editing a page and needing facts from outside it are not exclusive.
  /// "Add a section on the current EU AI rules" cannot be written from a page
  /// that says nothing about them. The pre-planning search below answers the
  /// obvious cases; the `web_search` action lets the model look things up
  /// itself, mid-job, when it finds it needs to.
  final WebSearchService search;

  /// Deliberately capped, per turn. A plan is not a loop, so this is not
  /// runaway protection — it stops a model from turning one instruction into
  /// forty edits to somebody's page in a single step.
  static const maxActions = 25;

  /// Turns per instruction. Enough for search → read → read → write, and a
  /// hard stop for a model that keeps asking to see one more thing.
  static const maxTurns = 8;

  /// Extra turns allowed for putting right what Mario refused or could not
  /// do. Two: once is a slip, twice is a pattern, and a third try would be a
  /// loop.
  static const maxRepairs = 2;

  /// The prompt the model plans against — Mario's skills, not a rulebook.
  ///
  /// Exposed so the change-versus-add wording can be asserted: it is the only
  /// thing standing between "rewrite this" and a page that says everything
  /// twice, and it is prose, so nothing else would catch it going away.
  static String get systemPrompt => marioAgentPrompt();

  /// Looks up what the page cannot answer, and renders it for the prompt.
  ///
  /// The instruction is a poor query on its own — "add a section on the new
  /// rules" carries its subject in the page, not in the sentence — so the
  /// model writes the query, with the labelled page as context and the
  /// instruction as the fallback. Same planner the Ask tab uses.
  ///
  /// A failed or unavailable search never sinks the run: the page alone is
  /// what the agent always had before, and the model can still `web_search`
  /// on its own during the job.
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
    run.cancelToken.throwIfCancelled();

    if (!plan.needsSearch && useWeb != true) {
      run.detail('nothing here needs looking up');
      run.skip(AiStepKind.searchingWeb);
      return '';
    }

    run.setSearchQuery(plan.queries.join(' · '));
    run.detail(plan.queries.join(' · '));

    final sources = <AiSource>[];
    final seen = <String>{};
    for (final query in plan.queries) {
      try {
        for (final r in await search.search(query, cancel: run.cancelToken)) {
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

  AiRun run({
    required String instruction,
    required NoteText note,
    required Future<bool> Function(AgentPlan plan) onPlanned,
    required Future<AgentActionResult> Function(AgentAction action) applyAction,
    List<NoteImage> images = const [],
    bool? useWeb,
    String? htmlArtifact,
    String? sectionName,
    List<String> sectionNames = const [],
    String? notebookName,
    List<AgentExchange> history = const [],
    List<String> userSkills = const [],
    bool reviewBeforeWriting = false,
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
    final job = _Job(
      instruction: instruction,
      note: note,
      onPlanned: onPlanned,
      applyAction: applyAction,
      images: images,
      wantsWeb: wantsWeb,
      useWeb: useWeb,
      htmlArtifact: htmlArtifact,
      whereItLives: _whereItLives(sectionName, sectionNames, notebookName),
      history: history,
      userSkills: userSkills,
      reviewBeforeWriting: reviewBeforeWriting,
    );
    unawaited(_run(agentRun, job));
    return agentRun;
  }

  /// The page's place in the notebook, for the prompt, so a section the model
  /// names in create_page or rename_section is one that exists.
  String _whereItLives(
    String? sectionName,
    List<String> sectionNames,
    String? notebookName,
  ) {
    final names = [for (final n in sectionNames) n.trim()]
        .where((n) => n.isNotEmpty)
        .toList();
    final buf = StringBuffer();
    final section = sectionName?.trim();
    final notebook = notebookName?.trim();
    if (section != null && section.isNotEmpty) {
      buf.writeln(notebook == null || notebook.isEmpty
          ? 'This page is in the section "$section".'
          : 'This page is in the section "$section" of the notebook '
              '"$notebook".');
    } else if (notebook != null && notebook.isNotEmpty) {
      buf.writeln('This page is in the notebook "$notebook".');
    }
    if (names.isNotEmpty) {
      buf.writeln(
          'Sections in this notebook: ${names.map((n) => '"$n"').join(', ')}.');
    }
    return buf.toString();
  }

  Future<void> _run(AiRun run, _Job job) async {
    try {
      final provider = await llm.requireProvider();
      run.setBackend(provider.displayName);
      final contextTokens = provider.capabilities.contextTokens;
      final htmlRequested = asksForHtmlArtifact(job.instruction) ||
          job.htmlArtifact?.trim().isNotEmpty == true;

      run.begin(AiStepKind.readingNote);
      // Ids go in the prompt so the model can target existing blocks. They are
      // session-scoped (see NoteBlock.nodeId), which is fine: the plan is made
      // and executed within one session.
      final promptNote = htmlRequested
          ? job.note.limitToTokens((contextTokens * 0.25).round())
          : job.note;
      final labelled = _withBlockIds(promptNote);
      final knownIds = {for (final b in job.note.blocks) b.nodeId};
      run.detail('${job.note.blocks.length} block(s)');

      final webContext = job.wantsWeb
          ? await _search(run, job.instruction, labelled, job.useWeb)
          : '';

      // The text found in each picture, labelled by the same block id the
      // agent uses to move things — which is what lets "put the diagram next
      // to the section it illustrates" resolve to a specific block.
      final imageText = renderImageTextForPrompt(job.images);
      final htmlText = _htmlForPrompt(
        job.htmlArtifact,
        (contextTokens * 0.35).round(),
      );
      final system = htmlRequested
          ? '${marioAgentPrompt(userSkills: job.userSkills)}\n\n'
              '$_htmlArtifactStyle'
          : marioAgentPrompt(userSkills: job.userSkills);
      final messages = <LlmMessage>[
        ..._historyMessages(job.history),
        LlmMessage.user('Current page:\n$labelled\n\n'
            '${job.whereItLives.isEmpty ? '' : '${job.whereItLives}\n'}'
            '${imageText.isEmpty ? '' : '$imageText\n'}'
            '${htmlText.isEmpty ? '' : '$htmlText\n'}'
            '${webContext.isEmpty ? '' : '$webContext\n'}'
            '---\n\nDo this: ${job.instruction}'),
      ];
      final maxTokens = htmlRequested
          ? math.min(8000, math.max(3000, contextTokens ~/ 2))
          : 3000;
      // Characters, not tokens: a read page comes back as prose, and three
      // characters to a token is the rough rate the budget check uses.
      final observationChars =
          (contextTokens * 0.3 * 3).round().clamp(4000, 40000);

      final applied = <String>[];
      var failed = 0;
      final rejected = <DroppedAction>[];
      var destructive = 0;
      var summary = '';
      var followUps = const <String>[];
      String? question;
      var turns = 0;
      // What the model has already asked to see. A small model that gets an
      // empty listing tends to ask for the same listing again, turn after
      // turn; a repeat is answered from memory once, and ends the run twice.
      final seen = <String>{};
      var repeats = 0;
      // Turns spent fixing a plan Mario could not use: actions the validator
      // refused, or actions that failed on the page. The reasons go back to
      // the model, as an agent's tool errors do, and it tries another way —
      // twice, and then the run ends with what it has.
      var repairs = 0;

      while (true) {
        turns++;
        run.cancelToken.throwIfCancelled();
        run.begin(AiStepKind.thinking,
            detail: turns == 1 ? job.instruction : 'step $turns');
        final raw = await llm.structured(
          request: LlmRequest(
            system: system,
            messages: messages,
            maxTokens: maxTokens,
            // Planning an edit to someone's page is user-facing work, so it
            // follows the depth they chose.
            effort: llm.userEffort,
          ),
          schemaName: 'agent_plan',
          schema: agentPlanSchema,
          cancel: run.cancelToken,
        );

        run.begin(AiStepKind.checking);
        final plan = _capped(parseAgentPlan(raw, knownBlockIds: knownIds));
        rejected.addAll(plan.rejected);
        destructive += plan.destructiveCount;
        if (plan.summary.isNotEmpty) summary = plan.summary;
        if (plan.followUps.isNotEmpty) followUps = plan.followUps;

        if (plan.isEmpty) {
          if (plan.dropped > 0 && repairs < maxRepairs && turns < maxTurns) {
            // Every action was refused. Say why, in the model's own terms,
            // and let it re-plan — a rewrite with no text, a table with
            // ragged rows, an id that is not on the page are all things it
            // can fix when told.
            repairs++;
            run.detail('re-planning: ${plan.rejectionSummary.join('; ')}');
            messages
              ..add(LlmMessage.assistant(jsonEncode(raw)))
              ..add(LlmMessage.user(_refusal(plan)));
            continue;
          }
          // Earlier turns did work and this one has nothing more to do.
          if (applied.isNotEmpty) break;
          // "Nothing to change here" is an answer, not a failure.
          if (plan.dropped == 0 && summary.isNotEmpty) break;
          // The reasons go in the message. This is the one case where the
          // user sees nothing else at all, so "none of them worked" without
          // saying why leaves them with no next move.
          throw LlmException(plan.dropped > 0
              ? 'The model proposed ${plan.dropped} change(s) and none could '
                  'be used: ${plan.rejectionSummary.join('; ')}. Try '
                  'phrasing the instruction more concretely.'
              : 'The model did not propose any changes.');
        }

        run.detail(plan.dropped == 0
            ? '${plan.actions.length} action(s)'
            : '${plan.actions.length} action(s), ${plan.dropped} not used '
                '(${plan.rejectionSummary.join('; ')})');

        if (job.reviewBeforeWriting &&
            plan.actions.any((a) => a.kind.isWrite)) {
          run.detail('review the preview, then apply or discard');
          final approved = await job.onPlanned(plan);
          run.cancelToken.throwIfCancelled();
          if (!approved) {
            run.appendAnswer('Preview discarded. No changes were applied.');
            run.finish();
            return;
          }
        }

        final askedBefore = plan.actions
            .every((a) => a.kind.observes && seen.contains(_signature(a)));
        if (askedBefore) {
          repeats++;
          run.detail('asked for the same thing again');
          if (repeats >= 2 || turns >= maxTurns) break;
          messages
            ..add(LlmMessage.assistant(jsonEncode(raw)))
            ..add(LlmMessage.user(
              'You already asked for exactly that, and the results were '
              'given above; they have not changed. Decide with what you '
              'have: do the work, or ask_user one clear question. Return '
              'done: true when finished.',
            ));
          continue;
        }

        run.begin(AiStepKind.answering);
        final observations = <String>[];
        final notes = <String>[];
        var stop = false;
        for (var i = 0; i < plan.actions.length; i++) {
          run.cancelToken.throwIfCancelled();
          final action = plan.actions[i];
          run.detail('${i + 1} of ${plan.actions.length} — ${action.summary}');
          final result = await job.applyAction(action);
          if (result.ok) {
            applied.add(action.summary);
          } else {
            failed++;
          }
          if (action.kind.observes) seen.add(_signature(action));
          if (action.kind.observes) {
            final text = result.text?.trim();
            observations.add('### ${action.summary}\n'
                '${_clip(text == null || text.isEmpty ? (result.ok ? '(nothing)' : 'failed') : text, observationChars)}');
          } else if (!result.ok && result.text != null) {
            notes.add('### ${action.summary} — could not be done\n'
                '${_clip(result.text!, 600)}');
          }
          if (result.ok && action.kind == AgentActionKind.askUser) {
            question = action.text;
            stop = true;
            break;
          }
          if (result.ok && action.kind == AgentActionKind.openPage) {
            // The page that was open is closing; nothing after this could
            // land on it.
            stop = true;
            break;
          }
        }
        if (stop) break;
        // A step that failed, or a step the validator refused, is worth one
        // more look: the model is told what went wrong and tries another
        // way, as long as it has repairs left.
        final wantsRepair =
            (notes.isNotEmpty || plan.dropped > 0) && repairs < maxRepairs;
        if (observations.isEmpty && plan.done && !wantsRepair) break;
        if (turns >= maxTurns) {
          run.detail('stopping after $maxTurns step(s)');
          break;
        }
        if (observations.isEmpty && wantsRepair) repairs++;

        messages
          ..add(LlmMessage.assistant(jsonEncode(raw)))
          ..add(LlmMessage.user(
            '${observations.isEmpty ? '' : 'Results:\n\n${observations.join('\n\n')}\n\n'}'
            '${notes.isEmpty ? '' : '${notes.join('\n\n')}\n\n'}'
            '${plan.dropped == 0 ? '' : '${_refusal(plan)}\n\n'}'
            '${notes.isEmpty && plan.dropped == 0 ? 'Continue. ' : 'Fix what you can another way, or say so in the summary. '}'
            'Return your next actions, and done: true when the work is '
            'finished.',
          ));
      }

      final plan =
          AgentPlan(summary: summary, actions: const [], rejected: rejected);
      run.setResult(AgentOutcome(
        summary: summary,
        applied: applied,
        failed: failed,
        dropped: rejected.length,
        dropReasons: plan.rejectionSummary,
        destructive: destructive,
        followUps: followUps,
        question: question,
        turns: turns,
      ));
      run.appendAnswer(summary);
      run.finish();
    } catch (e) {
      run.fail(e);
    }
  }

  /// The plan, cut to [maxActions], with the excess reported.
  AgentPlan _capped(AgentPlan plan) {
    if (plan.actions.length <= maxActions) return plan;
    final over = plan.actions.length - maxActions;
    return AgentPlan(
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
      done: plan.done,
      followUps: plan.followUps,
    );
  }

  /// Earlier exchanges, as the conversation the model is continuing.
  ///
  /// Only the last few: what matters is the question it asked and the reply
  /// it is about to get, or the instruction the user is now refining.
  List<LlmMessage> _historyMessages(List<AgentExchange> history) {
    final recent =
        history.length <= 6 ? history : history.sublist(history.length - 6);
    return [
      for (final e in recent) ...[
        LlmMessage.user('Do this: ${e.instruction}'),
        LlmMessage.assistant(e.question != null
            ? '${e.summary.isEmpty ? '' : '${e.summary}\n'}'
                'I asked: ${e.question}'
            : e.summary.isEmpty
                ? 'Done.'
                : e.summary),
      ],
    ];
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

  String _htmlForPrompt(String? html, int budget) {
    final value = html?.trim();
    if (value == null || value.isEmpty) return '';
    final maxChars = math.max(1, budget * 2);
    final clipped = value.length <= maxChars
        ? value
        : '${value.substring(0, maxChars)}\n<!-- HTML clipped to fit context -->';
    return 'Current HTML artifact (verbatim):\n'
        '<CURRENT_HTML_ARTIFACT>\n$clipped\n</CURRENT_HTML_ARTIFACT>\n';
  }

  /// What the validator refused, told to the model as a tool would report
  /// an error: which action, and why, so the fix is obvious.
  static String _refusal(AgentPlan plan) {
    final lines = [
      for (final r in plan.rejected)
        '- ${r.kind.isEmpty ? 'an action' : r.kind}: ${r.reason}',
    ];
    return 'Mario could not use ${plan.dropped} of your action(s):\n'
        '${lines.join('\n')}\n'
        'A block that should be removed is a delete_block; a rewrite needs '
        'its replacement in text; ids must be ones on the page.';
  }

  /// What a read asks for, so an identical one can be recognised.
  static String _signature(AgentAction a) => [
        a.kind.name,
        a.text.trim().toLowerCase(),
        a.page?.trim().toLowerCase() ?? '',
        a.notebook?.trim().toLowerCase() ?? '',
        a.section?.trim().toLowerCase() ?? '',
      ].join('|');

  static String _clip(String text, int maxChars) => text.length <= maxChars
      ? text
      : '${text.substring(0, maxChars)}\n[… clipped to fit the context]';

  static const _htmlArtifactStyle =
      'Create a working browser artifact, not prose about one. Return one html '
      'action containing a complete self-contained document. Put CSS in '
      '<style> and JavaScript in <script>. Keep it responsive and accessible. '
      'Do not use placeholders or omit code. The user will review a live '
      'sandboxed preview before choosing whether to apply it.';
}

/// Everything one run needs, so the loop reads as a loop.
class _Job {
  const _Job({
    required this.instruction,
    required this.note,
    required this.onPlanned,
    required this.applyAction,
    required this.images,
    required this.wantsWeb,
    required this.useWeb,
    required this.htmlArtifact,
    required this.whereItLives,
    required this.history,
    required this.userSkills,
    required this.reviewBeforeWriting,
  });

  final String instruction;
  final NoteText note;
  final Future<bool> Function(AgentPlan plan) onPlanned;
  final Future<AgentActionResult> Function(AgentAction action) applyAction;
  final List<NoteImage> images;
  final bool wantsWeb;
  final bool? useWeb;
  final String? htmlArtifact;
  final String whereItLives;
  final List<AgentExchange> history;
  final List<String> userSkills;
  final bool reviewBeforeWriting;
}
