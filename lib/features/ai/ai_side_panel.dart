/// The AI panel, docked on the right of the editor.
///
/// It lives in [ShellScreen]'s Row rather than inside the editor's own column,
/// for two reasons. The editor canvas is wrapped in zoom, `Transform.scale`,
/// `OverflowBox` and a horizontal scroller whose sizing maths all assume it
/// owns its width; splitting that region is where the layout bugs live.
/// And an answer half-streamed should survive the user clicking another page
/// to check something, which a panel owned by the page cannot do.
///
/// Three tabs: Ask (which `/ask` and `/summary` drive), Quiz, and Writing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/widgets/resizable_panel.dart';
import '../settings/settings_screen.dart';
import 'ai_state.dart';
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
                loading: () => const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (e, _) => _NeedsSetup(message: 'Could not load AI settings: $e'),
                data: (configs) => configs.isEmpty
                    ? const _NeedsSetup(
                        message: 'No model is set up yet.\n\nMario can use a '
                            'local model through Ollama, any OpenAI-compatible '
                            'server on your network, OpenAI, or Claude.',
                      )
                    : switch (tab) {
                        AiPanelTab.ask => const AskPanel(),
                        AiPanelTab.quiz => const QuizPanel(),
                        AiPanelTab.writing => const WritingPanel(),
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

class _NeedsSetup extends StatelessWidget {
  const _NeedsSetup({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_outlined,
                size: 26, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
              icon: const Icon(Icons.tune, size: 15),
              label: const Text('Set up a model'),
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
}
