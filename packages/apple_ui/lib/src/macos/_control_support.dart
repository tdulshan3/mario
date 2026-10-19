// Shared helpers for the macOS controls (buttons, toggles, sliders, steppers, segmented controls, pop-up buttons,
// colour wells, disclosure controls). Private to the package: files starting with "_" are not exported.
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '../core/typography.dart';

// ---------------------------------------------------------------------------------------------------------------
// Colours (CSS color-mix in srgb, with premultiplied alpha like the browser)
// ---------------------------------------------------------------------------------------------------------------

/// `color-mix(in srgb, a p, b)`: [p] of [a] (0…1), the rest [b].
Color controlMix(Color a, double p, Color b) {
  final q = 1 - p;
  final alpha = a.a * p + b.a * q;
  if (alpha <= 0) return const Color(0x00000000);
  double ch(double ca, double cb) => ((ca * a.a * p + cb * b.a * q) / alpha).clamp(0.0, 1.0);
  return Color.from(alpha: alpha.clamp(0.0, 1.0), red: ch(a.r, b.r), green: ch(a.g, b.g), blue: ch(a.b, b.b));
}

/// `color-mix(in srgb, c p, transparent)`: [c] at [p] of its opacity.
Color controlFade(Color c, double p) => c.withValues(alpha: (c.a * p).clamp(0.0, 1.0));

/// Black or white at an opacity.
Color controlBlack(double a) => Color.fromRGBO(0, 0, 0, a);
Color controlWhite(double a) => Color.fromRGBO(255, 255, 255, a);

const Color controlBlackSolid = Color(0xFF000000);
const Color controlWhiteSolid = Color(0xFFFFFFFF);
const Color controlClear = Color(0x00000000);

/// The vibrant version of the app accent (`--mac-accent-vibrant`): used on blur materials and by toggle buttons.
Color controlVibrantAccent(AppleThemeData theme) {
  final m = theme.mac;
  final accent = theme.accentColor;
  List<Color> plain(MacColors c) => [
        c.accentRed, c.accentOrange, c.accentYellow, c.accentGreen, c.accentMint, c.accentTeal, c.accentCyan,
        c.accentBlue, c.accentIndigo, c.accentPurple, c.accentPink, c.accentBrown, c.gray,
      ];
  List<Color> vibrant(MacColors c) => [
        c.accentVibrantRed, c.accentVibrantOrange, c.accentVibrantYellow, c.accentVibrantGreen, c.accentVibrantMint,
        c.accentVibrantTeal, c.accentVibrantCyan, c.accentVibrantBlue, c.accentVibrantIndigo, c.accentVibrantPurple,
        c.accentVibrantPink, c.accentVibrantBrown, c.gray,
      ];
  for (final palette in [MacColors.light, MacColors.dark]) {
    final i = plain(palette).indexOf(accent);
    if (i >= 0) return vibrant(m)[i];
  }
  return accent;
}

/// Everything a control needs to draw itself: theme, colours, size metrics, window state.
class ControlLook {
  ControlLook._(this.theme, this.c, this.s, this.size, this.inactive, this._context);

  /// [size] overrides the nearest [MacControlSizeScope].
  factory ControlLook.of(BuildContext context, [MacControlSize? size]) {
    final theme = AppleTheme.of(context);
    final resolved = size ?? MacControlSizeScope.of(context);
    return ControlLook._(theme, theme.mac, MacSizes.of(resolved), resolved, MacWindowState.isInactive(context), context);
  }

  final BuildContext _context;

  final AppleThemeData theme;
  final MacColors c;
  final MacSizes s;
  final MacControlSize size;

  /// The window is not focused (`mac-inactive`).
  final bool inactive;

  /// The control sits on a blur material (inside a [MacGlass]). Read it only while building.
  late final bool overGlass = _context.findAncestorWidgetOfExactType<MacGlass>() != null;

  bool get dark => theme.isDark;
  Color get accent => theme.accentColor;
  Color get vibrantAccent => controlVibrantAccent(theme);

  /// `light-dark(light, dark)`.
  Color ld(Color light, Color dark) => theme.isDark ? dark : light;

  /// Keyboard focus ring colour: accent 55 % (base.css `--mac-focus-color`).
  Color get focusColor => controlFade(accent, 0.55);

  /// Kit "_Control BG/Bordered": black 8 % / white 7 %.
  Color get borderedFill => ld(controlBlack(0.08), controlWhite(0.07));
  Color get borderedFillPressed => ld(controlBlack(0.16), controlWhite(0.16));
  Color get borderedFillDisabled => ld(controlBlack(0.04), controlWhite(0.04));

  /// SF Pro (Inter off Apple platforms) at [size], the controls' Medium weight by default.
  TextStyle text(double size, Color color, {FontWeight weight = FontWeight.w500, double? lineHeight}) =>
      appleFont(size: size).copyWith(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: (lineHeight ?? size) / size,
        letterSpacing: 0,
        leadingDistribution: TextLeadingDistribution.even,
        decoration: TextDecoration.none,
      );
}

// ---------------------------------------------------------------------------------------------------------------
// Shapes
// ---------------------------------------------------------------------------------------------------------------

/// A rounded rectangle with continuous corners; a capsule when [radius] reaches half the short side.
Path controlShape(Rect rect, double radius) {
  final half = rect.shortestSide / 2;
  if (radius >= half - 0.001) return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(half)));
  if (radius <= 0) return Path()..addRect(rect);
  return Path()..addRSuperellipse(BorderRadius.circular(radius).toRSuperellipse(rect));
}

/// Like [controlShape] with a radius per corner (continuous corners).
Path controlShapeCorners(Rect rect, {double topLeft = 0, double topRight = 0, double bottomLeft = 0, double bottomRight = 0}) {
  final r = BorderRadius.only(
    topLeft: Radius.circular(topLeft),
    topRight: Radius.circular(topRight),
    bottomLeft: Radius.circular(bottomLeft),
    bottomRight: Radius.circular(bottomRight),
  );
  return Path()..addRSuperellipse(r.toRSuperellipse(rect));
}

/// Fills a [controlShape] behind [child] and, when [focusRing] is set, draws the 3.5 px keyboard focus ring around it.
class ControlBox extends StatelessWidget {
  const ControlBox({super.key, required this.color, required this.radius, this.focusRing, this.child});

  final Color color;
  final double radius;

  /// Colour of the focus ring, or null for none.
  final Color? focusRing;
  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BoxPainter(color, radius, focusRing), child: child);
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.color, this.radius, this.ring);
  final Color color;
  final double radius;
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (color.a > 0) canvas.drawPath(controlShape(rect, radius), Paint()..color = color);
    if (ring != null) paintFocusRing(canvas, rect, radius, ring!);
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.color != color || old.radius != radius || old.ring != ring;
}

/// The keyboard focus ring: a 3.5 px band just outside the shape (CSS `outline: 3.5px; outline-offset: 0`).
void paintFocusRing(Canvas canvas, Rect rect, double radius, Color color, {double offset = 0}) {
  final inner = rect.inflate(offset);
  final outer = inner.inflate(3.5);
  final half = inner.shortestSide / 2;
  final r = radius >= half - 0.001 ? outer.shortestSide / 2 : radius + offset + 3.5;
  final ring = Path.combine(PathOperation.difference, controlShape(outer, r), controlShape(inner, radius >= half - 0.001 ? half : radius + offset));
  canvas.drawPath(ring, Paint()..color = color);
}

/// Paints the focus ring around [child]'s box (for controls that draw their own shape).
class ControlFocusRing extends StatelessWidget {
  const ControlFocusRing({super.key, required this.visible, required this.color, required this.radius, this.offset = 0, required this.child});
  final bool visible;
  final Color color;
  final double radius;
  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(foregroundPainter: visible ? _RingPainter(color, radius, offset) : null, child: child);
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.radius, this.offset);
  final Color color;
  final double radius;
  final double offset;
  @override
  void paint(Canvas canvas, Size size) => paintFocusRing(canvas, Offset.zero & size, radius, color, offset: offset);
  @override
  bool shouldRepaint(_RingPainter old) => old.color != color || old.radius != radius || old.offset != offset;
}

// ---------------------------------------------------------------------------------------------------------------
// Glyphs: the skill's original stroked symbols (same paths as the SVG masks in the CSS)
// ---------------------------------------------------------------------------------------------------------------

/// A stroked glyph: polylines in a [viewBox], drawn into the widget's size (stretched like `mask-size: 100% 100%`).
class ControlGlyph extends StatelessWidget {
  const ControlGlyph({
    super.key,
    required this.lines,
    required this.viewBox,
    required this.strokeWidth,
    required this.color,
    required this.width,
    required this.height,
    this.turns = 0,
  });

  /// Chevron right (icons.css `chevron-right`, 16 × 16, stroke 1.35).
  static const chevronRight = [[Offset(6.25, 4), Offset(10, 8), Offset(6.25, 12)]];

  /// ⌃⌄ (icons.css `chevron-up-down`, stroke 1.35).
  static const chevronUpDown = [
    [Offset(5, 6), Offset(8, 3), Offset(11, 6)],
    [Offset(5, 10), Offset(8, 13), Offset(11, 10)],
  ];

  /// ⌃⌄ of the pop-up button (pop-up-buttons.css, stroke 1.75).
  static const popupIndicator = [
    [Offset(4.9, 6.1), Offset(8, 3), Offset(11.1, 6.1)],
    [Offset(4.9, 9.9), Offset(8, 13), Offset(11.1, 9.9)],
  ];

  /// Bold ⌄ (icons.css `chevron-down-bold`, stroke 2).
  static const chevronDownBold = [[Offset(3, 5.75), Offset(8, 10.25), Offset(13, 5.75)]];

  /// Stepper chevrons (steppers.css, 10.5 × 6, stroke 1.5).
  static const stepperUp = [[Offset(0.75, 5.25), Offset(5.25, 0.75), Offset(9.75, 5.25)]];
  static const stepperDown = [[Offset(0.75, 0.75), Offset(5.25, 5.25), Offset(9.75, 0.75)]];

  /// Checkbox checkmark (toggles.css, 9.31 × 8.93, stroke 1.75).
  static const checkmark = [[Offset(0.9, 4.75), Offset(3.65, 8.05), Offset(8.4, 0.9)]];

  final List<List<Offset>> lines;
  final Size viewBox;
  final double strokeWidth;
  final Color color;
  final double width;
  final double height;

  /// Rotation in turns (0.25 = 90° clockwise), around the centre.
  final double turns;

  @override
  Widget build(BuildContext context) {
    Widget glyph = CustomPaint(
      size: Size(width, height),
      painter: _GlyphPainter(lines, viewBox, strokeWidth, color),
    );
    if (turns != 0) glyph = Transform.rotate(angle: turns * 2 * math.pi, child: glyph);
    return glyph;
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.lines, this.viewBox, this.strokeWidth, this.color);
  final List<List<Offset>> lines;
  final Size viewBox;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / viewBox.width;
    final sy = size.height / viewBox.height;
    canvas.save();
    canvas.scale(sx, sy);
    final path = Path();
    for (final line in lines) {
      path.moveTo(line.first.dx, line.first.dy);
      for (final p in line.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.viewBox != viewBox || !identical(old.lines, lines);
}

// ---------------------------------------------------------------------------------------------------------------
// Interaction: pressed state, keyboard focus and activation (no hover: macOS controls have none)
// ---------------------------------------------------------------------------------------------------------------

/// The interaction state of a control while it builds.
@immutable
class ControlState {
  const ControlState({required this.pressed, required this.focused, required this.hovered});

  /// The mouse button is down on it.
  final bool pressed;

  /// It has keyboard focus and the focus ring should show (keyboard navigation).
  final bool focused;

  /// The pointer is over it (only toolbar items use this).
  final bool hovered;
}

/// Pressed state, Tab focus, Space/Return activation and the arrow pointer for a control.
/// [onPressed] null = disabled.
class ControlPressable extends StatefulWidget {
  const ControlPressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.onPressDown,
    this.focusable = true,
    this.focusNode,
    this.autofocus = false,
    this.onKeyEvent,
    this.trackHover = false,
  });

  final VoidCallback? onPressed;

  /// Called when the mouse button goes down (pop-up menus open on mouse down on macOS).
  final VoidCallback? onPressDown;
  final Widget Function(BuildContext context, ControlState state) builder;
  final bool focusable;
  final FocusNode? focusNode;
  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;
  final bool trackHover;

  @override
  State<ControlPressable> createState() => _ControlPressableState();
}

class _ControlPressableState extends State<ControlPressable> {
  bool _pressed = false;
  bool _focused = false;
  bool _hovered = false;

  bool get _enabled => widget.onPressed != null || widget.onPressDown != null;

  @override
  void didUpdateWidget(ControlPressable old) {
    super.didUpdateWidget(old);
    if (!_enabled) _pressed = false;
  }

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _enabled
          ? (_) {
              _set(true);
              widget.onPressDown?.call();
            }
          : null,
      onTapUp: _enabled ? (_) => _set(false) : null,
      onTapCancel: _enabled ? () => _set(false) : null,
      onTap: widget.onPressed,
      child: widget.builder(context, ControlState(pressed: _pressed && _enabled, focused: _focused && _enabled, hovered: _hovered && _enabled)),
    );
    child = FocusableActionDetector(
      enabled: _enabled && widget.focusable,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.basic,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: widget.trackHover ? (v) => setState(() => _hovered = v) : null,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          (widget.onPressed ?? widget.onPressDown)?.call();
          return null;
        }),
      },
      child: child,
    );
    if (widget.onKeyEvent != null) child = Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: widget.onKeyEvent, child: child);
    return child;
  }
}

/// True for a key-down or key-repeat of [key].
bool controlKey(KeyEvent e, LogicalKeyboardKey key) => (e is KeyDownEvent || e is KeyRepeatEvent) && e.logicalKey == key;

// ---------------------------------------------------------------------------------------------------------------
// CSS box-shadows on capsules (used by the knobs of switches and sliders)
// ---------------------------------------------------------------------------------------------------------------

/// One CSS box-shadow: x, y, blur, spread, colour; [inset] = drawn inside the shape.
@immutable
class ControlShadow {
  const ControlShadow(this.dx, this.dy, this.blur, this.spread, this.color, {this.inset = false});
  final double dx;
  final double dy;
  final double blur;
  final double spread;
  final Color color;
  final bool inset;
}

Path _capsule(Rect r) => Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(math.max(0, r.shortestSide / 2))));

/// Paints CSS box-shadows for a capsule of [rect]: outer ones only outside it, inset ones only inside it.
void paintCapsuleShadows(Canvas canvas, Rect rect, List<ControlShadow> shadows) {
  final shape = _capsule(rect);
  final big = Path()..addRect(rect.inflate(200));
  for (final s in shadows.reversed) {
    final paint = Paint()..color = s.color;
    if (s.blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.blur / 2);
    canvas.save();
    if (s.inset) {
      canvas.clipPath(shape);
      final hole = rect.inflate(-s.spread).shift(Offset(s.dx, s.dy));
      final band = hole.width > 0 && hole.height > 0 ? Path.combine(PathOperation.difference, big, _capsule(hole)) : big;
      canvas.drawPath(band, paint);
    } else {
      canvas.clipPath(Path.combine(PathOperation.difference, big, shape));
      final grown = rect.inflate(s.spread).shift(Offset(s.dx, s.dy));
      if (grown.width > 0 && grown.height > 0) canvas.drawPath(_capsule(grown), paint);
    }
    canvas.restore();
  }
}

/// A white capsule knob with a CSS shadow (switch: 0 3 36 black 5 %; slider: 0 0.5 6 black 12 %). While pressed the
/// switch and slider pass [controlKnobPressed] as [color] (the classic macOS knob turns light grey; no Liquid Glass).
const Color controlKnobPressed = Color(0xFFF0F0F0);

class ControlKnob extends StatelessWidget {
  const ControlKnob({super.key, required this.width, required this.height, required this.shadow, this.color = controlWhiteSolid, this.focusRing});
  final double width;
  final double height;
  final ControlShadow shadow;
  final Color color;
  final Color? focusRing;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _KnobPainter(shadow, color, focusRing)),
      );
}

class _KnobPainter extends CustomPainter {
  _KnobPainter(this.shadow, this.color, this.ring);
  final ControlShadow shadow;
  final Color color;
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shadows = [if (ring != null) ControlShadow(0, 0, 0, 3.5, ring!), shadow];
    paintCapsuleShadows(canvas, rect, shadows);
    canvas.drawPath(_capsule(rect), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.color != color || old.ring != ring || old.shadow != shadow;
}

// ---------------------------------------------------------------------------------------------------------------
// Toolbar capsule (segmented control, pop-up and pull-down buttons in a toolbar)
// ---------------------------------------------------------------------------------------------------------------

/// The capsule of a toolbar control (kit "Toolbars"): [MacGlass], the classic Thin blur material with a 0.5 px
/// hairline (no side edges); [overlay] tints it (hover 5 %, pressed 16 %). In an inactive window: no material, a faint
/// fill and a 0.5 px outline.
class ControlToolbarCapsule extends StatelessWidget {
  const ControlToolbarCapsule({super.key, required this.child, this.overlay});
  final Widget child;
  final Color? overlay;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final dark = theme.isDark;
    if (MacWindowState.isInactive(context)) {
      return CustomPaint(painter: _ToolbarInactivePainter(dark: dark), child: child);
    }
    return MacGlass(child: overlay == null ? child : ColoredBox(color: overlay!, child: child));
  }
}

class _ToolbarInactivePainter extends CustomPainter {
  _ToolbarInactivePainter({required this.dark});
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    paintCapsuleShadows(canvas, rect, [
      ControlShadow(0, 0, 0, 0.5, dark ? const Color(0xFFE6E6E6) : const Color(0xFFEBEBEB)),
    ]);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)),
      Paint()..color = dark ? controlWhite(0.05) : controlBlack(0.02),
    );
  }

  @override
  bool shouldRepaint(_ToolbarInactivePainter old) => old.dark != dark;
}
