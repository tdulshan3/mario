// Shared parts of the iOS presentations (sheets, alerts, action sheets, activity views). Not exported.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/glass.dart';
import '../core/theme.dart';
import '../core/typography.dart';

/// Kit "Overlay - Alerts": #29293A 23% (Dark: the default overlay, black 48%).
Color presentationAlertDim(AppleThemeData theme) => theme.isDark ? const Color(0x7A000000) : const Color(0x3B29293A);

/// The backdrop filter of a material: the content behind blurred by [GlassRecipe.blur] and saturated by
/// [GlassRecipe.saturation] (the same as `backdrop-filter: blur() saturate()` in ios.css).
ui.ImageFilter presentationMaterialFilter(GlassRecipe recipe) => ui.ImageFilter.compose(
  outer: ui.ColorFilter.matrix(appleSaturationMatrix(recipe.saturation)),
  inner: ui.ImageFilter.blur(sigmaX: recipe.blur, sigmaY: recipe.blur, tileMode: TileMode.clamp),
);

/// The classic Thick blur material of panels ([AppleGlassStyle.panel] of [GlassRecipe]: blur + saturation under a
/// translucent fill, a soft drop shadow, no rims) with any corner radii (the kit's floating sheet is 34 at the top
/// and 58 at the bottom). Continuous corners. The name says glass for compatibility; there is no Liquid Glass.
class PresentationGlass extends StatelessWidget {
  const PresentationGlass({
    super.key,
    required this.child,
    required this.radius,
    this.extraShadows = const [],
    this.shadows,
  });

  final Widget child;
  final BorderRadius radius;

  /// Replaces the recipe's drop shadow (e.g. the small control shadow under a notification's action list).
  /// Null = the panel recipe's shadow.
  final List<GlassShadow>? shadows;

  /// Shadows added after the recipe's drop shadow (e.g. the popover's 0/10/100 black 30%).
  final List<GlassShadow> extraShadows;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final recipe = GlassRecipe.of(
      AppleGlassStyle.panel,
      dark: theme.isDark,
      accent: theme.accentColor,
      quaternaryFill: theme.ios.fillQuaternary,
    );
    final shape = RoundedSuperellipseBorder(borderRadius: radius);
    Widget body = ColoredBox(color: recipe.fill, child: child);
    body = BackdropFilter(filter: presentationMaterialFilter(recipe), child: body);
    return CustomPaint(
      painter: PresentationShadowPainter([...(shadows ?? recipe.shadows), ...extraShadows], shape),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: body,
      ),
    );
  }
}

/// An opaque presentation surface (large sheet, iPad sheet) with continuous corners and an outside-only shadow.
class PresentationSurface extends StatelessWidget {
  const PresentationSurface({
    super.key,
    required this.child,
    required this.color,
    required this.radius,
    this.shadows = const [],
  });

  final Widget child;
  final Color color;
  final BorderRadius radius;
  final List<GlassShadow> shadows;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedSuperellipseBorder(borderRadius: radius);
    return CustomPaint(
      painter: PresentationShadowPainter(shadows, shape),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: ColoredBox(color: color, child: child),
      ),
    );
  }
}

/// Paints kit shadows only OUTSIDE [shape] (like CSS box-shadow), so a translucent material doesn't show its own
/// shadow.
class PresentationShadowPainter extends CustomPainter {
  PresentationShadowPainter(this.shadows, this.shape);
  final List<GlassShadow> shadows;
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final rect = Offset.zero & size;
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect.inflate(400)),
      shape.getOuterPath(rect),
    );
    canvas.save();
    canvas.clipPath(outside);
    for (final s in shadows) {
      final grown = rect.inflate(s.spread).shift(Offset(s.dx, s.dy));
      if (grown.width <= 0 || grown.height <= 0) continue;
      final paint = Paint()..color = s.color;
      if (s.blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.blur / 2);
      canvas.drawPath(shape.getOuterPath(grown), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PresentationShadowPainter old) => old.shadows != shadows || old.shape != shape;
}

/// Role of an alert / action sheet button (kit "_Buttons" Role).
enum PresentationActionLook { plain, prominent, destructive }

/// Kit "_Buttons": a 48-tall capsule, padding 13/16, label Semibold 17/22. Plain = Fills/Secondary + primary label,
/// prominent = accent fill + white label, destructive = Fills/Secondary + red label. Pressed: darker (lighter in Dark).
class PresentationActionButton extends StatefulWidget {
  const PresentationActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.look = PresentationActionLook.plain,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final PresentationActionLook look;
  final IconData? icon;
  final bool expand;

  @override
  State<PresentationActionButton> createState() => _PresentationActionButtonState();
}

class _PresentationActionButtonState extends State<PresentationActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final enabled = widget.onPressed != null;
    var fill = c.fillSecondary;
    var label = c.labelPrimary;
    if (widget.look == PresentationActionLook.prominent && enabled) {
      fill = theme.accentColor;
      label = const Color(0xFFFFFFFF);
    } else if (widget.look == PresentationActionLook.destructive) {
      label = c.red;
    }
    if (!enabled) label = c.labelTertiary;
    final text = IosTypography.of(context).headline.copyWith(color: label);
    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[Icon(widget.icon, size: 20, color: label), const SizedBox(width: 8)],
        Flexible(
          child: Text(
            widget.label,
            style: text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
    Widget button = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
          child: Center(widthFactor: 1, child: content),
        ),
      ),
    );
    if (widget.expand) button = SizedBox(width: double.infinity, child: button);
    if (_pressed && enabled) {
      button = ColorFiltered(
        colorFilter: ColorFilter.mode(
          theme.isDark ? const Color(0x33FFFFFF) : const Color(0x1A000000),
          BlendMode.srcATop,
        ),
        child: button,
      );
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: button,
        ),
      ),
    );
  }
}

/// Title (Semibold 17) and message (Regular 17), left-aligned, padding 8/8/24/8, 10 apart (alerts, action sheets).
class PresentationTitleBlock extends StatelessWidget {
  const PresentationTitleBlock({super.key, this.title, this.message});
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = IosTypography.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) Semantics(header: true, child: Text(title!, style: t.headline)),
          if (title != null && message != null) const SizedBox(height: 10),
          if (message != null) Text(message!, style: t.body),
        ],
      ),
    );
  }
}

/// Where a panel of [size] goes next to [source] (iPad: below it, or above when there is no room; 8 apart) or over it
/// (iPhone: its top edge on the button's top edge, the kit's action sheet). Same rules as ios.js.
Offset presentationPlacement({required Rect source, required Size size, required Size screen, required bool regular}) {
  final margin = regular ? 8.0 : 4.0;
  final cx = source.center.dx;
  double left;
  if (cx > screen.width * 0.6) {
    left = (regular ? source.right : source.right + 12) - size.width;
  } else if (cx < screen.width * 0.4) {
    left = regular ? source.left : source.left - 12;
  } else {
    left = cx - size.width / 2;
  }
  left = left.clamp(margin, math.max(margin, screen.width - size.width - margin));
  double top;
  if (regular) {
    final below = source.bottom + 8;
    top = below + size.height <= screen.height - margin || source.top - 8 - size.height < margin
        ? below
        : source.top - 8 - size.height;
  } else {
    top = source.center.dy < screen.height / 2 ? source.top : source.bottom - size.height;
  }
  top = top.clamp(margin, math.max(margin, screen.height - size.height - margin));
  return Offset(left, top);
}

/// The global rect of the widget with [key] (null when it isn't laid out).
Rect? presentationRectOf(GlobalKey? key) {
  final box = key?.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
