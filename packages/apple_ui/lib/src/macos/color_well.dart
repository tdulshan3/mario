import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '_control_support.dart';
import 'popovers.dart';

/// Colour well styles (kit page "Color Wells").
enum MacColorWellStyle {
  /// A capsule swatch in a 3 px bezel (kit "Color Picker"). The usual case, in forms and inspectors.
  standard,

  /// A compact 28 px round button: a rainbow ring around the current colour (kit "Color Picker - Wheel").
  /// For toolbars and tight inspector rows. With no single colour ([MacColorWell.color] null) it shows the whole wheel.
  wheel,
}

/// A colour well (kit page "Color Wells"): shows a colour; clicking it lets people pick another.
///
///     MacColorWell(color: highlight, onChanged: (c) => setState(() => highlight = c), semanticLabel: 'Highlight Color')
///     MacColorWell(color: text, style: MacColorWellStyle.wheel, onChanged: …, semanticLabel: 'Text Color')
///     MacColorWell(color: tag, active: pickerOpen, onPressed: openMyPicker, semanticLabel: 'Tag Color')  // your own picker
///
/// With [onChanged] a click opens a popover of colour swatches (the system accent colours, grey, black and white);
/// the well is active (accent bezel) while it is open, and a pick applies at once. With [onPressed] your code opens its
/// own picker instead: set [active] while it is open. Both null = disabled (swatch at 50 %).
/// Sizes: mini 32 × 16 · small 40 × 20 · medium 48 × 24 · large 56 × 28 · XL 72 × 36 (the wheel is always 28).
/// Inactive window: an active bezel turns grey. No hover effect. Space or Return opens it from the keyboard.
class MacColorWell extends StatefulWidget {
  const MacColorWell({
    super.key,
    required this.color,
    this.onChanged,
    this.onPressed,
    this.active = false,
    this.style = MacColorWellStyle.standard,
    this.palette,
    this.semanticLabel,
    this.size,
    this.focusNode,
  });

  /// The current colour. Null = no single colour (nothing set, or a selection with different colours).
  final Color? color;

  /// Called with the colour picked in the built-in swatch popover.
  final ValueChanged<Color>? onChanged;

  /// Opens your own colour picker instead of the built-in popover.
  final VoidCallback? onPressed;

  /// Draw the active (accent) bezel: your own picker for this well is open.
  final bool active;
  final MacColorWellStyle style;

  /// Swatches of the built-in popover. Null = the 12 system accent colours, grey, black and white.
  final List<Color>? palette;

  /// Accessible name with the purpose ("Highlight Color").
  final String? semanticLabel;
  final MacControlSize? size;
  final FocusNode? focusNode;

  @override
  State<MacColorWell> createState() => _MacColorWellState();
}

class _MacColorWellState extends State<MacColorWell> {
  bool _open = false;

  bool get _enabled => widget.onChanged != null || widget.onPressed != null;

  void _press() {
    if (widget.onPressed != null) {
      widget.onPressed!();
    } else {
      setState(() => _open = !_open);
    }
  }

  List<Color> _palette(MacColors c) =>
      widget.palette ??
      [
        c.accentRed, c.accentOrange, c.accentYellow, c.accentGreen, c.accentMint, c.accentTeal, c.accentCyan,
        c.accentBlue, c.accentIndigo, c.accentPurple, c.accentPink, c.accentBrown, c.gray, c.black, c.white,
      ];

  @override
  Widget build(BuildContext context) {
    final look = ControlLook.of(context, widget.size);
    final active = widget.active || _open;
    Widget well = Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: ControlPressable(
        onPressed: _enabled ? _press : null,
        focusNode: widget.focusNode,
        builder: (context, state) => widget.style == MacColorWellStyle.wheel
            ? _Wheel(color: widget.color, enabled: _enabled, focus: state.focused ? look.focusColor : null)
            : _Standard(look: look, color: widget.color, enabled: _enabled, active: active, focus: state.focused ? look.focusColor : null),
      ),
    );
    if (widget.onChanged == null || widget.onPressed != null) return well;
    return MacPopover(
      isOpen: _open,
      onDismiss: () => setState(() => _open = false),
      semanticLabel: widget.semanticLabel,
      content: _Swatches(
        colors: _palette(look.c),
        // The current colour, also when it is the other appearance's version of a system colour.
        selectedIndex: [
          _palette(look.c).indexOf(widget.color ?? controlClear),
          _palette(MacColors.light).indexOf(widget.color ?? controlClear),
          _palette(MacColors.dark).indexOf(widget.color ?? controlClear),
        ].firstWhere((i) => i >= 0, orElse: () => -1),
        onPick: (c) {
          setState(() => _open = false);
          widget.onChanged!(c);
        },
      ),
      child: well,
    );
  }
}

/// The standard well: bezel (3 px) + capsule swatch with a 1 px black 10 % edge inside.
class _Standard extends StatelessWidget {
  const _Standard({required this.look, required this.color, required this.enabled, required this.active, required this.focus});
  final ControlLook look;
  final Color? color;
  final bool enabled;
  final bool active;
  final Color? focus;

  @override
  Widget build(BuildContext context) {
    final s = look.s;
    final bezel = active ? (look.inactive ? look.c.labelTertiary : look.accent) : look.borderedFill;
    return SizedBox(
      width: s.colorWellWidth,
      height: s.colorWellHeight,
      child: CustomPaint(
        painter: _StandardPainter(bezel: bezel, color: color, faded: !enabled, focus: focus),
      ),
    );
  }
}

class _StandardPainter extends CustomPainter {
  _StandardPainter({required this.bezel, required this.color, required this.faded, required this.focus});
  final Color bezel;
  final Color? color;
  final bool faded;
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)), Paint()..color = bezel);
    final inner = rect.deflate(3);
    final swatch = RRect.fromRectAndRadius(inner, Radius.circular(inner.height / 2));
    final alpha = faded ? 0.5 : 1.0;
    if (color != null) canvas.drawRRect(swatch, Paint()..color = controlFade(color!, alpha));
    final edge = Path.combine(
      PathOperation.difference,
      Path()..addRRect(swatch),
      Path()..addRRect(RRect.fromRectAndRadius(inner.deflate(1), Radius.circular(inner.height / 2 - 1))),
    );
    canvas.drawPath(edge, Paint()..color = controlBlack(0.1 * alpha));
    if (focus != null) paintFocusRing(canvas, rect, size.height / 2, focus!);
  }

  @override
  bool shouldRepaint(_StandardPainter old) => old.bezel != bezel || old.color != color || old.faded != faded || old.focus != focus;
}

/// The wheel well: a 3 px rainbow ring, a 2 px gap and an 18 px dot; with no colour the whole wheel with a white centre.
class _Wheel extends StatelessWidget {
  const _Wheel({required this.color, required this.enabled, required this.focus});
  final Color? color;
  final bool enabled;
  final Color? focus;

  @override
  Widget build(BuildContext context) {
    Widget w = SizedBox(width: 28, height: 28, child: CustomPaint(painter: _WheelPainter(color: color, focus: focus)));
    if (!enabled) w = Opacity(opacity: 0.5, child: w);
    return w;
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.color, required this.focus});
  final Color? color;
  final Color? focus;

  // conic-gradient(from 180deg, #FF0000, #FB00FF 20%, #00A1FF 40%, #44FF00 60%, #FFF700 80%, #FF0000): starts at the
  // bottom and runs clockwise.
  static const _rainbow = [Color(0xFFFF0000), Color(0xFFFB00FF), Color(0xFF00A1FF), Color(0xFF44FF00), Color(0xFFFFF700), Color(0xFFFF0000)];
  static const _stops = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = rect.center;
    final r = size.width / 2;
    final sweep = Paint()
      ..shader = const SweepGradient(colors: _rainbow, stops: _stops, transform: GradientRotation(math.pi / 2)).createShader(rect);
    if (color == null) {
      canvas.drawCircle(c, r, sweep);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFFFFFFFF), Color(0xA8FFFFFF), Color(0x54FFFFFF), Color(0x00FFFFFF)],
            stops: [0.04, 0.41, 0.74, 0.96],
          ).createShader(rect),
      );
    } else {
      // Ring: opaque from r − 2.75, fading in from r − 3.25 (the CSS radial mask).
      final ring = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: c, radius: r)),
        Path()..addOval(Rect.fromCircle(center: c, radius: r - 3)),
      );
      canvas.drawPath(ring, sweep);
      canvas.drawCircle(c, 9, Paint()..color = color!);
    }
    if (focus != null) paintFocusRing(canvas, rect, r, focus!);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.color != color || old.focus != focus;
}

/// The built-in popover content: a grid of round swatches, 5 per row; the current colour has a ring.
class _Swatches extends StatelessWidget {
  const _Swatches({required this.colors, required this.selectedIndex, required this.onPick});
  final List<Color> colors;
  final int selectedIndex;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final ringColor = theme.mac.labelPrimary;
    final focusColor = controlFade(theme.accentColor, 0.55);
    return SizedBox(
      width: 5 * 24 + 4 * 8,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (i, c) in colors.indexed)
            Semantics(
              button: true,
              selected: i == selectedIndex,
              label: '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
              excludeSemantics: true,
              child: ControlPressable(
                onPressed: () => onPick(c),
                builder: (context, state) => SizedBox(
                  width: 24,
                  height: 24,
                  child: CustomPaint(painter: _SwatchPainter(c, i == selectedIndex ? ringColor : null, state.focused ? focusColor : null)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.color, this.ring, this.focus);
  final Color color;
  final Color? ring;
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    if (ring != null) {
      canvas.drawCircle(c, r - 1, Paint()
        ..color = ring!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    final inner = ring != null ? r - 4 : r - 1;
    canvas.drawCircle(c, inner, Paint()..color = color);
    canvas.drawCircle(c, inner - 0.5, Paint()
      ..color = controlBlack(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    if (focus != null) paintFocusRing(canvas, Offset.zero & size, r, focus!);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color || old.ring != ring || old.focus != focus;
}
