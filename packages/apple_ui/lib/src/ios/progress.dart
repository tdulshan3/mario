import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '../core/typography.dart';

/// An iOS progress bar (kit page "Progress Indicators", "Progress Bar - Determinate Linear"): a 4 pt accent bar on a
/// Fills/Primary capsule track, optionally with a label above (kit "Show Label"). For work of known length.
///
///     IosProgressBar(value: 0.4)
///     IosProgressBar(value: done / total, label: 'Importing Photos…')
/// [value] is 0…1; null = not started (empty track). Unknown duration: use [IosSpinner]. Fills the width it gets.
class IosProgressBar extends StatelessWidget {
  const IosProgressBar({super.key, required this.value, this.label, this.color, this.semanticLabel});

  final double? value;

  /// Text above the bar (Body, Labels/Primary, 3 above the track).
  final String? label;

  /// Fill colour. Default: the accent colour.
  final Color? color;

  /// Accessible name when there is no [label].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final v = (value ?? 0).clamp(0.0, 1.0);
    final bar = TweenAnimationBuilder<double>(
      tween: Tween(end: v),
      duration: const Duration(milliseconds: 250),
      builder: (context, t, _) => CustomPaint(
        size: const Size(double.infinity, 4),
        painter: _ProgressBarPainter(t, c.fillPrimary, color ?? theme.accentColor),
      ),
    );
    return Semantics(
      label: label ?? semanticLabel,
      value: value == null ? null : '${(v * 100).round()}%',
      child: label == null
          ? SizedBox(height: 4, width: double.infinity, child: bar)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label!, style: IosTypography.of(context).body),
                const SizedBox(height: 3),
                SizedBox(height: 4, child: bar),
              ],
            ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter(this.value, this.track, this.fill);
  final double value;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    if (value > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width * value, size.height), r),
        Paint()..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressBarPainter old) => old.value != value || old.track != track || old.fill != fill;
}

/// Small 14 · Regular 20 (default) · Large 35 (kit Size).
enum IosSpinnerSize { small, regular, large }

/// The iOS activity indicator (kit "Progress Bar - Indeterminate Circular (Spinner)"): 8 rounded spokes in
/// Labels/Secondary, fading from 100% to 15%, turning clockwise in 8 steps per second. For work of unknown length.
///
///     const IosSpinner()
///     const IosSpinner(size: IosSpinnerSize.large)
///     const IosSpinner(label: 'Loading…')
class IosSpinner extends StatefulWidget {
  const IosSpinner({
    super.key,
    this.size = IosSpinnerSize.regular,
    this.label,
    this.color,
    this.animating = true,
    this.semanticLabel,
  });

  final IosSpinnerSize size;

  /// Text after the spinner (Body, Labels/Secondary).
  final String? label;

  /// Spoke colour. Default: Labels/Secondary (use white over photos).
  final Color? color;

  /// False = frozen (the first frame).
  final bool animating;

  /// Accessible name when there is no [label]. Default "Loading".
  final String? semanticLabel;

  @override
  State<IosSpinner> createState() => _IosSpinnerState();
}

class _IosSpinnerState extends State<IosSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void initState() {
    super.initState();
    if (widget.animating) _turn.repeat();
  }

  @override
  void didUpdateWidget(IosSpinner old) {
    super.didUpdateWidget(old);
    if (widget.animating && !_turn.isAnimating) _turn.repeat();
    if (!widget.animating && _turn.isAnimating) _turn.stop();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    final color = widget.color ?? c.labelSecondary;
    final side = switch (widget.size) {
      IosSpinnerSize.small => 14.0,
      IosSpinnerSize.regular => 20.0,
      IosSpinnerSize.large => 35.0,
    };
    final spinner = AnimatedBuilder(
      animation: _turn,
      builder: (context, _) => CustomPaint(
        size: Size.square(side),
        painter: _SpinnerPainter(size: widget.size, step: (_turn.value * 8).floor() % 8, color: color),
      ),
    );
    return Semantics(
      label: widget.label ?? widget.semanticLabel ?? 'Loading',
      excludeSemantics: true,
      child: widget.label == null
          ? spinner
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                spinner,
                SizedBox(width: widget.size == IosSpinnerSize.small ? 4 : 8),
                Text(widget.label!, style: IosTypography.of(context).body.copyWith(color: color)),
              ],
            ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({required this.size, required this.step, required this.color});
  final IosSpinnerSize size;
  final int step;
  final Color color;

  // Opacity of the spoke at 0°, 45°, … (clockwise from the top): the trail fades counter-clockwise.
  static const _opacity = [1.0, 0.15, 0.27, 0.39, 0.51, 0.63, 0.75, 0.87];

  @override
  void paint(Canvas canvas, Size s) {
    // Kit spokes: Small 2 × 4 · Regular 2.7 × 6.7 · Large 5 × 13, from the outer edge inwards, fully rounded.
    final (w, h) = switch (size) {
      IosSpinnerSize.small => (2.0, 4.0),
      IosSpinnerSize.regular => (2.7, 6.7),
      IosSpinnerSize.large => (5.0, 13.0),
    };
    final c = s.center(Offset.zero);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(step * math.pi / 4);
    for (var i = 0; i < 8; i++) {
      final spoke = RRect.fromRectAndRadius(Rect.fromLTWH(-w / 2, -s.height / 2, w, h), Radius.circular(w / 2));
      canvas.drawRRect(spoke, Paint()..color = color.withValues(alpha: color.a * _opacity[i]));
      canvas.rotate(math.pi / 4);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.size != size || old.step != step || old.color != color;
}

/// circular: a 270° ring open at the bottom with a dot at the value · capacity: a full ring that fills clockwise.
enum IosGaugeStyle { circular, capacity }

/// An iOS gauge (SwiftUI `Gauge` with `.accessoryCircular` / `.accessoryCircularCapacity`; kit page "Widgets",
/// Lock Screen "Open Gauge" / "Closed Gauge"): a 58 pt ring, 6 thick. For a level within a range (battery, speed,
/// air quality), not for progress over time.
///
///     IosGauge(value: 0.72, label: 'CPU')
///     IosGauge(value: 72, min: 50, max: 90, currentValueLabel: '72', minLabel: '50', maxLabel: '90')
///     IosGauge(value: 0.4, style: IosGaugeStyle.capacity)
class IosGauge extends StatelessWidget {
  const IosGauge({
    super.key,
    required this.value,
    this.min = 0,
    this.max = 1,
    this.style = IosGaugeStyle.circular,
    this.currentValueLabel,
    this.label,
    this.minLabel,
    this.maxLabel,
    this.tint,
    this.trackColor,
    this.surfaceColor,
    this.semanticLabel,
  });

  final double value;
  final double min;
  final double max;
  final IosGaugeStyle style;

  /// Text in the middle (Medium 17). Default: the value as a percentage.
  final String? currentValueLabel;

  /// Small text in the opening at the bottom (circular), e.g. "CPU".
  final String? label;

  /// Small texts at the two ends of the ring (circular). Use instead of [label].
  final String? minLabel;
  final String? maxLabel;

  /// Ring colour. Default: the accent colour.
  final Color? tint;

  /// Colour of the ring behind the value: the whole ring (circular, default [tint]) or the empty part (capacity,
  /// default Fills/Secondary).
  final Color? trackColor;

  /// The colour behind the gauge: cuts the gap around the dot. Default: Backgrounds/Primary.
  final Color? surfaceColor;

  /// Accessible name. Default: [label].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final fraction = max > min ? ((value - min) / (max - min)).clamp(0.0, 1.0) : 0.0;
    final capacity = style == IosGaugeStyle.capacity;
    TextStyle text(double size, Color color, double line) => appleFont(size: size).copyWith(
      fontSize: size,
      height: line / size,
      fontWeight: FontWeight.w500,
      color: color,
      letterSpacing: size >= 17 ? -0.43 : 0,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: TextDecoration.none,
    );
    Widget centred(double top, double height, String s, TextStyle style) => Positioned(
      left: 0,
      right: 0,
      top: top,
      height: height,
      child: Text(
        s,
        style: style,
        textAlign: TextAlign.center,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
      ),
    );
    return Semantics(
      label: semanticLabel ?? label,
      value: currentValueLabel ?? '${(fraction * 100).round()}%',
      excludeSemantics: true,
      child: SizedBox(
        width: 58,
        height: 58,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _GaugePainter(
                  fraction: fraction,
                  capacity: capacity,
                  tint: tint ?? theme.accentColor,
                  track: trackColor ?? (capacity ? c.fillSecondary : (tint ?? theme.accentColor)),
                  surface: surfaceColor ?? c.bgPrimary,
                ),
              ),
            ),
            centred(
              capacity ? 19 : 18,
              20,
              currentValueLabel ?? '${(fraction * 100).round()}%',
              text(17, c.labelPrimary, 20),
            ),
            if (!capacity && label != null) centred(41, 18, label!, text(12, c.labelSecondary, 18)),
            if (!capacity && minLabel != null)
              Positioned(
                left: 10,
                top: 44,
                width: 16,
                height: 13,
                child: Text(
                  minLabel!,
                  style: text(11, c.labelSecondary, 13),
                  textAlign: TextAlign.center,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                ),
              ),
            if (!capacity && maxLabel != null)
              Positioned(
                left: 32,
                top: 44,
                width: 16,
                height: 13,
                child: Text(
                  maxLabel!,
                  style: text(11, c.labelSecondary, 13),
                  textAlign: TextAlign.center,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.capacity,
    required this.tint,
    required this.track,
    required this.surface,
  });
  final double fraction;
  final bool capacity;
  final Color tint;
  final Color track;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    const centre = Offset(29, 29);
    const r = 26.0;
    final rect = Rect.fromCircle(center: centre, radius: r);
    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (capacity) {
      canvas.drawCircle(centre, r, stroke(track)..strokeCap = StrokeCap.butt);
      if (fraction > 0) canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction, false, stroke(tint));
      return;
    }
    // 270° from the lower left (135°) clockwise, round ends.
    const start = 3 * math.pi / 4;
    const sweep = 3 * math.pi / 2;
    canvas.drawArc(rect, start, sweep, false, stroke(track));
    final a = start + sweep * fraction;
    final dot = centre + Offset(math.cos(a), math.sin(a)) * r;
    canvas.drawCircle(dot, 4.35, Paint()..color = surface); // 1.5 gap around the dot
    canvas.drawCircle(dot, 2.85, Paint()..color = tint); // 5.7 dot
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.capacity != capacity ||
      old.tint != tint ||
      old.track != track ||
      old.surface != surface;
}
