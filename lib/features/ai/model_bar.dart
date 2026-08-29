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
import '../../core/services/ai/llm_service.dart';
import '../../core/services/ai/llm_types.dart';
import '../../ui/colors.dart';
import '../../ui/widgets/mario_loader.dart';
import 'ai_progress.dart';
import 'ai_state.dart';

class ModelBar extends ConsumerWidget {
  const ModelBar({super.key, this.run});

  /// The run in progress, if any — its reported usage is what fills in the
  /// context readout.
  final AiRun? run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Guarded because this bar renders unconditionally at the top of the panel,
    // above everything else. The backend providers resolve through get_it, so
    // in any context where DI has not been set up — a widget test, or a frame
    // before registration finishes — an unguarded read throws *here* and takes
    // the whole panel down with it, which is a far worse failure than showing
    // no bar.
    final List<LlmProviderConfig> configs;
    final AiBackends backends;
    try {
      configs = ref.watch(aiConfigsProvider).valueOrNull ?? const [];
      backends = ref.watch(aiBackendsProvider);
    } catch (_) {
      return const SizedBox.shrink();
    }
    if (configs.isEmpty) return const SizedBox.shrink();

    final active = backends.activeConfig;
    if (active == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              _EffortChip(
                effort: active.effort,
                onPick: (effort) async {
                  await backends.setEffort(active.id, effort);
                  ref.invalidate(aiConfigsProvider);
                },
              ),
              const SizedBox(width: 6),
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
          // What the model is doing right now. This bar already renders above
          // every tab, so putting the activity here gives Ask, Quiz, Writing
          // and Do the same readout for free rather than four of them.
          if (run != null)
            ValueListenableBuilder<AiRunState>(
              valueListenable: run!,
              builder: (context, state, _) => ModelActivityLine(state: state),
            ),
        ],
      ),
    );
  }
}

/// The live "what is it doing" line: the step that is running, whatever that
/// step chose to say about itself, and how long it has been at it.
///
/// Reads the run's own step list rather than inventing a vocabulary — the
/// steps already carry present-tense labels, and a detail like "page 3 of 12"
/// or the search query. Nothing is shown when no step is active, so an idle
/// panel stays quiet instead of asserting a status it does not have.
class ModelActivityLine extends StatelessWidget {
  const ModelActivityLine({super.key, required this.state});

  final AiRunState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (state.status == AiRunStatus.failed) {
      return _line(
        context,
        icon: Icon(Icons.error_outline, size: 13, color: scheme.error),
        text: state.error ?? 'Failed',
        colour: scheme.error,
      );
    }
    if (state.status != AiRunStatus.running) return const SizedBox.shrink();

    AiStep? active;
    for (final s in state.steps) {
      if (s.state == AiStepState.active) {
        active = s;
        break;
      }
    }
    // Running, but between steps — say so rather than going blank and looking
    // like nothing is happening.
    final label = active?.kind.label ?? 'Working';
    final detail = active?.detail;

    return _line(
      context,
      icon: const MarioLoader(size: 13),
      text: detail == null || detail.isEmpty ? label : '$label · $detail',
      colour: scheme.onSurfaceVariant,
      trailing: active?.elapsed,
    );
  }

  Widget _line(
    BuildContext context, {
    required Widget icon,
    required String text,
    required Color colour,
    Duration? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(width: 16, height: 16, child: Center(child: icon)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 11, color: colour),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Text(
              _elapsedLabel(trailing),
              style: GoogleFonts.inter(
                  fontSize: 11, color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }

  static String _elapsedLabel(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
    if (d.inSeconds < 60) {
      return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
    }
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
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

/// How hard the model should think before answering.
///
/// Beside the model rather than in Settings because it is a per-question
/// decision as often as a standing one: the same backend that should answer
/// "what does this paragraph mean" instantly should take its time over "write
/// me a hard quiz on this". It is saved against the backend, so the choice
/// sticks and can differ between a local model and a paid one.
class _EffortChip extends StatelessWidget {
  const _EffortChip({required this.effort, required this.onPick});

  final LlmEffort effort;
  final ValueChanged<LlmEffort> onPick;

  static const _labels = {
    LlmEffort.low: 'Fast',
    LlmEffort.medium: 'Balanced',
    LlmEffort.high: 'Thorough',
  };

  static const _blurbs = {
    LlmEffort.low: 'Answers straight away. Thinking off where the model '
        'supports turning it off.',
    LlmEffort.medium: 'Some deliberation before answering.',
    LlmEffort.high: 'Thinks it through first. Slower, and better on anything '
        'that needs reasoning rather than recall.',
  };

  static const _icons = {
    LlmEffort.low: Icons.bolt,
    LlmEffort.medium: Icons.balance,
    LlmEffort.high: Icons.psychology,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<LlmEffort>(
      tooltip: 'How hard to think',
      position: PopupMenuPosition.under,
      onSelected: onPick,
      itemBuilder: (context) => [
        for (final e in LlmEffort.values)
          PopupMenuItem(
            value: e,
            height: 48,
            child: Row(
              children: [
                Icon(
                  e == effort
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 15,
                  color: e == effort
                      ? MarioColors.primaryPressed
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_labels[e]!,
                          style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                      Text(_blurbs[e]!,
                          style: GoogleFonts.inter(
                              fontSize: 10.5,
                              height: 1.25,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icons[effort], size: 12, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              _labels[effort]!,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
