/// Which model is answering, and how much room it has left.
///
/// Both halves exist for the same reason: with several backends configured, the
/// same question gets a very different answer from a 0.8B on localhost than
/// from a 36B on the LAN or from Claude, and the difference is invisible unless
/// the panel says so. Switching used to mean a trip to Settings, which is far
/// enough away that people stop doing it and just live with whichever model
/// happened to be active.
///
/// The context readout matters most on a local model. A 40-page section against
/// an 8k window is silently truncated server-side — the answer covers the first
/// few pages and reads as though it covered everything — so seeing "8.1k / 8k"
/// is the difference between a confusing answer and an obvious one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/ai/llm_provider_config.dart';
import '../../ui/colors.dart';
import 'ai_progress.dart';
import 'ai_state.dart';

class ModelBar extends ConsumerWidget {
  const ModelBar({super.key, this.run});

  /// The run in progress, if any — its reported usage is what fills in the
  /// context readout.
  final AiRun? run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(aiConfigsProvider).valueOrNull ?? const [];
    if (configs.isEmpty) return const SizedBox.shrink();

    final backends = ref.watch(aiBackendsProvider);
    final active = backends.activeConfig;
    if (active == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModelPicker(
              configs: configs,
              active: active,
              onPick: (config) async {
                await backends.setActive(config.id);
                ref.invalidate(aiConfigsProvider);
              },
            ),
          ),
          if (run == null)
            _ContextChip(
                contextTokens: active.effectiveCapabilities.contextTokens)
          else
            ValueListenableBuilder<AiRunState>(
              valueListenable: run!,
              builder: (context, state, _) => _ContextChip(
                contextTokens: state.contextTokens ??
                    active.effectiveCapabilities.contextTokens,
                used: state.promptTokens,
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelPicker extends StatelessWidget {
  const _ModelPicker({
    required this.configs,
    required this.active,
    required this.onPick,
  });

  final List<LlmProviderConfig> configs;
  final LlmProviderConfig active;
  final ValueChanged<LlmProviderConfig> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // With one backend there is nothing to pick, so it reads as a label rather
    // than offering a menu that would only ever contain what is already shown.
    if (configs.length == 1) {
      return Row(
        children: [
          Icon(Icons.memory, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(child: _ActiveLabel(config: active)),
        ],
      );
    }

    return PopupMenuButton<LlmProviderConfig>(
      tooltip: 'Switch model',
      position: PopupMenuPosition.under,
      onSelected: onPick,
      itemBuilder: (context) => [
        for (final config in configs)
          PopupMenuItem(
            value: config,
            height: 42,
            child: Row(
              children: [
                Icon(
                  config.id == active.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 15,
                  color: config.id == active.id
                      ? MarioColors.primaryPressed
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(config.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                      Text(
                        '${config.model.isEmpty ? 'no model' : config.model}'
                        ' · ${_formatTokens(config.effectiveCapabilities.contextTokens)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 10.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Row(
        children: [
          Icon(Icons.memory, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(child: _ActiveLabel(config: active)),
          Icon(Icons.arrow_drop_down, size: 16, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _ActiveLabel extends StatelessWidget {
  const _ActiveLabel({required this.config});
  final LlmProviderConfig config;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The model, not the config label: "qwen3.6:latest" is what changes the
    // answer, where "LAN box" is only where it runs.
    final name = config.model.isEmpty ? config.label : config.model;
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    );
  }
}

/// The context window, and how much of it the last request used.
class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.contextTokens, this.used});

  final int contextTokens;

  /// Reported by the server. Null on a backend that does not say, in which case
  /// only the window is shown — a made-up estimate presented as a measurement
  /// would be worse than no number.
  final int? used;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction =
        used == null || contextTokens <= 0 ? null : used! / contextTokens;
    // Past about three-quarters, the next question in the same page is the one
    // that gets truncated.
    final tight = fraction != null && fraction > 0.75;

    return Tooltip(
      message: used == null
          ? 'Context window: ${_formatTokens(contextTokens)}'
          : 'Last request used ${_formatTokens(used!)} of '
              '${_formatTokens(contextTokens)}'
              '${tight ? ' — close to full, so longer notes may be cut' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fraction != null) ...[
              SizedBox(
                width: 22,
                height: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fraction.clamp(0, 1),
                    backgroundColor: scheme.outlineVariant,
                    color: tight ? scheme.error : MarioColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              used == null
                  ? _formatTokens(contextTokens)
                  : '${_formatTokens(used!)}/${_formatTokens(contextTokens)}',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: tight ? scheme.error : scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Token counts as people write them: 8k, 262k, 1.2M.
String _formatTokens(int tokens) {
  if (tokens <= 0) return '?';
  if (tokens >= 1000000) {
    final m = tokens / 1000000;
    return '${m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1)}M';
  }
  if (tokens >= 1000) {
    final k = tokens / 1000;
    return '${k >= 100 || k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}k';
  }
  return '$tokens';
}
