/// The AI panel, docked on the right of the editor.
///
/// It lives in [ShellScreen]'s Row rather than inside the editor's own column,
/// for two reasons. The editor canvas is wrapped in zoom, `Transform.scale`,
/// `OverflowBox` and a horizontal scroller whose sizing maths all assume it
/// owns its width; splitting that region is where the layout bugs live.
/// And an answer half-streamed should survive the user clicking another page
/// to check something, which a panel owned by the page cannot do.
///
/// Four tabs: Ask (which `/ask` and `/summary` drive), Quiz, Writing, and Do
/// — the agent, which edits the page directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/widgets/resizable_panel.dart';
import '../../core/services/ai/local_model_discovery.dart';
import 'ai_session_state.dart';
import '../../ui/widgets/mario_loader.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_state.dart';
import 'ai_state.dart';
import 'agent_panel.dart';
import 'ask_panel.dart';
import 'quiz_panel.dart';
import 'writing_panel.dart';

/// The panel plus its collapsed strip. Renders nothing when closed except a
/// hairline rail, so the editor keeps its full width.
class AiSidePanel extends ConsumerWidget {
  const AiSidePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(aiPanelProvider);

    // Highlighting a passage brings the panel up on the Ask tab, ready to
    // answer about it. Listened for here rather than inside AskPanel, because
    // when the panel is shut AskPanel is not in the tree to hear it — which is
    // exactly the case that needs to open it.
    //
    // The editor only publishes a selection that has settled and is long enough
    // to be deliberate (see _onSelectionChanged), so this does not fire on
    // every drag while someone is editing.
    final askOnHighlight =
        ref.watch(settingsProvider).valueOrNull?.askOnHighlight ?? true;
    ref.listen<String?>(editorSelectionProvider, (previous, next) {
      if (!askOnHighlight) return;
      if (next == null || next.trim().isEmpty) return;
      if (previous == next) return;
      ref.read(askSessionProvider.notifier).quote(next);
      ref.read(aiPanelProvider.notifier).showTab(AiPanelTab.ask);
    });

    if (!panel.isOpen) return const SizedBox.shrink();

    return ResizablePanel(
      edge: PanelEdge.left,
      initialWidth: 360,
      minWidth: 280,
      maxWidth: 560,
      child: _PanelBody(tab: panel.tab),
    );
  }
}

class _PanelBody extends ConsumerWidget {
  const _PanelBody({required this.tab});

  final AiPanelTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final backends = ref.watch(aiConfigsProvider);
    final notifier = ref.read(aiPanelProvider.notifier);

    return Material(
      color: scheme.surfaceContainerHighest,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              tab: tab,
              onTab: notifier.showTab,
              onClose: notifier.close,
            ),
            const Divider(height: 1),
            Expanded(
              child: backends.when(
                loading: () => const Center(child: MarioLoader(size: 30)),
                error: (e, _) =>
                    _NeedsSetup(message: 'Could not load AI settings: $e'),
                data: (configs) => configs.isEmpty
                    ? const _NeedsSetup()
                    : switch (tab) {
                        AiPanelTab.ask => const AskPanel(),
                        AiPanelTab.quiz => const QuizPanel(),
                        AiPanelTab.writing => const WritingPanel(),
                        AiPanelTab.agent => const AgentPanel(),
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.tab,
    required this.onTab,
    required this.onClose,
  });

  final AiPanelTab tab;
  final ValueChanged<AiPanelTab> onTab;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        children: [
          _TabChip(
            label: 'Ask',
            icon: Icons.auto_awesome,
            selected: tab == AiPanelTab.ask,
            onTap: () => onTab(AiPanelTab.ask),
          ),
          const SizedBox(width: 6),
          _TabChip(
            label: 'Quiz',
            icon: Icons.quiz_outlined,
            selected: tab == AiPanelTab.quiz,
            onTap: () => onTab(AiPanelTab.quiz),
          ),
          const SizedBox(width: 6),
          _TabChip(
            label: 'Writing',
            icon: Icons.spellcheck,
            selected: tab == AiPanelTab.writing,
            onTap: () => onTab(AiPanelTab.writing),
          ),
          const SizedBox(width: 6),
          _TabChip(
            label: 'Do',
            icon: Icons.auto_fix_high,
            selected: tab == AiPanelTab.agent,
            onTap: () => onTab(AiPanelTab.agent),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? scheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? scheme.outlineVariant : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// First run: nothing configured yet.
///
/// Rather than only pointing at Settings, this looks for a model server already
/// running on this machine and offers it directly — someone with Ollama going
/// should be one tap from a working panel, not a form.
class _NeedsSetup extends ConsumerWidget {
  const _NeedsSetup({this.message});
  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final found = ref.watch(localModelsProvider);

    final detected = found.maybeWhen(
      data: (endpoints) => endpoints,
      orElse: () => const <DiscoveredEndpoint>[],
    );
    final best = detected.isEmpty ? null : detected.first;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_outlined,
                size: 26, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              message ??
                  'No model is set up yet.\n\nMario can use a local model '
                      'through Ollama, any OpenAI-compatible server on your '
                      'network, OpenAI, or Claude.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (found.isLoading) ...[
              const SizedBox(height: 14),
              const MarioLoader(size: 20),
              const SizedBox(height: 6),
              Text('Looking for a local model server…',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
            if (best != null) ...[
              const SizedBox(height: 14),
              Text(
                '${best.serverName} is running here with '
                '${best.models.length} model'
                '${best.models.length == 1 ? '' : 's'}.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 11.5,
                    height: 1.4,
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              for (final m in best.models.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: FilledButton.icon(
                    onPressed: () => _use(ref, best, m.name),
                    icon: const Icon(Icons.bolt, size: 15),
                    label: Text(
                      m.sizeLabel.isEmpty
                          ? 'Use ${m.name}'
                          : 'Use ${m.name}  ·  ${m.sizeLabel}',
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: GoogleFonts.inter(
                          fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
              icon: const Icon(Icons.tune, size: 15),
              label: Text(best == null ? 'Set up a model' : 'More options'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Saves the picked model and makes it active, so the panel is usable
  /// immediately rather than after a trip to Settings.
  Future<void> _use(
      WidgetRef ref, DiscoveredEndpoint endpoint, String model) async {
    final backends = ref.read(aiBackendsProvider);
    final config = endpoint.toConfig(
      model,
      id: 'llm-${DateTime.now().microsecondsSinceEpoch}',
    );
    await backends.saveConfigs([...backends.configs, config]);
    await backends.setActive(config.id);
    ref.invalidate(aiConfigsProvider);
  }
}
