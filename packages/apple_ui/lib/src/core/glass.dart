import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Which classic blur material (kit "Materials" page; the names stay "glass" for compatibility, there is no Liquid Glass).
enum AppleGlassStyle {
  /// Regular material for controls: bar buttons, tab bars, toolbars, floating buttons.
  regular,

  /// A solid accent fill for the primary action of a bar (no blur). Content is white.
  prominent,

  /// A control that is not active (kit "Active = False"): flat quaternary fill and a hairline.
  inactive,

  /// Thick material for panels: menus, popovers, sheets, alerts, notifications.
  panel,

  /// Thin material over photos, video and maps.
  clear,
}

/// One kit shadow: x/y offset, blur radius, spread, colour. Drawn only OUTSIDE the glass shape, like CSS box-shadow.
@immutable
class GlassShadow {
  const GlassShadow(this.dx, this.dy, this.blur, this.spread, this.color);
  final double dx;
  final double dy;
  final double blur;
  final double spread;
  final Color color;
}

/// Resolved recipe for one style and appearance. The kit's blended fills (plus-lighter, luminosity, lighten,
/// darken) reduce to one normal fill over the blurred backdrop: backdrop x -> a·x + b (see base.css in the skill).
@immutable
class GlassRecipe {
  const GlassRecipe({
    required this.fill,
    required this.blur,
    required this.saturation,
    required this.shadows,
  });
  final Color fill;
  final double blur;
  final double saturation;
  final List<GlassShadow> shadows;


  /// The classic blur materials (iOS 13–18 style; no Liquid Glass): Apple's iOS 27 kit "Materials" page
  /// (Regular / Thick / Thin; background blur 100 in Figma = sigma 50), Light as white fills, Dark as the kit's
  /// classic dark platters. Same values as base.css (`--ios-material-*`).
  static GlassRecipe of(AppleGlassStyle style, {required bool dark, required Color accent, required Color quaternaryFill}) {
    switch (style) {
      case AppleGlassStyle.regular: // controls: bar buttons, tab bars, toolbar groups — Regular material
        return dark
            ? const GlassRecipe(fill: Color(0xD1252525), blur: 50, saturation: 1.8, shadows: [GlassShadow(0, 8, 15, 0, Color(0x1F000000))])
            : const GlassRecipe(fill: Color(0xB8FFFFFF), blur: 50, saturation: 1.8, shadows: [GlassShadow(0, 8, 15, 0, Color(0x0A000000))]);
      case AppleGlassStyle.prominent: // the primary action: a solid accent fill, no blur
        return GlassRecipe(fill: accent, blur: 0, saturation: 1, shadows: const [GlassShadow(0, 8, 15, 0, Color(0x0A000000))]);
      case AppleGlassStyle.inactive:
        return GlassRecipe(fill: quaternaryFill, blur: 0, saturation: 1, shadows: [
          GlassShadow(0, 0, 0, 0.5, dark ? const Color(0x1FFFFFFF) : const Color(0xFFEBEBEB)),
        ]);
      case AppleGlassStyle.panel: // menus, popovers, medium sheets, alerts — Thick material
        return dark
            ? const GlassRecipe(fill: Color(0xF01D1D1D), blur: 50, saturation: 1.8, shadows: [GlassShadow(0, 8, 48, 0, Color(0x73000000))])
            : const GlassRecipe(fill: Color(0xE0FFFFFF), blur: 50, saturation: 1.8, shadows: [GlassShadow(0, 8, 48, 0, Color(0x40000000))]);
      case AppleGlassStyle.clear: // over photos, video, maps — Thin material
        return dark
            ? const GlassRecipe(fill: Color(0x8C252525), blur: 50, saturation: 1.8, shadows: [GlassShadow(0, 8, 15, 0, Color(0x1F000000))])
            : const GlassRecipe(fill: Color(0x6EFFFFFF), blur: 50, saturation: 1.8, shadows: [GlassShadow(0, 8, 15, 0, Color(0x0A000000))]);
    }
  }
}

/// The classic frosted blur material behind [child] (the name says glass for compatibility; there is no Liquid
/// Glass). It is ONLY for controls and panels that float above content
/// (bar buttons, tab bars, toolbars, menus, popovers, sheets, alerts). Never for content, never glass on glass.
///
///     AppleGlass(child: Padding(padding: EdgeInsets.all(12), child: Icon(AppleIcons.plus)))      // capsule
///     AppleGlass(style: AppleGlassStyle.panel, radius: 34, child: ...)                            // panel
class AppleGlass extends StatelessWidget {
  const AppleGlass({
    super.key,
    required this.child,
    this.style = AppleGlassStyle.regular,
    this.radius,
    this.padding = EdgeInsets.zero,
    this.tint,
  });

  final Widget child;
  final AppleGlassStyle style;

  /// Corner radius (continuous corners). Null = capsule for regular/prominent/inactive/clear, 34 for panel.
  final double? radius;
  final EdgeInsetsGeometry padding;

  /// Colour of [AppleGlassStyle.prominent] glass. Null = the accent colour (red for a destructive action).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final recipe = GlassRecipe.of(style,
        dark: theme.isDark, accent: tint ?? theme.accentColor, quaternaryFill: theme.ios.fillQuaternary);
    final r = radius ?? (style == AppleGlassStyle.panel ? 34.0 : null);
    Widget body = ColoredBox(color: recipe.fill, child: Padding(padding: padding, child: child));
    if (recipe.blur > 0) {
      body = BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ui.ColorFilter.matrix(appleSaturationMatrix(recipe.saturation)),
          inner: ui.ImageFilter.blur(sigmaX: recipe.blur, sigmaY: recipe.blur, tileMode: TileMode.clamp),
        ),
        child: body,
      );
    }
    return CustomPaint(
      painter: _GlassShadowPainter(recipe.shadows, r),
      child: ClipPath(clipper: _ShapeClipper(r), child: body),
    );
  }
}

/// The glass shape: continuous-corner rounded rectangle, or a capsule when [radius] is null.
Path glassShapePath(Rect rect, double? radius) {
  final r = radius ?? rect.shortestSide / 2;
  final rr = r.clamp(0.0, rect.shortestSide / 2);
  return RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(rr)).getOuterPath(rect);
}

class _ShapeClipper extends CustomClipper<Path> {
  _ShapeClipper(this.radius);
  final double? radius;
  @override
  Path getClip(Size size) => glassShapePath(Offset.zero & size, radius);
  @override
  bool shouldReclip(_ShapeClipper old) => old.radius != radius;
}

class _GlassShadowPainter extends CustomPainter {
  _GlassShadowPainter(this.shadows, this.radius);
  final List<GlassShadow> shadows;
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = glassShapePath(rect, radius);
    // Only outside the shape (like CSS box-shadow): the translucent glass must not show its own shadow.
    final outside = Path.combine(PathOperation.difference, Path()..addRect(rect.inflate(200)), shape);
    canvas.save();
    canvas.clipPath(outside);
    for (final s in shadows) {
      final base = radius ?? size.shortestSide / 2;
      final grown = rect.inflate(s.spread).shift(Offset(s.dx, s.dy));
      if (grown.width <= 0 || grown.height <= 0) continue;
      final path = glassShapePath(grown, radius == null ? null : (base + s.spread).clamp(0.0, double.infinity));
      final paint = Paint()..color = s.color;
      if (s.blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.blur / 2);
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassShadowPainter old) => old.shadows != shadows || old.radius != radius;
}

/// The colour matrix of a saturation boost (1 = unchanged), applied to the blurred backdrop of a material.
List<double> appleSaturationMatrix(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  return [
    r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0,
    r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0,
    r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}
