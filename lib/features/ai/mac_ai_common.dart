/// The pieces every tab of the desktop AI inspector shares.
///
/// The desktop builds draw the AI panel as a macOS inspector (see
/// `mac_ai_side_panel.dart`), and each tab keeps its own logic in its own
/// file. What they have in common is how things *look*: an icon button that
/// names itself in a tooltip, a small grey group title, a step list for a run
/// in flight, an error note, an empty pane with an action under it. Those live
/// here so the four tabs read as one panel rather than four.
///
/// Everything in this file is apple_ui widgets, `context.macColors` and
/// [MacTypography]; nothing here is used by the Material (web) build.
library;

import 'package:apple_ui/apple_ui.dart';
// Selectable text is content, not chrome: the model's raw output has to be
// copyable, and apple_ui has no selectable text of its own.
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/widgets.dart';

import 'ai_progress.dart';

/// An icon-only borderless button with its name in a tooltip.
///
/// macOS icon buttons in an inspector have no bezel; the tooltip uses the same
/// words as the accessible name, as tooltips.md asks.
class MacAiIconButton extends StatelessWidget {
  const MacAiIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;

  /// The accessible name, and the tooltip unless [tooltip] says more.
  final String label;
  final VoidCallback? onPressed;

  /// A longer explanation than [label], where the icon needs one.
  final String? tooltip;

  @override
  Widget build(BuildContext context) => MacTooltip(
        message: tooltip ?? label,
        child: MacButton(
          icon: icon,
          semanticLabel: label,
          style: MacButtonStyle.borderless,
          onPressed: onPressed,
        ),
      );
}

/// A small grey title over a group of rows ("Earlier Questions").
///
/// The kit's group title: 11 px, semibold, secondary label colour.
class MacAiGroupTitle extends StatelessWidget {
  const MacAiGroupTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(
          text,
          style: MacTypography.of(context)
              .emphasized(MacTextSpecs.subheadline)
              .copyWith(color: context.macColors.labelSecondary),
        ),
      );
}

/// Body text in a label colour — the one text style most of the panel uses.
class MacAiText extends StatelessWidget {
  const MacAiText(
    this.text, {
    super.key,
    this.secondary = false,
    this.small = false,
    this.emphasized = false,
    this.color,
    this.maxLines,
    this.textAlign,
  });

  final String text;

  /// Secondary label colour rather than primary.
  final bool secondary;

  /// Subheadline (11 px) rather than body (13 px).
  final bool small;
  final bool emphasized;

  /// Overrides the label colour (an error, a success).
  final Color? color;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final t = MacTypography.of(context);
    final c = context.macColors;
    final spec = small ? MacTextSpecs.subheadline : MacTextSpecs.body;
    final base =
        emphasized ? t.emphasized(spec) : (small ? t.subheadline : t.body);
    return Text(
      text,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textAlign: textAlign,
      style: base.copyWith(
          color: color ?? (secondary ? c.labelSecondary : c.labelPrimary)),
    );
  }
}

/// A thin rule in the separator colour, as between macOS panes.
class MacAiSeparator extends StatelessWidget {
  const MacAiSeparator({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 1, child: ColoredBox(color: context.macColors.separator));
}

/// An empty pane: the kit's "No Items" text, with an optional button row.
///
/// [MacEmptyState] alone has no room for an action, and most of the panel's
/// empty states have one ("Check This Page", "Set Up a Model…").
class MacAiEmpty extends StatelessWidget {
  const MacAiEmpty({
    super.key,
    required this.title,
    this.message,
    this.actions = const [],
  });

  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return MacEmptyState(title: title, message: message);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MacEmptyState(title: title, message: message),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// A run's error, said plainly in red, with what the model actually returned
/// behind a disclosure when there is any.
///
/// The detail is diagnostic, not an answer — but with a local model it is
/// usually the fastest way to tell a rambling reply from a truncated one, so
/// it stays one click away.
class MacAiErrorNote extends StatefulWidget {
  const MacAiErrorNote({super.key, required this.message, this.detail});

  final String message;
  final String? detail;

  @override
  State<MacAiErrorNote> createState() => _MacAiErrorNoteState();
}

class _MacAiErrorNoteState extends State<MacAiErrorNote> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final t = MacTypography.of(context);
    final raw = widget.detail?.trim();
    return MacGroupBox(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(AppleIcons.exclamationmarkTriangle,
                    size: 14, color: c.accentRed),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(widget.message,
                    style: t.body.copyWith(color: c.accentRed)),
              ),
            ],
          ),
          if (raw != null && raw.isNotEmpty) ...[
            const SizedBox(height: 8),
            MacDisclosure(
              title: 'What the Model Actually Said',
              open: _open,
              onToggle: (v) => setState(() => _open = v),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectableText(
                  // Capped: a runaway model can return a wall of text, and
                  // the first part is always the diagnostic part.
                  raw.length > 1200
                      ? '${raw.substring(0, 1200)}\n…(truncated)'
                      : raw,
                  style: t.subheadline.copyWith(
                    color: c.labelSecondary,
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Menlo', 'Consolas'],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The step list of a run, macOS style: a spinner on the step that is
/// running, a tick on the ones behind it, and Stop while it goes.
///
/// The desktop counterpart of `AiProgressView` — same rules: past tense once a
/// step is done, skipped steps struck through, the detail under its step.
class MacAiStepList extends StatelessWidget {
  const MacAiStepList({super.key, required this.state, this.onCancel});

  final AiRunState state;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    if (state.steps.isEmpty) return const SizedBox.shrink();
    return MacGroupBox(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final step in state.steps) _MacStepRow(step: step),
          if (state.isRunning && onCancel != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: MacButton(
                label: 'Stop',
                icon: AppleIcons.stop,
                onPressed: onCancel,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MacStepRow extends StatelessWidget {
  const _MacStepRow({required this.step});

  final AiStep step;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final t = MacTypography.of(context);
    final isActive = step.state == AiStepState.active;
    final isSkipped = step.state == AiStepState.skipped;
    final isFailed = step.state == AiStepState.failed;
    final color = switch (step.state) {
      AiStepState.active => c.labelPrimary,
      AiStepState.done => c.labelSecondary,
      AiStepState.failed => c.accentRed,
      AiStepState.pending || AiStepState.skipped => c.labelTertiary,
    };
    final label = (isActive ? t.bodyEmphasized : t.body).copyWith(
      color: color,
      decoration: isSkipped ? TextDecoration.lineThrough : null,
    );

    final Widget icon = switch (step.state) {
      AiStepState.active => const MacSpinner(semanticLabel: 'Working'),
      AiStepState.done =>
        Icon(AppleIcons.checkmark, size: 12, color: c.labelSecondary),
      AiStepState.failed =>
        Icon(AppleIcons.xmark, size: 12, color: c.accentRed),
      AiStepState.skipped =>
        Icon(AppleIcons.minus, size: 12, color: c.labelTertiary),
      AiStepState.pending => SizedBox.square(
          dimension: 5,
          child: DecoratedBox(
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: c.labelQuaternary),
          ),
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: 16, child: Center(child: icon)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Past tense once it is behind us, so a finished list reads as
                // a record of what happened rather than a stalled plan.
                Text(
                  step.state == AiStepState.done
                      ? step.kind.pastLabel
                      : step.kind.label,
                  style: label,
                ),
                if (step.detail != null && !isSkipped)
                  Text(
                    step.detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.subheadline.copyWith(
                        color: isFailed ? c.accentRed : c.labelSecondary),
                  ),
              ],
            ),
          ),
          if (step.elapsed != null && step.state == AiStepState.done)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                formatAiElapsed(step.elapsed!),
                style: t.subheadline.copyWith(
                  color: c.labelTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "850ms", "2.4s", "1m 5s" — how long a step took.
String formatAiElapsed(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  if (d.inSeconds < 60) {
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
  return '${d.inMinutes}m ${d.inSeconds % 60}s';
}

/// A link-like row that opens something: the pointer turns into a hand and
/// the whole row takes the click.
///
/// macOS has no ink or hover wash on content links, so this is the bare
/// gesture plus the cursor — used for a cited source, the one place in the
/// panel where a row of content opens a web page.
class MacAiLinkRow extends StatelessWidget {
  const MacAiLinkRow({super.key, required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      );
}
