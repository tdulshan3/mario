/// The Do tab — tell the model what to change, preview it, then apply it.
///
/// A validated plan pauses here before the first write. The design leans on:
///
///  * **The whole plan is previewed.** The user applies or discards it while
///    the page is still untouched. HTML actions also get a live sandbox.
///  * **Every applied step is named.** "Added a 4x3 table", "Rewrote a block".
///  * **One Undo puts everything back.** The page is snapshotted between
///    validation and the first edit, and Undo restores that exact state. Not
///    Ctrl-Z nine times, guessing how many.
///  * **Destructive steps are counted separately.** Adding three things and
///    deleting three things are not the same event, and the summary says which.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/note_page.dart';
import '../../core/models/section.dart';
import '../../core/services/ai/ai_artifacts.dart';
import '../../core/services/page_content_repository.dart';
import '../auth/auth_notifier.dart';
import '../editor/page_content_provider.dart';
import '../../ui/colors.dart';
import '../../ui/organic.dart';
import '../settings/settings_state.dart';
import '../shell/dialogs/text_input_dialog.dart';
import '../shell/shell_state.dart' as shell;
import '../../ui/theme.dart';
import '../../ui/widgets/mario_loader.dart';
import '../editor/html_preview.dart';
import 'agent_actions.dart';
import 'agent_task.dart';
import 'ai_history.dart';
import 'ai_progress.dart';
import 'ai_progress_view.dart';
import 'ai_session_state.dart';
import 'ai_state.dart';
import 'mario_skills.dart';
import 'mario_tools.dart';
import 'note_images.dart';

class AgentPanel extends ConsumerStatefulWidget {
  const AgentPanel({super.key});

  @override
  ConsumerState<AgentPanel> createState() => _AgentPanelState();
}

class _AgentPanelState extends ConsumerState<AgentPanel> {
  @override
  void initState() {
    super.initState();
    // An instruction handed over by the panel's composer, collected once on
    // mount — the same route `/ask` takes into the Ask tab. The panel remounts
    // this tab on every hand-off, which is what makes a second instruction run
    // while the tab is already open.
    //
    // The TAKE has to be deferred too, not just the run. `takePending…` clears
    // the slot, so it writes to aiPanelProvider — and this tab is mounted BY
    // `runInstruction`, which sets the instruction and switches tab in one go.
    // Reading it straight from initState therefore modified a provider while
    // the tree that was mounting this widget was still building, and threw.
    // The Ask tab has always taken its pending question inside the callback;
    // this now matches it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending =
          ref.read(aiPanelProvider.notifier).takePendingInstruction();
      if (pending != null && pending.trim().isNotEmpty) {
        unawaited(_runInstruction(pending.trim()));
      }
    });
  }

  /// Runs one of the launcher's presets.
  ///
  /// It goes through [_runInstruction], the same path a typed instruction
  /// takes. It deliberately does *not* write itself into the composer first:
  /// a preset is three or four lines of prompt, and dropping that into the box
  /// and leaving it there reads as "nothing happened, here is your text" —
  /// which is exactly how it was read. What was asked shows in the run's own
  /// progress list instead, where it belongs.
  Future<void> _runPreset(_PagePreset preset) async {
    if (ref.read(aiEditorBridgeProvider) == null) return;

    var instruction = preset.instruction;
    if (preset.asksLanguage) {
      // The design names no target language. Picking one here would translate
      // somebody's page into a language they never chose, so it is asked for.
      final language = await showTextInputDialog(
        context,
        title: 'Translate this page',
        label: 'Into which language?',
        submitLabel: 'Translate',
      );
      if (language == null || language.trim().isEmpty) return;
      if (!mounted) return;
      instruction = instruction.replaceAll('{language}', language.trim());
    }

    await _runInstruction(instruction);
  }

  Future<void> _runInstruction(String instruction) async {
    final bridge = ref.read(aiEditorBridgeProvider);
    if (instruction.isEmpty || bridge == null) return;

    // Everything from `ref` is read before the first await: the run outlives
    // this widget.
    final session = ref.read(agentSessionProvider.notifier);
    final current = ref.read(agentSessionProvider);
    final settings = ref.read(settingsProvider.notifier);
    final task = ref.read(agentTaskProvider);
    final reader = ref.read(noteImageReaderProvider);
    final selection = ref.read(shell.selectionProvider.notifier);
    // The container, not `ref`: the tools run after awaits, and after this
    // widget may have been remounted for a second instruction.
    final container = ProviderScope.containerOf(context, listen: false);
    final tools = MarioTools(
      sync: ref.read(shell.syncServiceProvider),
      content: GetIt.I<PageContentRepository>(),
      loadIndex: () => _loadIndex(container),
      loadContent: (fileId) =>
          container.read(pageContentProvider(fileId).future),
      webSearch: ref.read(webSearchProvider),
      uid: ref.read(authStateProvider).valueOrNull?.uid ??
          ref.read(authServiceProvider).currentUser?.uid ??
          '',
      bridge: bridge,
      onOpenPage: (page) => selection.selectPage(
        page.id,
        sectionId: page.sectionId,
        notebookId: page.notebookId,
      ),
    );
    final note = bridge.readPage();
    final document = bridge.readDocument();

    // The notebook's sections, by name, so the model can put a new page in
    // one that exists — and knows which one this page is in.
    final sections =
        ref.read(shell.sectionsStreamProvider(bridge.notebookId)).valueOrNull ??
            const [];
    final sectionName =
        sections.where((s) => s.id == bridge.sectionId).firstOrNull?.name;
    final notebookName = ref
        .read(shell.notebooksStreamProvider)
        .valueOrNull
        ?.where((n) => n.id == bridge.notebookId)
        .firstOrNull
        ?.name;

    // Text only: the agent is choosing *where* things go, and OCR labelled by
    // block id answers that. Sending the pictures themselves would multiply
    // the prefill of an already slow planning call.
    //
    // Guarded because this happens *before* there is a run to fail into. An
    // unreadable image — not on this device, Drive unreachable — used to throw
    // out of this method into nothing, and a tap on a preset then did visibly
    // nothing at all. The pictures are optional context; the instruction is
    // not, so a failure here costs the OCR and keeps the run.
    var images = const <NoteImage>[];
    try {
      images = await reader.read(document, loadBytes: false);
    } catch (_) {
      // Falls through with no images.
    }
    // The user's own skills, read fresh so an edit counts next time.
    final userSkills = await loadUserSkills();
    if (!mounted) return;

    final run = task.run(
      instruction: instruction,
      note: note,
      images: images,
      htmlArtifact: bridge.readHtmlArtifact(),
      useWeb: current.useWeb,
      sectionName: sectionName,
      sectionNames: [for (final s in sections) s.name],
      notebookName: notebookName,
      history: current.exchanges,
      userSkills: userSkills,
      reviewBeforeWriting: current.reviewBeforeWriting,
      onPlanned: session.reviewPlan,
      applyAction: (action) => _perform(action, bridge, settings, tools),
    );
    tools.run = run;
    session.start(run, instruction: instruction);
    _saveWhenDone(run, instruction: instruction, bridge: bridge);
    _rememberWhenDone(run, instruction: instruction, session: session);
  }

  /// The notebook tree through the shell's own providers — the ones the
  /// sidebar shows, and the ones a demo build swaps for fixtures.
  static Future<MarioIndex> _loadIndex(ProviderContainer container) async {
    final notebooks =
        await container.read(shell.notebooksStreamProvider.future);
    final sections = <String, List<Section>>{};
    final pages = <String, List<NotePage>>{};
    for (final nb in notebooks) {
      final secs =
          await container.read(shell.sectionsStreamProvider(nb.id).future);
      sections[nb.id] = secs;
      for (final s in secs) {
        pages[s.id] = await container.read(
          shell
              .pagesStreamProvider((notebookId: nb.id, sectionId: s.id)).future,
        );
      }
    }
    return MarioIndex(notebooks, sections, pages);
  }

  /// Keeps a finished run in the session's conversation, so the next
  /// instruction — a reply to the agent's question, a refinement — sees it.
  /// The notifier is captured, not `ref`: the run outlives this widget.
  void _rememberWhenDone(
    AiRun run, {
    required String instruction,
    required AgentSessionNotifier session,
  }) {
    void listener() {
      final s = run.value;
      if (s.status != AiRunStatus.done) return;
      run.removeListener(listener);
      final outcome = s.result;
      session.remember(AgentExchange(
        instruction: instruction,
        summary: outcome is AgentOutcome
            ? [
                if (outcome.summary.isNotEmpty) outcome.summary,
                if (outcome.applied.isNotEmpty)
                  'Did: ${outcome.applied.join('; ')}',
              ].join(' ')
            : s.answer,
        question: outcome is AgentOutcome ? outcome.question : null,
      ));
    }

    run.addListener(listener);
  }

  /// Persists a finished run, so the Do tab has a history like Ask's.
  ///
  /// Listens rather than awaits, and captures the store now, while `ref` is
  /// valid: the run outlives this widget — a local model can still be
  /// planning when the user switches tab — and reading `ref` from a listener
  /// that fires after disposal throws. Same shape as AskPanel._saveWhenDone.
  ///
  /// Only a run that reached a result is kept. A discarded preview finishes
  /// without one; it changed nothing, and there is nothing to come back to.
  void _saveWhenDone(
    AiRun run, {
    required String instruction,
    required AiEditorBridge bridge,
  }) {
    final store = ref.read(aiArtifactStoreProvider);
    void listener() {
      final s = run.value;
      if (s.status != AiRunStatus.done) return;
      run.removeListener(listener);
      final outcome = s.result;
      if (outcome is! AgentOutcome) return;
      final entry = DoEntry(
        id: 'do-${DateTime.now().microsecondsSinceEpoch}',
        pageId: bridge.pageId,
        instruction: instruction,
        summary: outcome.summary,
        applied: outcome.applied,
        failed: outcome.failed,
        dropped: outcome.dropped,
        provenance: AiProvenance(
          backend: s.backendLabel ?? 'unknown',
          model: '',
          createdAt: DateTime.now(),
        ),
      );
      // Best-effort: the outcome is on screen either way, and the store keeps
      // a local copy when Drive is unreachable.
      store.addDo(bridge.notebookId, entry).ignore();
    }

    run.addListener(listener);
  }

  /// Routes one action: edits to the open page go to the executor through
  /// the bridge, the rest to the tools or to the settings.
  Future<AgentActionResult> _perform(
    AgentAction action,
    AiEditorBridge bridge,
    SettingsNotifier settings,
    MarioTools tools,
  ) async {
    AgentActionResult asResult(bool ok) =>
        ok ? const AgentActionResult.ok() : const AgentActionResult.failed();
    switch (action.kind) {
      case AgentActionKind.renamePage:
        return asResult(await bridge.renamePage(action.text));
      case AgentActionKind.createPage:
        if (action.notebook != null) return tools.perform(action);
        return asResult(await bridge.createPage(
          action.text,
          section: action.section,
          markdown: action.content,
        ));
      case AgentActionKind.createSection:
        if (action.notebook != null) return tools.perform(action);
        return asResult(await bridge.createSection(action.text));
      case AgentActionKind.renameSection:
        return asResult(
            await bridge.renameSection(action.text, section: action.section));
      case AgentActionKind.setting:
        return asResult(await _applySetting(action, settings));
      case AgentActionKind.htmlArtifact:
        return asResult(await bridge.setHtmlArtifact(action.text));
      case AgentActionKind.writePage:
        // The open page is written through the editor, so it is watched and
        // undoable; any other page goes through its file.
        if (tools.isCurrentPage(action.page)) {
          return asResult(await bridge.applyAgentAction(action));
        }
        return tools.perform(action);
      case AgentActionKind.createNotebook:
      case AgentActionKind.readPage:
      case AgentActionKind.listNotebooks:
      case AgentActionKind.listPages:
      case AgentActionKind.searchNotes:
      case AgentActionKind.webSearch:
      case AgentActionKind.openPage:
      case AgentActionKind.askUser:
        return tools.perform(action);
      default:
        final ok = await bridge.applyAgentAction(action);
        if (ok) return const AgentActionResult.ok();
        // The executor says only yes or no; the reason it says no is almost
        // always the same one, and the model can act on it.
        return AgentActionResult.failed(action.blockId != null
            ? 'block ${action.blockId} is not on this page any more — it '
                'may have been edited or removed; read the page again'
            : 'it could not be applied to the page');
    }
  }

  /// Applies one of the few settings an agent may touch.
  ///
  /// Parsed strictly and per-key rather than reflectively: the allowlist in
  /// agent_actions.dart says *which* keys, and this says what a valid value
  /// looks like, so a nonsense value changes nothing instead of something
  /// arbitrary.
  Future<bool> _applySetting(
      AgentAction action, SettingsNotifier settings) async {
    final value = (action.settingValue ?? '').trim().toLowerCase();
    switch (action.settingKey) {
      case 'theme':
        final mode = MarioThemeMode.values
            .where((m) => m.name.toLowerCase() == value)
            .firstOrNull;
        if (mode == null) return false;
        await settings.change((s) => s.copyWith(themeMode: mode));
        return true;
      case 'fontScale':
        final scale = double.tryParse(value);
        if (scale == null || scale < 0.5 || scale > 2.0) return false;
        await settings.change((s) => s.copyWith(fontScale: scale));
        return true;
      case 'canvasWidth':
        final width = CanvasWidth.values
            .where((w) => w.name.toLowerCase() == value)
            .firstOrNull;
        if (width == null) return false;
        await settings.change((s) => s.copyWith(canvasWidth: width));
        return true;
      case 'spellCheck':
        await settings.change((s) => s.copyWith(spellCheck: value == 'true'));
        return true;
      case 'autoCorrectMath':
        await settings
            .change((s) => s.copyWith(autoCorrectMath: value == 'true'));
        return true;
      default:
        return false;
    }
  }

  Future<void> _undo() async {
    final bridge = ref.read(aiEditorBridgeProvider);
    final snapshot = ref.read(agentSessionProvider).snapshot;
    if (bridge == null || snapshot == null) return;
    final session = ref.read(agentSessionProvider.notifier)..undoing();
    final ok = await bridge.restore(snapshot);
    session.undone(ok);
  }

  void _approvePlan() {
    final bridge = ref.read(aiEditorBridgeProvider);
    if (bridge == null) return;
    ref.read(agentSessionProvider.notifier).approve(bridge.snapshot());
  }

  void _discardPlan() {
    ref.read(agentSessionProvider.notifier).discardReview();
  }

  Future<void> _applyArtifactDraft() async {
    final bridge = ref.read(aiEditorBridgeProvider);
    final html = ref.read(agentSessionProvider).artifactDraft;
    if (bridge == null || html == null) return;
    final snapshot = bridge.snapshot();
    final ok = await bridge.setHtmlArtifact(html);
    if (!mounted) return;
    if (ok) {
      ref.read(agentSessionProvider.notifier).artifactApplied(snapshot);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(aiEditorBridgeProvider);
    final session = ref.watch(agentSessionProvider);
    final run = session.run;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: session.artifactDraft != null
              ? _ArtifactDraftPreview(
                  html: session.artifactDraft!,
                  applied: session.artifactApplied,
                  undone: session.undone,
                  canApply: bridge != null,
                  onApply: _applyArtifactDraft,
                  onDiscard:
                      ref.read(agentSessionProvider.notifier).discardArtifact,
                  onUndo: _undo,
                )
              : run == null
                  ? ListView(
                      padding: EdgeInsets.fromLTRB(
                          18, 18, 18, ComposerReserve.of(context)),
                      children: [
                        const _Intro(),
                        const SizedBox(height: MarioSpace.x6),
                        _ActOnThisPage(
                          enabled: bridge != null,
                          onRun: _runPreset,
                          reviewToggle: const _ReviewToggle(),
                        ),
                        DoHistoryList(onReplay: _runInstruction),
                      ],
                    )
                  : ValueListenableBuilder<AiRunState>(
                      valueListenable: run,
                      builder: (context, state, _) => ListView(
                        padding: EdgeInsets.fromLTRB(
                            12, 12, 12, ComposerReserve.of(context)),
                        children: [
                          AiProgressView(
                            state: state,
                            onCancel:
                                ref.read(agentSessionProvider.notifier).stop,
                          ),
                          if (state.error != null) ...[
                            const SizedBox(height: 10),
                            _Error(message: state.error!),
                          ],
                          if (session.review != null) ...[
                            const SizedBox(height: 12),
                            _PlanPreview(
                              plan: session.review!.plan,
                              canApply: bridge != null,
                              onApply: _approvePlan,
                              onDiscard: _discardPlan,
                            ),
                          ],
                          if (state.result is AgentOutcome) ...[
                            const SizedBox(height: 12),
                            _Outcome(
                              outcome: state.result as AgentOutcome,
                              undone: session.undone,
                              undoing: session.isUndoing,
                              canUndo:
                                  session.snapshot != null && bridge != null,
                              onUndo: _undo,
                              onFollowUp: bridge == null || state.isRunning
                                  ? null
                                  : _runInstruction,
                            ),
                          ],
                          // The launcher rides along under the result too. The
                          // agent session is app-level and never cleared, so the
                          // intro above is gone for good after the first run —
                          // without this the presets would be usable exactly once.
                          if (session.review == null) ...[
                            const SizedBox(height: MarioSpace.x6),
                            _ActOnThisPage(
                              enabled: bridge != null && !state.isRunning,
                              onRun: _runPreset,
                              reviewToggle: const _ReviewToggle(),
                            ),
                            // Earlier runs, under the launcher: the session
                            // holds one run, so this is the only way back to
                            // what a previous instruction did.
                            DoHistoryList(
                              onReplay:
                                  state.isRunning ? null : _runInstruction,
                            ),
                          ],
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}

class _PlanPreview extends StatelessWidget {
  const _PlanPreview({
    required this.plan,
    required this.canApply,
    required this.onApply,
    required this.onDiscard,
  });

  final AgentPlan plan;
  final bool canApply;
  final VoidCallback onApply;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final html = plan.actions
        .where((a) => a.kind == AgentActionKind.htmlArtifact)
        .firstOrNull
        ?.text;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Preview — nothing has changed yet',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          if (plan.summary.trim().isNotEmpty)
            Text(
              plan.summary,
              style: GoogleFonts.inter(fontSize: 11.5, height: 1.4),
            ),
          const SizedBox(height: 8),
          for (final action in plan.actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    action.isDestructive
                        ? Icons.warning_amber_rounded
                        : Icons.arrow_right,
                    size: 14,
                    color: action.isDestructive
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      action.summary,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (html != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 360,
              child: HtmlPreviewPane(
                html: html,
                isDark: Theme.of(context).brightness == Brightness.dark,
                title: 'Generated artifact · sandboxed',
                sandboxed: true,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: canApply ? onApply : null,
                icon: const Icon(Icons.check, size: 16),
                label: Text(html == null ? 'Apply changes' : 'Apply artifact'),
              ),
              TextButton(
                onPressed: onDiscard,
                child: const Text('Discard'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArtifactDraftPreview extends StatelessWidget {
  const _ArtifactDraftPreview({
    required this.html,
    required this.applied,
    required this.undone,
    required this.canApply,
    required this.onApply,
    required this.onDiscard,
    required this.onUndo,
  });

  final String html;
  final bool applied;
  final bool undone;
  final bool canApply;
  final Future<void> Function() onApply;
  final VoidCallback onDiscard;
  final Future<void> Function() onUndo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 10, 10, ComposerReserve.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: HtmlPreviewPane(
              html: html,
              isDark: Theme.of(context).brightness == Brightness.dark,
              title: 'AI artifact · sandboxed preview',
              sandboxed: true,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: !canApply || (applied && !undone) ? null : onApply,
                icon: Icon(applied && !undone ? Icons.check : Icons.save,
                    size: 16),
                label: Text(applied && !undone ? 'Applied' : 'Apply to page'),
              ),
              if (applied && !undone)
                OutlinedButton.icon(
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo, size: 16),
                  label: const Text('Undo'),
                ),
              TextButton(
                onPressed: onDiscard,
                child: const Text('Close preview'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const examples = [
      'Add a table comparing the three methods',
      'Turn the last paragraph into bullet points',
      'Add a Python example for this algorithm',
      'Rename this page to match its heading',
      'Create a page "Krebs cycle" with a summary of this one',
      'Find my notes on enzymes and pull them into one page',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.auto_fix_high, size: 26, color: scheme.onSurfaceVariant),
        const SizedBox(height: 10),
        Text(
          'Change the page',
          textAlign: TextAlign.center,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Say what you want and it edits the page directly — tables, code, '
          'formulas, spreadsheets, lists, the title — and can add pages and '
          'sections to the notebook. Every change is listed as it happens, '
          'and one Undo puts the page back.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
              fontSize: 11.5, height: 1.45, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        for (final e in examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              '“$e”',
              style: GoogleFonts.inter(
                fontSize: 11,
                height: 1.4,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ),
      ],
    );
  }
}

/// One row of the "Act on this page" launcher.
///
/// [instruction] is what the agent is handed, worded against the contract in
/// agent_task.dart rather than as a wish: it asks for the specific operations
/// [AgentActionKind] actually allows, and names blockId/afterBlockId where
/// placement matters, because the plan is validated in Dart and anything the
/// model invents outside that list is dropped rather than attempted.
class _PagePreset {
  const _PagePreset({
    required this.icon,
    required this.title,
    required this.description,
    required this.instruction,
    this.asksLanguage = false,
  });

  final IconData icon;
  final String title;
  final String description;

  /// Sent exactly as if it had been typed into the box below. Contains
  /// `{language}`, filled in before the run, when [asksLanguage].
  final String instruction;

  /// Whether to ask for a target language before running.
  final bool asksLanguage;
}

/// The design draws five rows. Four of them are here.
///
/// **"Split into pages" is still missing.** The agent can create pages now
/// (create_page, with a Markdown body), so the row is no longer impossible —
/// but a split also has to delete the moved blocks from this page, and a
/// one-tap preset that removes half of someone's page is a worse default
/// than a typed instruction whose plan they preview first. Better absent
/// than surprising.
const _presets = <_PagePreset>[
  _PagePreset(
    icon: Icons.checklist,
    title: 'Pull out the to-dos',
    description: 'Every action in the page as a checklist',
    instruction: 'Read the whole page and collect every task, action or next '
        'step it mentions. Add a level 2 heading "To do" at the end of the '
        'page, then one todo action underneath it with a single item per '
        'task, each worded as a short instruction. Do not change or remove '
        'anything already on the page.',
  ),
  _PagePreset(
    icon: Icons.table_chart,
    title: 'Make a table',
    description: 'Turn the bullet list into rows and columns',
    instruction: 'Find the bullet list on this page and turn it into a table. '
        'Add a table immediately after the list, using afterBlockId, whose '
        'first row is the column headers and which has one row per bullet, '
        'with each bullet split across those columns and every row the same '
        'width. Then delete the original bullet blocks by their ids. Change '
        'nothing else on the page.',
  ),
  _PagePreset(
    icon: Icons.translate,
    title: 'Translate',
    description: 'Keep the blocks, swap the language',
    // The language is asked for at the tap; see _AgentPanelState._runPreset.
    asksLanguage: true,
    instruction: 'Translate this page into {language}. For every block that '
        'has text, use replace_block with that block\'s id and the {language} '
        'translation of its text. Keep exactly the same blocks in the same '
        'order — the same headings, lists, tables, quotes and code — and do '
        'not add or delete a single block.',
  ),
  _PagePreset(
    icon: Icons.content_cut,
    title: 'Tighten the writing',
    description: 'Same meaning, fewer words',
    instruction: 'Tighten the writing on this page. For each paragraph or '
        'quote block that could be shorter, use replace_block with that '
        'block\'s id and a shorter version carrying the same meaning and '
        'every fact, name and number. Do not delete any block, do not touch '
        'headings, code, formulas, tables or lists, and do not add anything '
        'new.',
  ),
];

/// The launcher: preset instructions, one tap each.
class _ActOnThisPage extends StatelessWidget {
  const _ActOnThisPage({
    required this.enabled,
    required this.onRun,
    required this.reviewToggle,
  });

  /// The "Preview before writing" switch, shown with the kicker so it is
  /// seen before the first preset is tapped rather than found under them.
  final Widget reviewToggle;

  /// False with no page open, and while a run is in flight — a preset that
  /// queued a second plan on top of the first would leave two sets of edits
  /// and one snapshot.
  final bool enabled;

  final ValueChanged<_PagePreset> onRun;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MarioKicker('Act on this page'),
        reviewToggle,
        const SizedBox(height: MarioSpace.x2),
        for (final preset in _presets)
          _PresetRow(
            preset: preset,
            onTap: enabled ? () => onRun(preset) : null,
          ),
        const SizedBox(height: MarioSpace.x2),
        Text(
          'Mario works through the job and lists each step as it happens; '
          'Undo all puts the page back. Turn on Preview before writing to '
          'approve each step first.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.preset, required this.onTap});

  final _PagePreset preset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: MarioSpace.x1),
      // Its own Material: the panel's ink needs somewhere to land, and a
      // transparent one keeps whichever of the four grounds is showing.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(MarioRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MarioRadius.sm),
          child: Opacity(
            opacity: onTap == null ? 0.45 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MarioSpace.x2,
                vertical: MarioSpace.x2,
              ),
              child: Row(
                children: [
                  // The second accent, not the gold: gold on cream is the one
                  // pairing in this palette that does not carry a 17px glyph.
                  Icon(preset.icon, size: 17, color: scheme.secondary),
                  const SizedBox(width: MarioSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preset.title,
                          style: text.bodySmall?.copyWith(
                            fontSize: 12.5,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          preset.description,
                          style: text.bodySmall?.copyWith(
                            fontSize: 11.5,
                            height: 1.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: MarioSpace.x2),
                  Icon(Icons.chevron_right,
                      size: 16, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.outcome,
    required this.undone,
    required this.undoing,
    required this.canUndo,
    required this.onUndo,
    required this.onFollowUp,
  });

  final AgentOutcome outcome;
  final bool undone;
  final bool undoing;
  final bool canUndo;
  final VoidCallback onUndo;

  /// Runs a suggested next instruction. Null while nothing can run.
  final Future<void> Function(String instruction)? onFollowUp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: undone ? scheme.outlineVariant : MarioColors.primary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            undone
                ? 'Undone — the page is back as it was'
                : outcome.summary.isEmpty
                    ? 'Done'
                    : outcome.summary,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          if (!undone) ...[
            const SizedBox(height: 8),
            for (final line in outcome.applied)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check, size: 12, color: MarioColors.labelGreen),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(line,
                          style: GoogleFonts.inter(
                              fontSize: 11.5,
                              height: 1.35,
                              color: scheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            // Rewrites and deletions get their own line. "9 changes" reads very
            // differently once you know three of them removed something.
            if (outcome.destructive > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${outcome.destructive} of these changed or removed existing '
                  'content.',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
            // "Rejected as unsafe" was almost always a lie. One rejection —
            // a setting outside the allowlist — really is a guard refusing.
            // The rest are the model writing an action in a shape the parser
            // could not read, which is a defect, not a defence, and calling it
            // safety hid it. The reason is now on the line.
            if (outcome.failed > 0 || outcome.dropped > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    if (outcome.dropped > 0)
                      '${outcome.dropped} proposed change(s) could not be '
                          'used${outcome.dropReasons.isEmpty ? '' : ': '
                              '${outcome.dropReasons.join('; ')}'}',
                    if (outcome.failed > 0)
                      '${outcome.failed} step(s) could not be done',
                  ].join('. '),
                  style: GoogleFonts.inter(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
            // The agent stopped to ask. The reply goes in the box below; the
            // question rides along with it as context.
            if (outcome.question != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      outcome.question!,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Reply in the box below to carry on.',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
            if (outcome.followUps.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in outcome.followUps)
                    ActionChip(
                      label: Text(f),
                      labelStyle: GoogleFonts.inter(fontSize: 11.5),
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          onFollowUp == null ? null : () => onFollowUp!(f),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: canUndo && !undoing ? onUndo : null,
                  icon: undoing
                      // Disabled while undoing, so the fill is onSurface@12%,
                      // not primary; the theme default is what reads on it.
                      ? const MarioLoader(size: 18)
                      : const Icon(Icons.undo, size: 18),
                  label: const Text('Undo all'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: GoogleFonts.inter(
                        fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "Preview before writing": pause each writing step for approval, the way
/// every run used to. Off by default, so the agent works through; the step
/// list and Undo all are what stand in for the preview.
class _ReviewToggle extends ConsumerWidget {
  const _ReviewToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final value =
        ref.watch(agentSessionProvider.select((s) => s.reviewBeforeWriting));
    return Padding(
      padding: const EdgeInsets.only(top: MarioSpace.x2, bottom: MarioSpace.x1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Preview before writing',
              style: GoogleFonts.inter(
                  fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          MarioToggle(
            value: value,
            onChanged:
                ref.read(agentSessionProvider.notifier).setReviewBeforeWriting,
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          message,
          style: GoogleFonts.inter(
              fontSize: 12, height: 1.4, color: scheme.onErrorContainer),
        ),
      ),
    );
  }
}
