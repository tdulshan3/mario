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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/colors.dart';
import '../settings/settings_state.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/mario_loader.dart';
import 'agent_actions.dart';
import 'agent_task.dart';
import 'ai_progress.dart';
import 'ai_progress_view.dart';
import 'ai_session_state.dart';
import 'ai_state.dart';

class AgentPanel extends ConsumerStatefulWidget {
  const AgentPanel({super.key});

  @override
  ConsumerState<AgentPanel> createState() => _AgentPanelState();
}

class _AgentPanelState extends ConsumerState<AgentPanel> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: ref.read(agentSessionProvider).draft);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _run() {
    final instruction = _controller.text.trim();
    final bridge = ref.read(aiEditorBridgeProvider);
    if (instruction.isEmpty || bridge == null) return;

    final session = ref.read(agentSessionProvider.notifier);
    // Captured before the first await: the run outlives this widget.
    final settings = ref.read(settingsProvider.notifier);

    final run = ref.read(agentTaskProvider).run(
          instruction: instruction,
          note: bridge.readPage(),
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
    final scheme = Theme.of(context).colorScheme;
    final bridge = ref.watch(aiEditorBridgeProvider);
    final session = ref.watch(agentSessionProvider);
    final run = session.run;

    if (_controller.text != session.draft) {
      _controller.value = TextEditingValue(
        text: session.draft,
        selection: TextSelection.collapsed(offset: session.draft.length),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: run == null
              ? const _Intro()
              : ValueListenableBuilder<AiRunState>(
                  valueListenable: run,
                  builder: (context, state, _) => ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
                    ],
                  ),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                focusNode: _focus,
                enabled: bridge != null,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onChanged: ref.read(agentSessionProvider.notifier).setDraft,
                onSubmitted: (_) => _run(),
                style: GoogleFonts.inter(fontSize: 13),
                decoration: InputDecoration(
                  hintText: bridge == null
                      ? 'Open a page to edit it'
                      : 'Add a table of..., rename this page to...',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    tooltip: 'Make the change',
                    onPressed: bridge == null ? null : _run,
                  ),
                ),
              ),
            ],
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

    return ListView(
      padding: const EdgeInsets.all(18),
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
            if (outcome.failed > 0 || outcome.dropped > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    if (outcome.dropped > 0)
                      '${outcome.dropped} proposed change(s) were rejected as '
                          'unsafe',
                    if (outcome.failed > 0)
                      '${outcome.failed} could not be applied',
                  ].join('; '),
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
