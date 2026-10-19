// Shared painting helpers for the macOS panels of batch M4 (menus, popovers, alerts, sheets, notifications,
// tooltips, Dock). Not exported: the names are public only so the M4 files can share them.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/glass.dart' show GlassShadow;
import '../core/mac_support.dart';

/// One CSS `box-shadow` of a panel: x/y offset, blur radius, spread, colour; [inset] = drawn inside the shape.
@immutable
class PanelShadow {
  const PanelShadow(this.dx, this.dy, this.blur, this.spread, this.color, {this.inset = false});
  final double dx;
  final double dy;
  final double blur;
  final double spread;
  final Color color;
  final bool inset;

  @override
  bool operator ==(Object other) =>
      other is PanelShadow &&
      other.dx == dx &&
      other.dy == dy &&
      other.blur == blur &&
      other.spread == spread &&
      other.color == color &&
      other.inset == inset;

  @override
  int get hashCode => Object.hash(dx, dy, blur, spread, color, inset);
}

/// The outline of a panel for [rect], grown by [spread] (negative = shrunk), like a CSS box-shadow spread.
typedef PanelShapeBuilder = Path Function(Rect rect, double spread);

/// Continuous-corner rounded rectangle (CSS `border-radius` + the kit's corner smoothing).
PanelShapeBuilder roundedPanelShape(double radius) => (Rect rect, double spread) {
      final r = rect.inflate(spread);
      if (r.width <= 0 || r.height <= 0) return Path();
      final rr = (radius + spread).clamp(0.0, r.shortestSide / 2);
      if (rr <= 0) return Path()..addRect(r);
      return RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(rr)).getOuterPath(r);
    };

/// Paints CSS box-shadows for a shape: outer shadows only outside the shape (like the browser), inset shadows
/// only inside it. The first shadow in the list paints on top, as in CSS.
class PanelShadowPainter extends CustomPainter {
  PanelShadowPainter(this.shape, this.shadows, {required this.inset, super.repaint});
  final PanelShapeBuilder shape;
  final List<PanelShadow> shadows;
  final bool inset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = shape(rect, 0);
    final list = shadows.where((s) => s.inset == inset).toList().reversed;
    if (list.isEmpty) return;
    canvas.save();
    if (inset) {
      canvas.clipPath(base);
    } else {
      canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(rect.inflate(400)), base));
    }
    for (final s in list) {
      final paint = Paint()..color = s.color;
      if (s.blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.blur / 2);
      if (inset) {
        final hole = shape(rect, -s.spread).shift(Offset(s.dx, s.dy));
        final outside = Path()..addRect(rect.inflate(s.blur * 2 + s.spread.abs() + s.dx.abs() + s.dy.abs() + 20));
        canvas.drawPath(Path.combine(PathOperation.difference, outside, hole), paint);
      } else {
        canvas.drawPath(shape(rect, s.spread).shift(Offset(s.dx, s.dy)), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PanelShadowPainter old) => old.shape != shape || !_sameList(old.shadows, shadows) || old.inset != inset;
}

bool _sameList(List<PanelShadow> a, List<PanelShadow> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _ShapeClipper extends CustomClipper<Path> {
  _ShapeClipper(this.shape, {super.reclip});
  final PanelShapeBuilder shape;
  @override
  Path getClip(Size size) => shape(Offset.zero & size, 0);
  @override
  bool shouldReclip(_ShapeClipper old) => old.shape != shape;
}

/// A panel surface: outer shadows, backdrop filter (blur + colour matrix), fill, inset shadows, then [child],
/// all clipped to [shape]. This is the CSS recipe of each M4 panel (menus.css, popovers.css, alerts.css …).
class PanelSurface extends StatelessWidget {
  const PanelSurface({
    super.key,
    required this.shape,
    required this.fill,
    this.backdrop,
    this.shadows = const [],
    this.child,
    this.repaint,
  });

  final PanelShapeBuilder shape;
  final Color fill;
  final ui.ImageFilter? backdrop;
  final List<PanelShadow> shadows;
  final Widget? child;

  /// Repaints and re-clips when this changes (popover arrow geometry).
  final Listenable? repaint;

  @override
  Widget build(BuildContext context) {
    Widget body = CustomPaint(
      painter: PanelShadowPainter(shape, shadows, inset: true, repaint: repaint),
      child: child ?? const SizedBox.expand(),
    );
    body = ColoredBox(color: fill, child: body);
    if (backdrop != null) body = BackdropFilter(filter: backdrop!, child: body);
    body = ClipPath(clipper: _ShapeClipper(shape, reclip: repaint), child: body);
    return CustomPaint(painter: PanelShadowPainter(shape, shadows, inset: false, repaint: repaint), child: body);
  }
}

// --- The classic macOS blur material of a panel ----------------------------------------------------------

/// The fill, backdrop and shadows of a panel in the classic macOS blur material ([macGlassRecipe]; macos.css
/// `--mac-glass-*`): [MacGlassStyle.panel] = Ultra Thick (menus, popovers, alerts, notifications),
/// [MacGlassStyle.control] = Thin (the Dock). The content behind is blurred (sigma 30) and saturated (1.8) under a
/// translucent fill, with the 0.5 px hairline of classic macOS menus and popovers. No rims, no side edges, no inner
/// highlights. [drop] = the panel's own drop shadow(s) under the hairline; null = the recipe's.
({Color fill, ui.ImageFilter backdrop, List<PanelShadow> shadows}) panelMaterial(
  bool dark, {
  MacGlassStyle style = MacGlassStyle.panel,
  List<PanelShadow>? drop,
}) {
  final recipe = macGlassRecipe(style, dark: dark);
  bool isHairline(GlassShadow s) => s.dx == 0 && s.dy == 0 && s.blur == 0;
  PanelShadow panel(GlassShadow s) => PanelShadow(s.dx, s.dy, s.blur, s.spread, s.color);
  return (
    fill: recipe.fill,
    backdrop: cssBackdrop(blur: recipe.blur, saturate: recipe.saturation),
    shadows: [
      for (final s in recipe.shadows.where(isHairline)) panel(s),
      ...?drop,
      if (drop == null)
        for (final s in recipe.shadows.where((s) => !isHairline(s))) panel(s),
    ],
  );
}

/// The kit's drop shadow of menus, popovers and notifications: 0 8 48, black 25 % (Light) · 45 % (Dark).
PanelShadow panelDropShadow(bool dark) => PanelShadow(0, 8, 48, 0, dark ? const Color(0x73000000) : const Color(0x40000000));

// --- CSS filter functions as one colour matrix (sRGB, like the browser) ---------------------------------

List<double> _mul(List<double> a, List<double> b) {
  // 4x5 affine matrices (row major, offsets in 0..1); returns a·b (b applied first).
  final r = List<double>.filled(20, 0);
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 5; j++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += a[i * 5 + k] * b[k * 5 + j];
      }
      if (j == 4) v += a[i * 5 + 4];
      r[i * 5 + j] = v;
    }
  }
  return r;
}

List<double> _contrast(double c) {
  final o = 0.5 * (1 - c);
  return [c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0];
}

List<double> _brightness(double b) => [b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];

List<double> _saturate(double s) => [
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
      0, 0, 0, 1, 0,
    ];

/// CSS `blur(sigma) contrast(c) brightness(b) saturate(s)` as one backdrop image filter (CSS blur = sigma).
ui.ImageFilter cssBackdrop({required double blur, double contrast = 1, double brightness = 1, double saturate = 1}) {
  var m = _contrast(contrast);
  m = _mul(_brightness(brightness), m);
  m = _mul(_saturate(saturate), m);
  final flutter = [for (var i = 0; i < 20; i++) i % 5 == 4 ? m[i] * 255 : m[i]];
  return ui.ImageFilter.compose(
    outer: ui.ColorFilter.matrix(flutter),
    inner: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.clamp),
  );
}

// --- Colour helpers --------------------------------------------------------------------------------------

/// CSS `color-mix(in srgb, a p%, b)`.
Color mixColor(Color a, Color b, double p) => Color.lerp(b, a, p)!;

/// The menu highlight: the accent 0.07 darker and 14 % more chromatic in OKLCH (menus.css; kit #0069F9 for blue).
Color menuHighlightColor(Color accent) {
  double toLinear(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double toSrgb(double c) => c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
  final r = toLinear(accent.r), g = toLinear(accent.g), b = toLinear(accent.b);
  final l = math.pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1 / 3).toDouble();
  final m = math.pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1 / 3).toDouble();
  final s = math.pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1 / 3).toDouble();
  var lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  final aa = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  final bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  final chroma = math.sqrt(aa * aa + bb * bb) * 1.14;
  final hue = math.atan2(bb, aa);
  lightness -= 0.07;
  final a2 = chroma * math.cos(hue), b2 = chroma * math.sin(hue);
  final l_ = math.pow(lightness + 0.3963377774 * a2 + 0.2158037573 * b2, 3).toDouble();
  final m_ = math.pow(lightness - 0.1055613458 * a2 - 0.0638541728 * b2, 3).toDouble();
  final s_ = math.pow(lightness - 0.0894841775 * a2 - 1.2914855480 * b2, 3).toDouble();
  double out(double v) => toSrgb(v.clamp(0.0, 1.0)).clamp(0.0, 1.0);
  return Color.from(
    alpha: accent.a,
    red: out(4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_),
    green: out(-1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_),
    blue: out(-0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_),
  );
}

/// Text style with the CSS metrics: size, line height, weight, colour (even leading like CSS line-height).
TextStyle panelText(TextStyle base, {required double size, required double lineHeight, FontWeight weight = FontWeight.w400, required Color color}) =>
    base.copyWith(
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      color: color,
      letterSpacing: 0,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: TextDecoration.none,
    );

/// Keyboard focus ring (base.css: 3.5 px, accent at 55 %) drawn around [shape], outside it.
class FocusRingPainter extends CustomPainter {
  FocusRingPainter(this.shape, this.color);
  final PanelShapeBuilder shape;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawPath(
      Path.combine(PathOperation.difference, shape(rect, 3.5), shape(rect, 0)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(FocusRingPainter old) => old.color != color || old.shape != shape;
}
