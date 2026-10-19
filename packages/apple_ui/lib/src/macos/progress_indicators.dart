import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '../core/theme.dart';

/// Colours shared by the progress indicators (kit "Progress Indicators", macos.css `.mac-progress`).
class _ProgressColors {
  _ProgressColors(BuildContext context, {bool indeterminate = false}) {
    final theme = AppleTheme.of(context);
    final inactive = MacWindowState.isInactive(context);
    final base = theme.isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    // Track: label primary × 10 % (× 6 % in an inactive window, except the indeterminate bar).
    track = base.withValues(alpha: inactive && !indeterminate ? 0.051 : 0.085);
    stroke = theme.mac.progressTrackStroke; // 0.5 px inside: black 7 % · white 4 %
    // Fill: the accent; label primary × 17 % when the window is not focused (kit Active=False).
    fill = inactive ? base.withValues(alpha: 0.145) : theme.accentColor;
  }

  late final Color track;
  late final Color stroke;
  late final Color fill;
}

/// A linear progress bar (kit "Linear - Determinate" / "Linear - Indeterminate"): an accent capsule on a grey
/// track, 10 px tall (6 px at the small and mini control sizes). [value] 0.0–1.0; null = indeterminate
/// (a segment sweeps left → right every 1.5 s). Turns grey in an inactive window.
///
///     MacProgressBar(value: 0.4, semanticLabel: 'Downloading')            // 40 %
///     MacProgressBar(semanticLabel: 'Loading')                            // indeterminate
///     MacProgressBar(value: done / total, size: MacControlSize.small)     // 6 px bar
///
/// It fills the width it gets (100 when unbounded). Prefer determinate; never let the value go backwards.
class MacProgressBar extends StatefulWidget {
  const MacProgressBar({super.key, this.value, this.semanticLabel, this.size, this.width});

  /// 0.0 … 1.0. Null = indeterminate.
  final double? value;

  /// Accessible name ("Downloading", "Exporting 3 of 12 files").
  final String? semanticLabel;

  /// Control size. Null = the nearest [MacControlSizeScope]. Mini and small draw the 6 px bar.
  final MacControlSize? size;

  /// Fixed width. Null = fill the available width.
  final double? width;

  @override
  State<MacProgressBar> createState() => _MacProgressBarState();
}

class _MacProgressBarState extends State<MacProgressBar> with SingleTickerProviderStateMixin {
  AnimationController? _sweep;

  void _sync() {
    if (widget.value == null) {
      // Starts mid-sweep (the kit's pose): visible at once, and frozen there when tickers are muted.
      _sweep ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 1500), value: 0.5)..repeat();
    } else {
      _sweep?.dispose();
      _sweep = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(MacProgressBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _sweep?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controlSize = widget.size ?? MacControlSizeScope.of(context);
    final h = controlSize == MacControlSize.mini || controlSize == MacControlSize.small ? 6.0 : 10.0;
    final colors = _ProgressColors(context, indeterminate: widget.value == null);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final v = widget.value?.clamp(0.0, 1.0);

    Widget bar;
    if (v != null) {
      bar = TweenAnimationBuilder<double>(
        tween: Tween(end: v),
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
        curve: Curves.ease,
        builder: (context, t, _) => CustomPaint(painter: _BarPainter(colors, value: t)),
      );
    } else {
      bar = AnimatedBuilder(
        animation: _sweep!,
        builder: (context, _) {
          final t = _sweep!.value;
          if (reduceMotion) {
            // Reduce Motion: the segment stays centred and pulses (opacity 1 ↔ 0.4).
            final pulse = 1 - 0.6 * (1 - (2 * t - 1).abs());
            return CustomPaint(painter: _BarPainter(colors, sweep: 0.5, segmentOpacity: pulse));
          }
          return CustomPaint(painter: _BarPainter(colors, sweep: Curves.easeInOut.transform(t)));
        },
      );
    }

    return Semantics(
      label: widget.semanticLabel,
      value: v == null ? null : '${(v * 100).round()}%',
      child: SizedBox(
        height: h,
        child: widget.width != null
            ? SizedBox(width: widget.width, child: bar)
            : LimitedBox(
                maxWidth: 100,
                child: SizedBox(width: double.infinity, child: bar),
              ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.colors, {this.value, this.sweep, this.segmentOpacity = 1});
  final _ProgressColors colors;
  final double? value;
  final double? sweep;
  final double segmentOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final track = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(h / 2));
    canvas.drawRRect(track, Paint()..color = colors.track);
    canvas.save();
    canvas.clipRRect(track);
    if (value != null) {
      // Determinate: a capsule from the left; 0 % still shows a round dot (min width = height).
      final fw = math.max(h, value! * w);
      canvas.drawRRect(RRect.fromLTRBR(0, 0, fw, h, Radius.circular(h / 2)), Paint()..color = colors.fill);
    } else {
      // Indeterminate: a 48 %-wide segment that fades in from the left and ends in a round cap.
      final segW = 0.48 * w;
      final x = -segW + sweep! * (w + segW);
      final bodyEnd = x + segW - h / 2;
      final fill = colors.fill.withValues(alpha: colors.fill.a * segmentOpacity);
      final body = Rect.fromLTRB(x, 0, bodyEnd, h);
      canvas.drawRect(body, Paint()..shader = LinearGradient(colors: [fill.withValues(alpha: 0), fill]).createShader(body));
      canvas.drawPath(
        Path()
          ..moveTo(bodyEnd, 0)
          ..arcTo(Rect.fromCircle(center: Offset(bodyEnd, h / 2), radius: h / 2), -math.pi / 2, math.pi, false)
          ..close(),
        Paint()..color = fill,
      );
    }
    canvas.restore();
    // 0.5 px track outline inside the edge, drawn on top (kit "Track - Stroke").
    canvas.drawRRect(
      track.deflate(0.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = colors.stroke,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.value != value ||
      old.sweep != sweep ||
      old.segmentOpacity != segmentOpacity ||
      old.colors.fill != colors.fill ||
      old.colors.track != colors.track;
}

/// A circular determinate progress indicator (kit "Circular - Determinate"): a 5 px ring that fills clockwise from
/// 12 o'clock with the accent colour. 16 px, or 32 px with [large]. For known progress in a tight spot
/// (a table row, a toolbar, next to a file name).
///
///     MacProgressCircle(value: 0.75, semanticLabel: 'Uploading')
///     MacProgressCircle(value: progress, large: true, semanticLabel: 'Exporting')
class MacProgressCircle extends StatelessWidget {
  const MacProgressCircle({super.key, required this.value, this.large = false, this.semanticLabel});

  /// 0.0 … 1.0.
  final double value;

  /// 32 px instead of 16 px.
  final bool large;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = _ProgressColors(context);
    final size = large ? 32.0 : 16.0;
    final v = value.clamp(0.0, 1.0);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: semanticLabel,
      value: '${(v * 100).round()}%',
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: v),
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.ease,
          builder: (context, t, _) => CustomPaint(painter: _CirclePainter(colors, t)),
        ),
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  _CirclePainter(this.colors, this.value);
  final _ProgressColors colors;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    const ring = 5.0;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final mid = r - ring / 2;
    // Track: the 5 px ring, with 0.5 px outlines on its outer and inner edges.
    canvas.drawCircle(
      c,
      mid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring
        ..color = colors.track,
    );
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = colors.stroke;
    canvas.drawCircle(c, r - 0.25, outline);
    canvas.drawCircle(c, r - ring + 0.25, outline);
    // Fill: an arc from 12 o'clock, round caps at both ends (a dot at 0 %).
    final fill = Paint()..color = colors.fill;
    final angle = value * 2 * math.pi;
    if (angle <= 0.0001) {
      canvas.drawCircle(Offset(c.dx, c.dy - mid), ring / 2, fill);
    } else if (value >= 1) {
      canvas.drawCircle(
        c,
        mid,
        fill
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring,
      );
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: mid),
        -math.pi / 2,
        angle,
        false,
        fill
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CirclePainter old) => old.value != value || old.colors.fill != colors.fill || old.colors.track != colors.track;
}

/// The spinner (kit "Circular - Indeterminate"): 8 spokes that step clockwise, for short waits of unknown
/// length ("Loading…", "Connecting…"). 16 px, or 32 px with [large] (only when it is alone in an empty view).
///
///     MacSpinner()                                   // 16 px, "Loading"
///     MacSpinner(large: true, semanticLabel: 'Connecting')
class MacSpinner extends StatefulWidget {
  const MacSpinner({super.key, this.large = false, this.semanticLabel = 'Loading'});

  /// 32 px instead of 16 px.
  final bool large;
  final String semanticLabel;

  @override
  State<MacSpinner> createState() => _MacSpinnerState();
}

class _MacSpinnerState extends State<MacSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce Motion: half speed (macos.css).
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final d = Duration(seconds: reduce ? 2 : 1);
    if (_turn.duration != d) {
      _turn.duration = d;
      if (_turn.isAnimating) _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppleTheme.of(context).mac.labelPrimary;
    final size = widget.large ? 32.0 : 16.0;
    return Semantics(
      label: widget.semanticLabel,
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: _turn,
          builder: (context, _) => CustomPaint(painter: _SpinnerPainter(color, (_turn.value * 8).floor() % 8)),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.color, this.step);
  final Color color;
  final int step;

  // Opacity of each spoke, clockwise from 12 o'clock (macos.css / kit: the top spoke is the darkest).
  static const _alpha = [0.55, 0.0825, 0.1485, 0.2145, 0.2805, 0.3465, 0.4125, 0.4785];

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 16;
    canvas.save();
    canvas.scale(k);
    canvas.translate(8, 8);
    canvas.rotate(step * math.pi / 4);
    for (var i = 0; i < 8; i++) {
      canvas.drawRRect(
        RRect.fromLTRBR(-1, -8, 1, -3, const Radius.circular(1)),
        Paint()..color = color.withValues(alpha: color.a * _alpha[i]),
      );
      canvas.rotate(math.pi / 4);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.step != step || old.color != color;
}
