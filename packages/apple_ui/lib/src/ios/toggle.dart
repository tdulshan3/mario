import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '_control_support.dart';

/// An iOS switch (kit page "Toggles", "Toggle - Switch"): a 64 × 28 capsule, green when on, with a 38 × 24 white knob
/// that stretches 8 pt towards the middle while pressed (the classic iOS switch). For on/off settings that take effect
/// immediately.
///
///     IosToggle(value: wifi, onChanged: (v) => setState(() => wifi = v), semanticLabel: 'Wi-Fi')
///     IosToggle(value: true, onChanged: null)                         // disabled (50% opacity)
///     IosToggle(value: on, onChanged: set, showOnOffLabels: true)     // Accessibility "On/Off Labels"
/// [onChanged] null = disabled. Tap or drag the knob. In a list row, make the whole row toggle it too.
class IosToggle extends StatefulWidget {
  const IosToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.showOnOffLabels = false,
    this.semanticLabel,
    this.surfaceColor,
  });

  /// On (true) or off.
  final bool value;

  /// Receives the new value. Null = disabled.
  final ValueChanged<bool>? onChanged;

  /// Track colour when on. Default: system green (iOS switches are green, not the accent colour).
  final Color? activeColor;

  /// Draws "I" (on) and "O" (off) in the track (Settings > Accessibility > On/Off Labels).
  final bool showOnOffLabels;

  /// Accessible name when no visible label describes the switch.
  final String? semanticLabel;

  /// No longer used: the pressed knob is a plain white knob (there is no Liquid Glass lens). Kept so existing code
  /// still compiles.
  final Color? surfaceColor;

  @override
  State<IosToggle> createState() => _IosToggleState();
}

class _IosToggleState extends State<IosToggle> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.value ? 1 : 0,
  );
  bool _pressed = false;
  bool _dragging = false;

  bool get _enabled => widget.onChanged != null;

  @override
  void didUpdateWidget(IosToggle old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_dragging) _animateTo(widget.value);
  }

  void _animateTo(bool on) => _t.animateTo(on ? 1 : 0, curve: const Cubic(0.3, 1.25, 0.5, 1));

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _set(bool on) {
    _animateTo(on);
    if (on != widget.value) widget.onChanged?.call(on);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final on = widget.activeColor ?? c.green;
    Widget toggle = AnimatedBuilder(
      animation: _t,
      builder: (context, _) => CustomPaint(
        size: const Size(64, 28),
        painter: _TogglePainter(
          t: _t.value.clamp(0.0, 1.0),
          pressed: _pressed && _enabled,
          onColor: on,
          offColor: c.labelTertiary,
          knobColor: c.white,
          labels: widget.showOnOffLabels,
          labelOffColor: c.toggleAxLabelOff,
        ),
      ),
    );
    if (!_enabled) toggle = Opacity(opacity: 0.5, child: toggle);

    // The 44 pt tap area must be the outermost box: a parent only asks children inside their own size.
    return IosMinTapArea(
      child: Semantics(
        toggled: widget.value,
        enabled: _enabled,
        label: widget.semanticLabel,
        onTap: _enabled ? () => _set(!widget.value) : null,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
            onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
            onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
            onTap: _enabled ? () => _set(!widget.value) : null,
            onHorizontalDragStart: _enabled
                ? (_) => setState(() {
                    _pressed = true;
                    _dragging = true;
                  })
                : null,
            onHorizontalDragUpdate: _enabled
                ? (d) {
                    final dir = Directionality.maybeOf(context) == TextDirection.rtl ? -1 : 1;
                    _t.value = (_t.value + dir * d.delta.dx / 22).clamp(0.0, 1.0);
                  }
                : null,
            onHorizontalDragEnd: _enabled
                ? (_) {
                    setState(() {
                      _pressed = false;
                      _dragging = false;
                    });
                    _set(_t.value >= 0.5);
                  }
                : null,
            onHorizontalDragCancel: _enabled
                ? () => setState(() {
                    _pressed = false;
                    _dragging = false;
                    _animateTo(widget.value);
                  })
                : null,
            child: toggle,
          ),
        ),
      ),
    );
  }
}

class _TogglePainter extends CustomPainter {
  _TogglePainter({
    required this.t,
    required this.pressed,
    required this.onColor,
    required this.offColor,
    required this.knobColor,
    required this.labels,
    required this.labelOffColor,
  });

  final double t;
  final bool pressed;
  final Color onColor;
  final Color offColor;
  final Color knobColor;
  final bool labels;
  final Color labelOffColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Track: 64 × 28 capsule, Labels/Tertiary when off, green when on.
    final track = Color.lerp(offColor, onColor, t)!;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), Paint()..color = track);
    // On/Off labels: 1 × 10 white bar at (12, 9) when on; 10 pt ring centred at (51.5, 14) when off.
    if (labels) {
      if (t >= 0.5) {
        canvas.drawRect(const Rect.fromLTWH(12, 9, 1, 10), Paint()..color = knobColor);
      } else {
        canvas.drawCircle(
          const Offset(51.5, 14),
          4.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = labelOffColor,
        );
      }
    }
    // Knob: 38 × 24 at (2 + 22t, 2). Pressed: 8 wider, stretched towards the middle of the track (its outer end
    // stays put), like the classic iOS switch.
    final stretch = pressed ? 8.0 : 0.0;
    final left = 2 + (22 - stretch) * t;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, 2, 38 + stretch, 24), const Radius.circular(12)),
      Paint()..color = knobColor,
    );
  }

  @override
  bool shouldRepaint(_TogglePainter old) =>
      old.t != t ||
      old.pressed != pressed ||
      old.onColor != onColor ||
      old.offColor != offColor ||
      old.knobColor != knobColor ||
      old.labels != labels ||
      old.labelOffColor != labelOffColor;
}

/// The iOS selection circle (kit page "Lists", "_Edit Buttons" Selected / Unselected): 22 × 22. Unselected = a 1.5 pt
/// Gray 3 ring; selected = accent circle with a white checkmark. For picking several items (edit mode, to-do lists).
/// For on/off settings use [IosToggle].
///
///     IosCheckbox(value: done, onChanged: (v) => setState(() => done = v), semanticLabel: 'Buy milk')
///     IosCheckbox(value: true, onChanged: null)       // disabled (50% opacity)
/// [onChanged] null = disabled.
class IosCheckbox extends StatefulWidget {
  const IosCheckbox({super.key, required this.value, required this.onChanged, this.activeColor, this.semanticLabel});

  /// Selected (true) or not.
  final bool value;

  /// Receives the new value. Null = disabled.
  final ValueChanged<bool>? onChanged;

  /// Fill when selected. Default: the accent colour.
  final Color? activeColor;

  /// Accessible name (the circle has no text), e.g. the item's title.
  final String? semanticLabel;

  @override
  State<IosCheckbox> createState() => _IosCheckboxState();
}

class _IosCheckboxState extends State<IosCheckbox> {
  bool _pressed = false;
  bool get _enabled => widget.onChanged != null;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    Widget circle = TweenAnimationBuilder<double>(
      tween: Tween(end: widget.value ? 1 : 0),
      duration: const Duration(milliseconds: 150),
      builder: (context, t, _) => CustomPaint(
        size: const Size(22, 22),
        painter: _CheckboxPainter(
          t: t,
          fill: widget.activeColor ?? theme.accentColor,
          ring: c.gray3,
          check: const Color(0xFFFFFFFF),
          pressed: _pressed && _enabled,
          dark: theme.isDark,
        ),
      ),
    );
    if (!_enabled) circle = Opacity(opacity: 0.5, child: circle);
    return IosMinTapArea(
      child: Semantics(
        checked: widget.value,
        enabled: _enabled,
        label: widget.semanticLabel,
        onTap: _enabled ? () => widget.onChanged!(!widget.value) : null,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
            onTap: _enabled ? () => widget.onChanged!(!widget.value) : null,
            child: circle,
          ),
        ),
      ),
    );
  }
}

class _CheckboxPainter extends CustomPainter {
  _CheckboxPainter({
    required this.t,
    required this.fill,
    required this.ring,
    required this.check,
    required this.pressed,
    required this.dark,
  });
  final double t;
  final Color fill;
  final Color ring;
  final Color check;
  final bool pressed;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const centre = Offset(11, 11);
    if (t < 1) {
      canvas.drawCircle(
        centre,
        10.25,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = ring.withValues(alpha: ring.a * (1 - t)),
      );
    }
    if (t > 0) {
      var f = fill.withValues(alpha: fill.a * t);
      if (pressed) f = Color.lerp(f, dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000), 0.1)!;
      canvas.drawCircle(centre, 11, Paint()..color = f);
      // Checkmark (SF Symbol "checkmark" 14.5 pt Semibold): the skill's bold checkmark on a 14.4 pt box.
      const s = 14.4 / 14;
      const o = (22 - 14.4) / 2;
      Offset p(double x, double y) => Offset(o + (x - 1) * s, o + (y - 1) * s);
      final scale = 0.6 + 0.4 * t;
      canvas.save();
      canvas.translate(11, 11);
      canvas.scale(scale);
      canvas.translate(-11, -11);
      canvas.drawPath(
        Path()
          ..moveTo(p(3.25, 8.5).dx, p(3.25, 8.5).dy)
          ..lineTo(p(6.5, 11.75).dx, p(6.5, 11.75).dy)
          ..lineTo(p(12.75, 4.5).dx, p(12.75, 4.5).dy),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.75 * s
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = check.withValues(alpha: t),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CheckboxPainter old) =>
      old.t != t ||
      old.fill != fill ||
      old.ring != ring ||
      old.check != check ||
      old.pressed != pressed ||
      old.dark != dark;
}
