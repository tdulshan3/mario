import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'glass.dart';
import 'macos_tokens.dart';
import 'theme.dart';

/// The classic macOS blur materials (the same values as macos.css): [control] = Thin material for toolbar items and
/// the Dock, [panel] = Ultra Thick material for menus, popovers, sheets, alerts and notifications.
enum MacGlassStyle { control, panel }

GlassRecipe macGlassRecipe(MacGlassStyle style, {required bool dark}) {
  // The classic macOS blur materials (Big Sur … Sequoia style): the kit's material variables, background blur 60
  // in Figma = sigma 30; panels keep a 0.5 px hairline like classic macOS menus and popovers. Same as macos.css.
  if (style == MacGlassStyle.control) {
    // Material / Thin: #F6F6F6 48% · #282828 50%.
    return dark
        ? const GlassRecipe(fill: Color(0x80282828), blur: 30, saturation: 1.8, shadows: [
            GlassShadow(0, 0, 0, 0.5, Color(0x1FFFFFFF)),
            GlassShadow(0, 8, 15, 0, Color(0x1F000000)),
          ])
        : const GlassRecipe(fill: Color(0x7AF6F6F6), blur: 30, saturation: 1.8, shadows: [
            GlassShadow(0, 0, 0, 0.5, Color(0x1A000000)),
            GlassShadow(0, 8, 15, 0, Color(0x0A000000)),
          ]);
  }
  // Material / Ultra Thick: #F6F6F6 84% · #282828 80%.
  return dark
      ? const GlassRecipe(fill: Color(0xCC282828), blur: 30, saturation: 1.8, shadows: [
          GlassShadow(0, 0, 0, 0.5, Color(0x26FFFFFF)),
          GlassShadow(0, 18, 48, 0, Color(0x73000000)),
        ])
      : const GlassRecipe(fill: Color(0xD6F6F6F6), blur: 30, saturation: 1.8, shadows: [
          GlassShadow(0, 0, 0, 0.5, Color(0x1F000000)),
          GlassShadow(0, 18, 48, 0, Color(0x40000000)),
        ]);
}

/// The classic macOS blur material behind [child] (macos.css `mac-glass-control` / `mac-glass`; the name says glass for
/// compatibility, there is no Liquid Glass). Only for controls and panels
/// that float above content. [radius] null = capsule; panels in the kit use 26 (menus 13, popovers 20: see their docs).
class MacGlass extends StatelessWidget {
  const MacGlass({super.key, required this.child, this.style = MacGlassStyle.control, this.radius, this.padding = EdgeInsets.zero});

  final Widget child;
  final MacGlassStyle style;
  final double? radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final recipe = macGlassRecipe(style, dark: theme.isDark);
    final r = radius ?? (style == MacGlassStyle.panel ? 26.0 : null);
    Widget body = ColoredBox(color: recipe.fill, child: Padding(padding: padding, child: child));
    body = BackdropFilter(
      filter: ui.ImageFilter.compose(
        outer: ui.ColorFilter.matrix(appleSaturationMatrix(recipe.saturation)),
        inner: ui.ImageFilter.blur(sigmaX: recipe.blur, sigmaY: recipe.blur, tileMode: TileMode.clamp),
      ),
      child: body,
    );
    return CustomPaint(
      painter: _OuterShadows(recipe.shadows, r),
      child: ClipPath(clipper: _Clip(r), child: body),
    );
  }
}

class _Clip extends CustomClipper<Path> {
  _Clip(this.r);
  final double? r;
  @override
  Path getClip(Size size) => glassShapePath(Offset.zero & size, r);
  @override
  bool shouldReclip(_Clip old) => old.r != r;
}

class _OuterShadows extends CustomPainter {
  _OuterShadows(this.shadows, this.r);
  final List<GlassShadow> shadows;
  final double? r;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = glassShapePath(rect, r);
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(rect.inflate(200)), shape));
    for (final s in shadows) {
      final base = r ?? size.shortestSide / 2;
      final grown = rect.inflate(s.spread).shift(Offset(s.dx, s.dy));
      final p = Paint()..color = s.color;
      if (s.blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, s.blur / 2);
      canvas.drawPath(glassShapePath(grown, r == null ? null : base + s.spread), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadows old) => old.shadows != shadows || old.r != r;
}

/// Sets the macOS control size for every Mac control below (like `mac-size-small` on a container in macos.css).
///
///     MacControlSizeScope(size: MacControlSize.small, child: inspectorForm)
class MacControlSizeScope extends InheritedWidget {
  const MacControlSizeScope({super.key, required this.size, required super.child});
  final MacControlSize size;

  /// The size for controls here: the nearest scope, else medium (the default).
  static MacControlSize of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MacControlSizeScope>()?.size ?? MacControlSize.medium;

  /// Metrics (heights, radii, paddings…) for the size here.
  static MacSizes sizesOf(BuildContext context) => MacSizes.of(of(context));

  @override
  bool updateShouldNotify(MacControlSizeScope old) => old.size != size;
}

/// Marks a window as not focused (like `mac-inactive` in macos.css): accent colours of controls inside turn grey,
/// selection turns grey, toolbar glass turns flat. MacWindow sets it from the window focus automatically.
class MacWindowState extends InheritedWidget {
  const MacWindowState({super.key, required this.inactive, required super.child});
  final bool inactive;

  static bool isInactive(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MacWindowState>()?.inactive ?? false;

  @override
  bool updateShouldNotify(MacWindowState old) => old.inactive != inactive;
}

/// Marks its subtree as the inside of a macOS toolbar. `MacToolbar` adds it, and controls that have a toolbar
/// version (segmented control, pop-up and pull-down buttons, search field) switch to it automatically, like
/// `.mac-toolbar` in macos.css. Popovers, menus and sheets opened from a toolbar reset it (`inToolbar: false`),
/// so the controls in them get their normal look.
class MacToolbarScope extends InheritedWidget {
  const MacToolbarScope({super.key, this.inToolbar = true, required super.child});
  final bool inToolbar;

  static bool isInToolbar(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MacToolbarScope>()?.inToolbar ?? false;

  @override
  bool updateShouldNotify(MacToolbarScope old) => old.inToolbar != inToolbar;
}
