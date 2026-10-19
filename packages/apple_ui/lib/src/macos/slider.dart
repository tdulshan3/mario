import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/macos_tokens.dart';
import '_control_support.dart';

/// Slider styles of the kit page "Sliders and Dials".
enum MacSliderStyle {
  /// The accent fill runs from the start of the track to the knob (kit "Slider"). The usual case.
  linear,

  /// The fill runs from the middle to the knob; a midline marks the neutral middle (kit "Slider - Center-biased").
  /// For balance, pan, exposure −/+.
  centered,

  /// A round knob with a line that points at the value: 0 at the top, clockwise (kit "Dial (Circular Slider)").
  dial,
}

/// A macOS slider or dial (kit page "Sliders and Dials").
///
///     MacSlider(value: volume, onChanged: (v) => setState(() => volume = v))                          // 0…1
///     MacSlider(value: quality, min: 1, max: 5, ticks: 5, onChanged: (v) => setState(() => quality = v))  // snaps
///     MacSlider(value: balance, min: -1, max: 1, style: MacSliderStyle.centered, onChanged: …)
///     MacSlider(value: angle, min: 0, max: 360, style: MacSliderStyle.dial, semanticLabel: 'Angle', onChanged: …)
///
/// [onChanged] null = disabled. A linear slider fills the available width (160 when the width is unbounded, for
/// example in a Row: wrap it in `SizedBox(width: …)` or `Expanded`). The box is one knob wider than the knob's
/// travel, so the knob never sticks out. [ticks] (≥ 2) draws tick marks under the track and makes the knob snap to them.
/// Use [onChangeEnd] for expensive work (it runs once, when the mouse button is released).
/// Keyboard: arrows step (1 % or one tick), Page Up/Down 10 %, Home/End jump to the ends. No hover effect.
class MacSlider extends StatefulWidget {
  const MacSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.ticks,
    this.style = MacSliderStyle.linear,
    this.onChangeStart,
    this.onChangeEnd,
    this.semanticLabel,
    this.size,
    this.focusNode,
    this.autofocus = false,
  }) : assert(ticks == null || ticks >= 2, 'ticks must be at least 2');

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  /// Number of tick marks (and stops) under the track, e.g. 5 for 0 · 25 · 50 · 75 · 100 %. Null = continuous.
  final int? ticks;
  final MacSliderStyle style;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  /// Accessible name ("Volume"). Give every slider one (or a visible label next to it).
  final String? semanticLabel;
  final MacControlSize? size;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<MacSlider> createState() => _MacSliderState();
}

class _MacSliderState extends State<MacSlider> {
  bool _pressed = false;
  bool _focused = false;
  double? _dragValue;

  bool get _enabled => widget.onChanged != null;
  double get _span => widget.max - widget.min;

  double _fraction(double value) => _span <= 0 ? 0 : ((value - widget.min) / _span).clamp(0.0, 1.0);

  double _snap(double t) {
    final n = widget.ticks;
    if (n == null || widget.style == MacSliderStyle.dial) return t.clamp(0.0, 1.0);
    return (t * (n - 1)).round() / (n - 1);
  }

  double _valueAt(double t) => widget.min + _snap(t) * _span;

  void _emit(double value) {
    _dragValue = value;
    if (value != widget.value) widget.onChanged?.call(value);
  }

  double _fromPointer(Offset local, Size size, double knobW) {
    if (widget.style == MacSliderStyle.dial) {
      final c = size.center(Offset.zero);
      var a = math.atan2(local.dx - c.dx, -(local.dy - c.dy));
      if (a < 0) a += 2 * math.pi;
      return _valueAt(a / (2 * math.pi));
    }
    final travel = size.width - knobW;
    return _valueAt(travel <= 0 ? 0 : (local.dx - knobW / 2) / travel);
  }

  void _step(double fraction) {
    final n = widget.ticks;
    final t = _fraction(widget.value);
    final delta = n != null && widget.style != MacSliderStyle.dial ? fraction.sign * math.max(1, (fraction.abs() * (n - 1)).round()) / (n - 1) : fraction;
    var next = t + delta;
    if (widget.style == MacSliderStyle.dial) next = next % 1.0;
    final value = _valueAt(next.clamp(0.0, 1.0));
    widget.onChangeStart?.call(widget.value);
    _emit(value);
    widget.onChangeEnd?.call(value);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!_enabled) return KeyEventResult.ignored;
    if (controlKey(e, LogicalKeyboardKey.arrowRight) || controlKey(e, LogicalKeyboardKey.arrowUp)) {
      _step(0.01);
    } else if (controlKey(e, LogicalKeyboardKey.arrowLeft) || controlKey(e, LogicalKeyboardKey.arrowDown)) {
      _step(-0.01);
    } else if (controlKey(e, LogicalKeyboardKey.pageUp)) {
      _step(0.1);
    } else if (controlKey(e, LogicalKeyboardKey.pageDown)) {
      _step(-0.1);
    } else if (controlKey(e, LogicalKeyboardKey.home)) {
      _step(-1);
    } else if (controlKey(e, LogicalKeyboardKey.end)) {
      _step(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final look = ControlLook.of(context, widget.size);
    final s = look.s;
    final dial = widget.style == MacSliderStyle.dial;
    final ticked = widget.ticks != null && !dial;
    final knobW = ticked ? s.sliderKnobTickedSliderWidth : s.sliderKnobNonTickedSliderWidth;
    final knobH = ticked ? s.sliderKnobTickedSliderHeight : s.sliderKnobNonTickedSliderHeight;
    final h = s.globalHeight;
    final t = _fraction(widget.value);
    final pressed = _pressed && _enabled;

    Widget body = LayoutBuilder(builder: (context, constraints) {
      final size = dial ? Size(h, h) : Size(constraints.hasBoundedWidth ? constraints.maxWidth : 160, h);
      Widget painted;
      if (dial) {
        painted = CustomPaint(
          size: size,
          painter: _DialPainter(look: look, t: t, enabled: _enabled, pressed: pressed, focus: _focused ? look.focusColor : null),
        );
      } else {
        final cx = knobW / 2 + (size.width - knobW) * t;
        // Pressed: the same knob in light grey (the classic macOS slider; no Liquid Glass knob).
        final knob = ControlKnob(
          width: knobW,
          height: knobH,
          shadow: ControlShadow(0, 0.5, 6, 0, controlBlack(0.12)),
          color: pressed ? controlKnobPressed : controlWhiteSolid,
          focusRing: _focused ? look.focusColor : null,
        );
        painted = SizedBox.fromSize(
          size: size,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TrackPainter(
                  look: look,
                  t: t,
                  knobW: knobW,
                  ticks: ticked ? widget.ticks : null,
                  centered: widget.style == MacSliderStyle.centered,
                  enabled: _enabled,
                  pressed: pressed,
                ),
              ),
            ),
            Positioned(left: cx - knobW / 2, top: (h - knobH) / 2, width: knobW, height: knobH, child: knob),
          ]),
        );
      }
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _enabled
            ? (e) {
                setState(() => _pressed = true);
                widget.onChangeStart?.call(widget.value);
                _emit(_fromPointer(e.localPosition, size, knobW));
              }
            : null,
        onPointerMove: _enabled && _pressed ? (e) => _emit(_fromPointer(e.localPosition, size, knobW)) : null,
        onPointerUp: _enabled
            ? (e) {
                setState(() => _pressed = false);
                widget.onChangeEnd?.call(_dragValue ?? widget.value);
                _dragValue = null;
              }
            : null,
        onPointerCancel: _enabled ? (e) => setState(() => _pressed = false) : null,
        child: painted,
      );
    });

    body = Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: _enabled,
      skipTraversal: !_enabled,
      onKeyEvent: _onKey,
      onFocusChange: (f) => setState(() => _focused = f && FocusManager.instance.highlightMode == FocusHighlightMode.traditional),
      child: MouseRegion(cursor: SystemMouseCursors.basic, child: body),
    );
    final percent = (t * 100).round();
    return Semantics(
      slider: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      value: '$percent%',
      increasedValue: '${math.min(100, percent + 1)}%',
      decreasedValue: '${math.max(0, percent - 1)}%',
      onIncrease: _enabled ? () => _step(0.01) : null,
      onDecrease: _enabled ? () => _step(-0.01) : null,
      child: body,
    );
  }
}

/// Track, fill, ticks and midline (sliders.css background layers).
class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.look,
    required this.t,
    required this.knobW,
    required this.ticks,
    required this.centered,
    required this.enabled,
    required this.pressed,
  });
  final ControlLook look;
  final double t;
  final double knobW;
  final int? ticks;
  final bool centered;
  final bool enabled;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final s = look.s;
    final w = size.width;
    final h = size.height;
    final bar = 6 - 2 * s.sliderTrackInsetVertical;
    final overhang = 3 - s.sliderTrackInsetHorizontal;
    final end = knobW / 2 - overhang;
    final pos = knobW / 2 + (w - knobW) * t;
    final accent = look.accent;

    final tickColor = enabled ? look.ld(controlBlack(0.21), controlWhite(0.21)) : look.ld(controlBlack(0.085), controlWhite(0.085));
    final Color track;
    final Color fill;
    if (!enabled) {
      track = look.ld(controlBlack(0.05), controlWhite(0.05));
      fill = look.ld(controlBlack(0.05), controlWhite(0.05));
    } else if (pressed) {
      track = look.ld(controlBlack(0.16), controlWhite(0.16));
      fill = centered ? accent : controlMix(accent, 0.92, look.dark ? controlWhiteSolid : controlBlackSolid);
    } else {
      track = look.ld(controlBlack(0.085), controlWhite(0.085));
      fill = look.inactive ? look.ld(controlBlack(0.145), controlWhite(0.145)) : accent;
    }
    final midline = enabled ? look.c.labelTertiary : look.ld(controlBlack(0.085), controlWhite(0.085));
    final centerTick = enabled ? look.c.labelPrimary : look.ld(controlBlack(0.085), controlWhite(0.085));

    final trackRect = Rect.fromLTRB(end, h / 2 - bar / 2, w - end, h / 2 + bar / 2);
    final trackShape = RRect.fromRectAndRadius(trackRect, Radius.circular(bar / 2));
    canvas.drawRRect(trackShape, Paint()..color = track);

    canvas.save();
    canvas.clipRRect(trackShape);
    if (centered) {
      final a = math.min(w / 2 + 1, pos - overhang);
      final b = math.max(w / 2 - 1, pos + overhang);
      canvas.drawRect(Rect.fromLTRB(a, trackRect.top, b, trackRect.bottom), Paint()..color = fill);
    } else {
      canvas.drawRect(Rect.fromLTRB(end, trackRect.top, pos + overhang, trackRect.bottom), Paint()..color = fill);
    }
    canvas.restore();

    if (centered) {
      canvas.drawRect(Rect.fromLTRB(w / 2 - 1, trackRect.top, w / 2 + 1, trackRect.bottom), Paint()..color = midline);
    }

    final n = ticks;
    if (n != null) {
      // CSS background-position: calc(50% + …) resolves against (height − image height).
      final top = (h - 2) / 2 + bar / 2 + (centered ? 3 : 5);
      final period = (w - knobW) / (n - 1);
      final paint = Paint()..color = tickColor;
      for (var i = 0; i < n; i++) {
        final x = knobW / 2 - 1 + i * period;
        canvas.drawRect(Rect.fromLTWH(x + 0.15, top, 1.7, 2), paint);
      }
      if (centered) {
        final ct = (h - 4) / 2 + bar / 2 + 4;
        canvas.drawRect(Rect.fromLTRB(w / 2 - 1, ct, w / 2 + 1, ct + 4), Paint()..color = centerTick);
      }
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.t != t || old.knobW != knobW || old.ticks != ticks || old.centered != centered || old.enabled != enabled ||
      old.pressed != pressed || old.look.dark != look.dark || old.look.inactive != look.inactive ||
      old.look.accent != look.accent || old.look.size != look.size;
}

/// The dial: a bordered circle with a 2 px knob line that points at the value (0 = top, clockwise).
class _DialPainter extends CustomPainter {
  _DialPainter({required this.look, required this.t, required this.enabled, required this.pressed, required this.focus});
  final ControlLook look;
  final double t;
  final bool enabled;
  final bool pressed;
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final s = look.s;
    final rect = Offset.zero & size;
    final fill = !enabled ? look.borderedFillDisabled : (pressed ? look.borderedFillPressed : look.borderedFill);
    canvas.drawOval(rect, Paint()..color = fill);
    if (focus != null) paintFocusRing(canvas, rect, size.width / 2, focus!);
    final knob = enabled ? look.c.labelPrimary : look.c.labelTertiary;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(t * 2 * math.pi);
    final top = -size.height / 2 + s.dialInsetKnob;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-1, top, 2, s.dialHeightKnob), const Radius.circular(1)),
      Paint()..color = knob,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.t != t || old.enabled != enabled || old.pressed != pressed || old.focus != focus || old.look.dark != look.dark ||
      old.look.size != look.size;
}
