import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';

import '../core/theme.dart';

/// An iOS slider (kit page "Sliders"): a 6 pt track with the accent fill, a 38 × 24 white knob (it stays the same
/// while dragged, like the classic iOS slider), optional tick marks (one per stop) and symbols at both ends.
///
///     IosSlider(value: volume, onChanged: (v) => setState(() => volume = v), semanticLabel: 'Volume',
///         minIcon: CupertinoIcons.speaker_fill, maxIcon: CupertinoIcons.speaker_3_fill)
///     IosSlider(value: rating, min: 1, max: 5, divisions: 4, onChanged: setRating)   // 5 stops with tick marks
///     IosSlider(value: 0.4, onChanged: null)                                         // disabled (50% opacity)
/// [onChanged] null = disabled. Values run from [min] to [max] (default 0…1).
class IosSlider extends StatefulWidget {
  const IosSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.showTicks,
    this.minIcon,
    this.maxIcon,
    this.activeColor,
    this.semanticLabel,
  });

  final double value;

  /// Called while dragging with the new value. Null = disabled.
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;

  /// Number of steps between [min] and [max] (4 = five stops). Null = continuous.
  final int? divisions;

  /// Tick marks under the track, one per stop. Default: on when [divisions] is 1–10.
  final bool? showTicks;

  /// Symbol at the low end (kit "Symbol - Min"), e.g. a small speaker.
  final IconData? minIcon;

  /// Symbol at the high end (kit "Symbol - Max"), e.g. a loud speaker.
  final IconData? maxIcon;

  /// Fill colour. Default: the accent colour.
  final Color? activeColor;

  /// Accessible name, e.g. "Volume".
  final String? semanticLabel;

  @override
  State<IosSlider> createState() => _IosSliderState();
}

class _IosSliderState extends State<IosSlider> {
  bool _pressed = false;
  double _width = 0;

  bool get _enabled => widget.onChanged != null;
  double get _fraction =>
      widget.max > widget.min ? ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0) : 0;

  double _valueAt(double x) {
    var f = ((x - 19) / (_width - 38)).clamp(0.0, 1.0);
    if (Directionality.maybeOf(context) == TextDirection.rtl) f = 1 - f;
    final d = widget.divisions;
    if (d != null && d > 0) f = (f * d).round() / d;
    return widget.min + f * (widget.max - widget.min);
  }

  void _update(Offset local) {
    final v = _valueAt(local.dx);
    if (v != widget.value) widget.onChanged?.call(v);
  }

  void _start(Offset local) {
    setState(() => _pressed = true);
    widget.onChangeStart?.call(widget.value);
    _update(local);
  }

  void _end() {
    setState(() => _pressed = false);
    widget.onChangeEnd?.call(widget.value);
  }

  double get _step {
    final d = widget.divisions;
    return (widget.max - widget.min) / (d != null && d > 0 ? d : 10);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final d = widget.divisions;
    final ticks = (widget.showTicks ?? (d != null && d >= 1 && d <= 10)) && d != null && d >= 1 ? d + 1 : 0;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;

    Widget symbol(IconData icon) => SizedBox(
      width: 32,
      child: Center(child: Icon(icon, size: 20.4, color: c.labelSecondary, weight: 600)),
    );

    final track = LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTapDown: _enabled ? (e) => _start(e.localPosition) : null,
          onTapUp: _enabled ? (_) => _end() : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onHorizontalDragStart: _enabled ? (e) => _start(e.localPosition) : null,
          onHorizontalDragUpdate: _enabled ? (e) => _update(e.localPosition) : null,
          onHorizontalDragEnd: _enabled ? (_) => _end() : null,
          onHorizontalDragCancel: _enabled ? () => setState(() => _pressed = false) : null,
          child: CustomPaint(
            size: Size(constraints.maxWidth, 44),
            painter: _SliderPainter(
              fraction: rtl ? 1 - _fraction : _fraction,
              fillFromEnd: rtl,
              pressed: _pressed && _enabled,
              ticks: ticks,
              trackColor: c.fillPrimary,
              fillColor: widget.activeColor ?? theme.accentColor,
              tickColor: c.labelQuaternary,
              knobColor: c.white,
            ),
          ),
        );
      },
    );

    Widget slider = SizedBox(
      height: 44,
      child: Row(
        children: [
          if (widget.minIcon != null) ...[symbol(widget.minIcon!), const SizedBox(width: 12)],
          Expanded(child: track),
          if (widget.maxIcon != null) ...[const SizedBox(width: 12), symbol(widget.maxIcon!)],
        ],
      ),
    );
    if (!_enabled) slider = Opacity(opacity: 0.5, child: slider);

    final pct = '${(_fraction * 100).round()}%';
    return Semantics(
      slider: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      value: pct,
      increasedValue:
          '${(((widget.value + _step).clamp(widget.min, widget.max) - widget.min) / (widget.max - widget.min) * 100).round()}%',
      decreasedValue:
          '${(((widget.value - _step).clamp(widget.min, widget.max) - widget.min) / (widget.max - widget.min) * 100).round()}%',
      onIncrease: _enabled ? () => widget.onChanged!((widget.value + _step).clamp(widget.min, widget.max)) : null,
      onDecrease: _enabled ? () => widget.onChanged!((widget.value - _step).clamp(widget.min, widget.max)) : null,
      child: slider,
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({
    required this.fraction,
    required this.fillFromEnd,
    required this.pressed,
    required this.ticks,
    required this.trackColor,
    required this.fillColor,
    required this.tickColor,
    required this.knobColor,
  });

  final double fraction;
  final bool fillFromEnd;
  final bool pressed;
  final int ticks;
  final Color trackColor;
  final Color fillColor;
  final Color tickColor;
  final Color knobColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height / 2;
    // Track: 6 tall, radius 3 (kit "_Track", Fills/Primary).
    final trackRect = Rect.fromLTWH(0, cy - 3, w, 6);
    canvas.drawRRect(RRect.fromRectAndRadius(trackRect, const Radius.circular(3)), Paint()..color = trackColor);
    // Ticks: 4 pt dots 9 below the track centre, one under every knob stop (kit "_Ticks", Labels/Quaternary).
    if (ticks >= 2) {
      for (var i = 0; i < ticks; i++) {
        canvas.drawCircle(Offset(19 + i * (w - 38) / (ticks - 1), cy + 9), 2, Paint()..color = tickColor);
      }
    }
    // Fill: accent, from the start to fraction × width, round ends (kit "_Fill").
    final fw = fraction * w;
    if (fw > 0) {
      final fillRect = fillFromEnd ? Rect.fromLTWH(fw, cy - 3, w - fw, 6) : Rect.fromLTWH(0, cy - 3, fw, 6);
      canvas.drawRRect(RRect.fromRectAndRadius(fillRect, const Radius.circular(3)), Paint()..color = fillColor);
    }
    // Knob: 38 × 24, centre from 19 to width − 19. The same white knob while dragged (no Liquid Glass lens).
    final centre = Offset(19 + fraction * (w - 38), cy);
    final knob = RRect.fromRectAndRadius(
      Rect.fromCenter(center: centre, width: 38, height: 24),
      const Radius.circular(12),
    );
    // Kit shadows: 0 6 r13 black 12% and 0 0.5 r4 black 12%.
    canvas.drawRRect(
      knob.shift(const Offset(0, 6)),
      Paint()
        ..color = const Color(0x1F000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.5),
    );
    canvas.drawRRect(
      knob.shift(const Offset(0, 0.5)),
      Paint()
        ..color = const Color(0x1F000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawRRect(knob, Paint()..color = knobColor);
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.fraction != fraction ||
      old.fillFromEnd != fillFromEnd ||
      old.pressed != pressed ||
      old.ticks != ticks ||
      old.trackColor != trackColor ||
      old.fillColor != fillColor ||
      old.tickColor != tickColor ||
      old.knobColor != knobColor;
}
