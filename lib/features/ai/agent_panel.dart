/// The Do tab — tell the model to change the page, and watch it happen.
///
/// This is the one place in Mario where a model writes into the user's notes
/// without them reading the result first, so the design leans hard on three
/// things:
///
///  * **Every step is named as it happens.** "Added a 4x3 table", "Rewrote a
///    block" — not a spinner and a finished page.
///  * **One Undo puts everything back.** The page is snapshotted between
///    validation and the first edit, and Undo restores that exact state. Not
///    Ctrl-Z nine times, guessing how many.
///  * **Destructive steps are counted separately.** Adding three things and
///    deleting three things are not the same event, and the summary says which.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/colors.dart';
import '../../ui/organic.dart';
import '../settings/settings_state.dart';
import '../shell/dialogs/text_input_dialog.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/mario_loader.dart';
import 'agent_actions.dart';
import 'agent_task.dart';
import 'ai_progress.dart';
import 'ai_progress_view.dart';
import 'ai_session_state.dart';
import 'ai_state.dart';
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
    final settings = ref.read(settingsProvider.notifier);
    final task = ref.read(agentTaskProvider);
    final reader = ref.read(noteImageReaderProvider);
    final note = bridge.readPage();
    final document = bridge.readDocument();

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
    if (!mounted) return;

    final run = task.run(
      instruction: instruction,
      note: note,
      images: images,
      useWeb: ref.read(agentSessionProvider).useWeb,
      onPlanned: (_) => session.snapshotTaken(bridge.snapshot()),
      applyAction: (action) => _perform(action, bridge, settings),
    );
    session.start(run, instruction: instruction);
  }

  /// Routes one action: document edits go to the executor, the two that are
  /// not document edits are handled here.
  Future<bool> _perform(
    AgentAction action,
    AiEditorBridge bridge,
    SettingsNotifier settings,
  ) async {
    switch (action.kind) {
      case AgentActionKind.renamePage:
        return bridge.renamePage(action.text);
      case AgentActionKind.setting:
        return _applySetting(action, settings);
      default:
        return bridge.applyAgentAction(action);
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

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(aiEditorBridgeProvider);
    final session = ref.watch(agentSessionProvider);
    final run = session.run;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: run == null
              ? ListView(
                  padding: EdgeInsets.fromLTRB(
                      18, 18, 18, ComposerReserve.of(context)),
                  children: [
                    const _Intro(),
                    const SizedBox(height: MarioSpace.x6),
                    _ActOnThisPage(
                      enabled: bridge != null,
                      onRun: _runPreset,
                    ),
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
                        onCancel: ref.read(agentSessionProvider.notifier).stop,
                      ),
                      if (state.error != null) ...[
                        const SizedBox(height: 10),
                        _Error(message: state.error!),
                      ],
                      if (state.result is AgentOutcome) ...[
                        const SizedBox(height: 12),
                        _Outcome(
                          outcome: state.result as AgentOutcome,
                          undone: session.undone,
                          undoing: session.isUndoing,
                          canUndo: session.snapshot != null && bridge != null,
                          onUndo: _undo,
                        ),
                      ],
                      // The launcher rides along under the result too. The
                      // agent session is app-level and never cleared, so the
                      // intro above is gone for good after the first run —
                      // without this the presets would be usable exactly once.
                      const SizedBox(height: MarioSpace.x6),
                      _ActOnThisPage(
                        enabled: bridge != null && !state.isRunning,
                        onRun: _runPreset,
                      ),
                    ],
                  ),
                ),
        ),
      ],
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
      'Add a spreadsheet for the experiment results',
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
          'formulas, spreadsheets, lists, the title. Every change is listed as '
          'it happens, and one Undo puts everything back.',
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
/// **"Split into pages" is deliberately missing.** It would have to write new
/// pages into the section, and nothing in this feature can: [AgentActionKind]
/// is an allowlist with no create-page member, and [AiEditorBridge] exposes
/// only the open page — read it, edit its blocks, rename it. A row for it
/// would plan something, drop every action as unknown, and fail every time it
/// was pressed. Better absent than broken.
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
///
/// The note at the foot is **not** the line the design writes. The design
/// promises "every action previews its change and asks before writing to the
/// page", and this agent does no such thing: [AgentTask] asks for a plan,
/// validates it, snapshots the page and then writes, with no preview and no
/// confirmation anywhere between. What it does have is the running commentary
/// and the one-press Undo, so that is what the line says.
class _ActOnThisPage extends StatelessWidget {
  const _ActOnThisPage({required this.enabled, required this.onRun});

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
        const SizedBox(height: MarioSpace.x2),
        for (final preset in _presets)
          _PresetRow(
            preset: preset,
            onTap: enabled ? () => onRun(preset) : null,
          ),
        const SizedBox(height: MarioSpace.x2),
        Text(
          'Changes are written straight to the page. Each one is named as it '
          'happens, and Undo all puts the page back.',
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
  });

  final AgentOutcome outcome;
  final bool undone;
  final bool undoing;
  final bool canUndo;
  final VoidCallback onUndo;

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
                      '${outcome.failed} could not be applied to the page',
                  ].join('. '),
                  style: GoogleFonts.inter(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
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
