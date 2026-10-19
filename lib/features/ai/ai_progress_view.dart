/// The step list the user watches while a request runs.
///
/// Reading the note · Searching the web · Thinking · Answering — drawn in full
/// from the start, with the current step lit and finished ones ticked. The
/// point is that a slow local model stops looking like a hang: you can see it
/// is on step three of four, and how long step two took.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/mac/mac_look.dart';
import '../../ui/widgets/mario_loader.dart';
import 'ai_progress.dart';
import 'mac_ai_common.dart';

class AiProgressView extends StatelessWidget {
  const AiProgressView({
    super.key,
    required this.state,
    this.onCancel,
  });

  final AiRunState state;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    // The desktop inspector draws the same list with apple_ui's spinner and
    // buttons; the rules for what each step says are the same in both.
    if (useMacLook) return MacAiStepList(state: state, onCancel: onCancel);
    if (state.steps.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final step in state.steps) _StepRow(step: step),
          if (state.isRunning && onCancel != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.stop_circle_outlined, size: 15),
                label: const Text('Stop'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final AiStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = step.state == AiStepState.active;
    final isSkipped = step.state == AiStepState.skipped;
    final isFailed = step.state == AiStepState.failed;

    final color = switch (step.state) {
      AiStepState.active => scheme.onSurface,
      AiStepState.done => scheme.onSurfaceVariant,
      AiStepState.failed => scheme.error,
      // Pending and skipped both read as "not the story right now"; skipped
      // additionally gets a strikethrough below so the two are distinguishable.
      AiStepState.pending ||
      AiStepState.skipped =>
        scheme.onSurfaceVariant.withValues(alpha: 0.45),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wide enough for the four-dot animation to read as four dots.
          SizedBox(
            width: 22,
            height: 20,
            child: Center(child: _StepIcon(state: step.state)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Past tense once it is behind us, so a finished list reads
                  // as a record of what happened rather than a stalled plan.
                  step.state == AiStepState.done
                      ? step.kind.pastLabel
                      : step.kind.label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.3,
                    color: color,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    decoration: isSkipped ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (step.detail != null && !isSkipped)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      step.detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        height: 1.25,
                        color: isFailed
                            ? scheme.error
                            : scheme.onSurfaceVariant.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (step.elapsed != null && step.state == AiStepState.done)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 1),
              child: Text(
                _formatElapsed(step.elapsed!),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.state});

  final AiStepState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (state) {
      case AiStepState.active:
        return const MarioLoader(size: 16);
      case AiStepState.done:
        return Icon(Icons.check, size: 13, color: scheme.onSurfaceVariant);
      case AiStepState.failed:
        return Icon(Icons.close, size: 13, color: scheme.error);
      case AiStepState.skipped:
        return Icon(Icons.remove,
            size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.4));
      case AiStepState.pending:
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
          ),
        );
    }
  }
}

String _formatElapsed(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  if (d.inSeconds < 60) {
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
  return '${d.inMinutes}m ${d.inSeconds % 60}s';
}
