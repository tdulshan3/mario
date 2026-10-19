import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '_control_support.dart';

/// An iOS stepper (kit page "Steppers"): − and + in a 92 × 32 grey capsule. Tap to change the value by [step];
/// hold to repeat. The stepper never shows the value: put it in the label next to it ("Guests: 3").
///
///     Row(children: [
///       Expanded(child: Text('Guests: $guests')),
///       IosStepper(value: guests, min: 1, max: 10, onChanged: (v) => setState(() => guests = v), semanticLabel: 'Guests'),
///     ])
/// [onChanged] null = disabled. − is disabled at [min], + at [max].
class IosStepper extends StatefulWidget {
  const IosStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = double.negativeInfinity,
    this.max = double.infinity,
    this.step = 1,
    this.semanticLabel,
  });

  final double value;

  /// Receives the new value. Null = disabled.
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final double step;

  /// Accessible name, e.g. "Guests".
  final String? semanticLabel;

  @override
  State<IosStepper> createState() => _IosStepperState();
}

class _IosStepperState extends State<IosStepper> {
  int _pressed = 0; // -1 = minus, 1 = plus
  Timer? _timer;
  bool _repeated = false;
  late double _latest = widget.value;

  @override
  void didUpdateWidget(IosStepper old) {
    super.didUpdateWidget(old);
    _latest = widget.value;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _canStep(int dir) => widget.onChanged != null && (dir < 0 ? _latest > widget.min : _latest < widget.max);

  bool _stepBy(int dir) {
    if (!_canStep(dir)) return false;
    final next = ((_latest + dir * widget.step) * 1e6).roundToDouble() / 1e6;
    _latest = next.clamp(widget.min, widget.max);
    widget.onChanged!(_latest);
    return true;
  }

  void _down(int dir) {
    setState(() => _pressed = dir);
    _repeated = false;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        _repeated = true;
        if (!_stepBy(dir)) t.cancel();
      });
    });
  }

  void _up() {
    _timer?.cancel();
    if (mounted && _pressed != 0) setState(() => _pressed = 0);
  }

  Widget _half(BuildContext context, int dir) {
    final c = AppleTheme.of(context).ios;
    final dark = AppleTheme.of(context).isDark;
    final enabled = widget.onChanged != null && (dir < 0 ? widget.value > widget.min : widget.value < widget.max);
    final interactive = widget.onChanged != null;
    final pressed = enabled && _pressed == dir;
    // Kit: Default = Fills/Tertiary + Labels/Primary; Pressed = Fills/Quaternary + black 8%; Disabled = Fills/Quaternary + Labels/Tertiary.
    final fill = !enabled
        ? c.fillQuaternary
        : pressed
        ? Color.alphaBlend(dark ? const Color(0x14FFFFFF) : const Color(0x14000000), c.fillQuaternary)
        : c.fillTertiary;
    final radius = dir < 0
        ? const BorderRadius.horizontal(left: Radius.circular(16))
        : const BorderRadius.horizontal(right: Radius.circular(16));
    return IosMinTapArea(
      minSize: const Size(46, 44),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: dir < 0 ? 'Decrease' : 'Increase',
        onTap: enabled ? () => _stepBy(dir) : null,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Callbacks stay attached while the stepper is enabled (a half that reaches its limit mid-hold must not
          // lose its recognizer); each callback checks the half itself.
          onTapDown: interactive
              ? (_) {
                  if (_canStep(dir)) _down(dir);
                }
              : null,
          onTapUp: interactive ? (_) => _up() : null,
          onTapCancel: interactive ? _up : null,
          onTap: interactive
              ? () {
                  if (_repeated) {
                    _repeated = false;
                    return;
                  }
                  _stepBy(dir);
                }
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(color: fill, borderRadius: radius),
            child: SizedBox(
              width: 46,
              height: 32,
              child: CustomPaint(
                painter: _StepperGlyphPainter(plus: dir > 0, color: enabled ? c.labelPrimary : c.labelTertiary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    final canUp = widget.onChanged != null && widget.value < widget.max;
    final canDown = widget.onChanged != null && widget.value > widget.min;
    // VoiceOver: an adjustable element (swipe up / down), like UIStepper.
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      value: fmt(widget.value),
      increasedValue: canUp ? fmt((widget.value + widget.step).clamp(widget.min, widget.max)) : null,
      decreasedValue: canDown ? fmt((widget.value - widget.step).clamp(widget.min, widget.max)) : null,
      onIncrease: canUp ? () => _stepBy(1) : null,
      onDecrease: canDown ? () => _stepBy(-1) : null,
      child: SizedBox(
        width: 92,
        height: 32,
        child: Stack(
          children: [
            Row(children: [_half(context, -1), _half(context, 1)]),
            // Separator: 1 × 24 at x 45.5, Labels/Tertiary.
            Positioned(
              left: 45.5,
              top: 4,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: c.labelTertiary, borderRadius: BorderRadius.circular(1)),
                  child: const SizedBox(width: 1, height: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SF Symbols "minus" / "plus" at 17 pt Semibold: 14 wide, 2 thick, round ends.
class _StepperGlyphPainter extends CustomPainter {
  _StepperGlyphPainter({required this.plus, required this.color});
  final bool plus;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c - const Offset(6, 0), c + const Offset(6, 0), p);
    if (plus) canvas.drawLine(c - const Offset(0, 6), c + const Offset(0, 6), p);
  }

  @override
  bool shouldRepaint(_StepperGlyphPainter old) => old.plus != plus || old.color != color;
}
