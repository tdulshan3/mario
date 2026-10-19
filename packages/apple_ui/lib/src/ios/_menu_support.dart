// Shared parts of the iOS menus (menus, context menus, pop-up / pull-down buttons) and popovers. Not exported.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/adaptive.dart';
import '../core/ios_tokens.dart';
import '../core/theme.dart';
import '../core/typography.dart';

/// Menu colours. The kit draws "Labels - Vibrant/*" plus-darker (Light) / plus-lighter (Dark) over the material panel;
/// resolved over the kit panel (#F0F0F0 Light, #1E1E1E Dark) they are these flat colours (same as menus.css).
class MenuColors {
  const MenuColors._({
    required this.label,
    required this.secondary,
    required this.tertiary,
    required this.quaternary,
    required this.separator,
    required this.highlight,
    required this.openFill,
    required this.editSeparator,
    required this.destructive,
  });

  final Color label;
  final Color secondary;
  final Color tertiary;
  final Color quaternary;
  final Color separator;
  final Color highlight;
  final Color openFill;
  final Color editSeparator;
  final Color destructive;

  static MenuColors of(BuildContext context) {
    final theme = AppleTheme.of(context);
    return theme.isDark
        ? const MenuColors._(
            label: Color(0xFFFFFFFF),
            secondary: Color(0xFFA8A8A8),
            tertiary: Color(0xFF5E5E5E),
            quaternary: Color(0xFF444444),
            separator: Color(0xFF383838),
            highlight: Color(0xFF303030),
            openFill: Color(0xFF303030),
            editSeparator: Color(0xFF515151),
            destructive: Color(0xFFFF6063),
          )
        : MenuColors._(
            label: const Color(0xFF0B0B0B),
            secondary: const Color(0xFF636363),
            tertiary: const Color(0xFFB0B0B0),
            quaternary: const Color(0xFFCACACA),
            separator: const Color(0xFFD7D7D7),
            highlight: const Color(0xFFDEDEDE),
            openFill: const Color(0xFFEDEDED),
            editSeparator: const Color(0xFFBDBDBD),
            destructive: theme.ios.red,
          );
  }
}

/// Menu metrics for the current size class (kit "Dimensions": iPhone / iPad).
class MenuMetrics {
  MenuMetrics._(this.regular, this.dims, this.fontSize, this.lineHeight, this.tracking);

  final bool regular;
  final IosDimensions dims;
  final double fontSize;
  final double lineHeight;
  final double tracking;

  /// iPhone: Size/Body (17 at the default Dynamic Type size) on a 20 line. iPad: 15 on 18.
  static MenuMetrics of(BuildContext context) {
    final regular = IosLayout.isRegular(context);
    final dims = regular ? IosDimensions.ipad : IosDimensions.iphone;
    if (regular) return MenuMetrics._(true, dims, dims.menuItemSize, dims.menuItemLeading, -0.23);
    final body = IosTypography.of(context).body;
    final size = body.fontSize ?? 17;
    return MenuMetrics._(false, dims, size, size * (body.height ?? 22 / 17) - 2, body.letterSpacing ?? -0.43);
  }
}

/// The small glyphs of the menus, drawn as strokes on the same 16-unit grid as the web icons
/// (CupertinoIcons has no bold chevrons): chevron.right / chevron.down / chevron.up.chevron.down / checkmark.
enum MenuGlyphKind { chevronRight, chevronDown, chevronUpDown, checkmark }

class MenuGlyph extends StatelessWidget {
  const MenuGlyph(this.kind, {super.key, required this.color, required this.size, this.width, this.height});

  final MenuGlyphKind kind;
  final Color color;

  /// Drawn size of the 14-unit icon box.
  final double size;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width ?? size,
    height: height ?? size,
    child: CustomPaint(painter: _MenuGlyphPainter(kind, color, size)),
  );
}

class _MenuGlyphPainter extends CustomPainter {
  _MenuGlyphPainter(this.kind, this.color, this.box);
  final MenuGlyphKind kind;
  final Color color;
  final double box;

  @override
  void paint(Canvas canvas, Size size) {
    final s = box / 14; // viewBox 1..15 like the web icons
    canvas.translate((size.width - box) / 2 - s, (size.height - box) / 2 - s);
    Offset p(double x, double y) => Offset(x * s, y * s);
    final path = Path();
    double stroke;
    switch (kind) {
      case MenuGlyphKind.chevronRight:
        path
          ..moveTo(p(6.2, 4.8).dx, p(6.2, 4.8).dy)
          ..lineTo(p(9.8, 8).dx, p(9.8, 8).dy)
          ..lineTo(p(6.2, 11.2).dx, p(6.2, 11.2).dy);
        stroke = 1.75;
      case MenuGlyphKind.chevronDown:
        path
          ..moveTo(p(3, 5.75).dx, p(3, 5.75).dy)
          ..lineTo(p(8, 10.25).dx, p(8, 10.25).dy)
          ..lineTo(p(13, 5.75).dx, p(13, 5.75).dy);
        stroke = 2;
      case MenuGlyphKind.chevronUpDown:
        path
          ..moveTo(p(4.9, 6.1).dx, p(4.9, 6.1).dy)
          ..lineTo(p(8, 3).dx, p(8, 3).dy)
          ..lineTo(p(11.1, 6.1).dx, p(11.1, 6.1).dy)
          ..moveTo(p(4.9, 9.9).dx, p(4.9, 9.9).dy)
          ..lineTo(p(8, 13).dx, p(8, 13).dy)
          ..lineTo(p(11.1, 9.9).dx, p(11.1, 9.9).dy);
        stroke = 1.75;
      case MenuGlyphKind.checkmark:
        path
          ..moveTo(p(3.1, 8.6).dx, p(3.1, 8.6).dy)
          ..lineTo(p(6.45, 11.9).dx, p(6.45, 11.9).dy)
          ..lineTo(p(12.9, 4.3).dx, p(12.9, 4.3).dy);
        stroke = 2;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MenuGlyphPainter old) => old.kind != kind || old.color != color || old.box != box;
}

/// The rect of [context]'s render box in the coordinates of [overlay] (the Overlay the menu is shown in).
Rect menuRectIn(BuildContext context, RenderBox overlay) {
  final box = context.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  return topLeft & box.size;
}

/// Places a menu 8 below its anchor (above when there is no room), aligned to the anchor's leading edge
/// (trailing edge when the anchor is in the right half), inside the screen margins (16 iPhone / 20 iPad).
class MenuPlacementDelegate extends SingleChildLayoutDelegate {
  MenuPlacementDelegate({required this.anchor, required this.margin, this.gap = 8});
  final Rect anchor;
  final double margin;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final room = math.max(anchor.top, constraints.maxHeight - anchor.bottom) - gap - margin;
    return BoxConstraints(
      maxWidth: constraints.maxWidth - 2 * margin,
      maxHeight: math.max(120, room > 0 ? math.max(room, constraints.maxHeight - 2 * margin) : 120),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final child = childSize;
    // >= : a full-width trigger (a list row) opens its menu at its trailing end, under the value, like iOS.
    final alignRight = anchor.center.dx >= size.width / 2;
    final left = (alignRight ? anchor.right - child.width : anchor.left).clamp(
      margin,
      math.max(margin, size.width - margin - child.width),
    );
    double top;
    if (anchor.bottom + gap + child.height <= size.height - margin) {
      top = anchor.bottom + gap;
    } else if (anchor.top - gap - child.height >= margin) {
      top = anchor.top - gap - child.height;
    } else {
      top = (size.height - margin - child.height).clamp(margin, math.max(margin, size.height - margin));
    }
    return Offset(left.toDouble(), top);
  }

  @override
  bool shouldRelayout(MenuPlacementDelegate old) => old.anchor != anchor || old.margin != margin || old.gap != gap;
}

/// Places a submenu: iPhone = over its row (left of the parent menu, the row's top − 10); iPad = beside the parent
/// menu overlapping it by 8 (to the left when there is no room on the right).
class SubmenuPlacementDelegate extends SingleChildLayoutDelegate {
  SubmenuPlacementDelegate({required this.parent, required this.row, required this.regular});
  final Rect parent;
  final Rect row;
  final bool regular;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: constraints.maxHeight - 2 * (regular ? 20 : 16));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final child = childSize;
    final m = regular ? 20.0 : 16.0;
    var left = regular ? parent.right - 8 : parent.left;
    if (regular && left + child.width > size.width - m) left = parent.left - child.width + 8;
    left = left.clamp(m, math.max(m, size.width - m - child.width));
    final top = (row.top - 10).clamp(m, math.max(m, size.height - m - child.height));
    return Offset(left.toDouble(), top.toDouble());
  }

  @override
  bool shouldRelayout(SubmenuPlacementDelegate old) => old.parent != parent || old.row != row || old.regular != regular;
}

/// A short scale + fade when a menu or popover appears (none with Reduce Motion).
class MenuAppear extends StatelessWidget {
  const MenuAppear({super.key, required this.child, this.alignment = Alignment.topCenter, this.from = 0.6});
  final Widget child;
  final Alignment alignment;
  final double from;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: from + (1 - from) * t, alignment: alignment, child: child),
      ),
      child: child,
    );
  }
}
