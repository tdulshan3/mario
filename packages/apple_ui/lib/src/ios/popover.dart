import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/glass.dart';
import '../core/ios_tokens.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '_menu_support.dart';
import '_presentation_support.dart' show presentationMaterialFilter;
import 'menu.dart';

/// The edge of a popover that carries the ARROW (kit "Edge"): [top] = the popover sits BELOW its source,
/// [bottom] = above it, [leading] = to its trailing side, [trailing] = to its leading side. [auto] picks the first
/// that fits in this order: top, bottom, leading, trailing.
enum IosPopoverEdge { auto, top, bottom, leading, trailing }

const double _kArrowHeight = 13;                         // kit "Arrow" 56 × 13
const double _kArrowWidth = 56;
const double _kArrowGap = 4;                             // arrow tip → source
const double _kCorner = 72;                              // kit: the arrow centre sits 44 + 28 from a corner
const double _kMinArrow = 56;                            // …or 28 + 28 for a source at the screen edge

@immutable
class _ArrowPlacement {
  const _ArrowPlacement(this.edge, this.offset);
  final IosPopoverEdge edge;

  /// Centre of the arrow along its edge; null = the middle.
  final double? offset;
  @override
  bool operator ==(Object other) => other is _ArrowPlacement && other.edge == edge && other.offset == offset;
  @override
  int get hashCode => Object.hash(edge, offset);
}

/// The kit arrow outline (pointing up, tip at (28, 0), base on y = 13), translated and turned for [edge].
Path _arrowPath(Size size, _ArrowPlacement p) {
  final up = Path()
    ..moveTo(0, 13)
    ..cubicTo(2.04, 13, 4.08, 13.01, 6.12, 12.99)
    ..cubicTo(8.07, 12.97, 10.26, 12.95, 12.16, 12.34)
    ..cubicTo(14.21, 11.69, 15.57, 10.56, 16.94, 9.22)
    ..cubicTo(17.92, 8.26, 19.86, 6.2, 20.8, 5.21)
    ..cubicTo(21.57, 4.4, 23.08, 2.79, 23.9, 2.02)
    ..cubicTo(24.94, 1.04, 26.22, 0, 28, 0)
    ..cubicTo(29.78, 0, 31.06, 1.04, 32.1, 2.02)
    ..cubicTo(32.92, 2.79, 34.43, 4.4, 35.2, 5.21)
    ..cubicTo(36.14, 6.2, 38.08, 8.26, 39.06, 9.22)
    ..cubicTo(40.43, 10.56, 41.79, 11.69, 43.84, 12.34)
    ..cubicTo(45.74, 12.94, 47.93, 12.97, 49.88, 12.99)
    ..cubicTo(51.92, 13.01, 53.96, 13, 56, 13)
    ..lineTo(42, 13)                                     // the middle reaches 1 into the body: no hairline gap
    ..lineTo(42, 14)
    ..lineTo(14, 14)
    ..lineTo(14, 13)
    ..close();
  final along = (p.edge == IosPopoverEdge.top || p.edge == IosPopoverEdge.bottom) ? size.width : size.height;
  final c = p.offset ?? along / 2;
  final m = Matrix4.identity();
  switch (p.edge) {
    case IosPopoverEdge.top || IosPopoverEdge.auto:
      m.translateByDouble(c - _kArrowWidth / 2, -_kArrowHeight, 0, 1);
    case IosPopoverEdge.bottom:
      m
        ..translateByDouble(c + _kArrowWidth / 2, size.height + _kArrowHeight, 0, 1)
        ..rotateZ(math.pi);
    case IosPopoverEdge.leading:
      m
        ..translateByDouble(-_kArrowHeight, c + _kArrowWidth / 2, 0, 1)
        ..rotateZ(-math.pi / 2);
    case IosPopoverEdge.trailing:
      m
        ..translateByDouble(size.width + _kArrowHeight, c - _kArrowWidth / 2, 0, 1)
        ..rotateZ(math.pi / 2);
  }
  return up.transform(m.storage);
}

Path _popoverShape(Size size, _ArrowPlacement? p, double radius) {
  final body = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius)).getOuterPath(Offset.zero & size);
  if (p == null) return body;
  return Path.combine(PathOperation.union, body, _arrowPath(size, p));
}

class _PopoverClipper extends CustomClipper<Path> {
  _PopoverClipper(this.placement, this.radius) : super(reclip: placement);
  final ValueListenable<_ArrowPlacement?> placement;
  final double radius;
  @override
  Path getClip(Size size) => _popoverShape(size, placement.value, radius);
  @override
  bool shouldReclip(_PopoverClipper old) => old.placement != placement || old.radius != radius;
}

class _PopoverPainter extends CustomPainter {
  _PopoverPainter(this.placement, this.radius, this.fill, this.shadow) : super(repaint: placement);
  final ValueListenable<_ArrowPlacement?> placement;
  final double radius;
  final Color? fill;
  final GlassShadow? shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _popoverShape(size, placement.value, radius);
    if (shadow != null) {
      final s = shadow!;
      final outside = Path.combine(PathOperation.difference, Path()..addRect((Offset.zero & size).inflate(300)), path);
      canvas.save();
      canvas.clipPath(outside);
      canvas.drawPath(
        path.shift(Offset(s.dx, s.dy)),
        Paint()
          ..color = s.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.blur / 2),
      );
      canvas.restore();
    }
    if (fill != null) canvas.drawPath(path, Paint()..color = fill!);
  }

  @override
  bool shouldRepaint(_PopoverPainter old) =>
      old.placement != placement || old.radius != radius || old.fill != fill || old.shadow != shadow;
}

/// The material body + arrow (Thick material: blur + saturation, no rims), reading the arrow from [placement] at
/// paint time.
class _PopoverBody extends StatelessWidget {
  const _PopoverBody({required this.placement, required this.child, this.width});
  final ValueListenable<_ArrowPlacement?> placement;
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final recipe = GlassRecipe.of(AppleGlassStyle.panel, dark: theme.isDark, accent: theme.accentColor, quaternaryFill: theme.ios.fillQuaternary);
    const radius = 38.0;                                 // kit "Popover Corner Radius"
    const shadow = GlassShadow(0, 10, 100, 0, Color(0x4D000000)); // kit: 0 10 r100 black 30%
    Widget body = CustomPaint(
      painter: _PopoverPainter(placement, radius, recipe.fill, null),
      child: DefaultTextStyle(
        style: appleFont(size: 17).copyWith(
          fontSize: 17,
          height: 22 / 17,
          letterSpacing: -0.43,
          color: theme.ios.labelPrimary,
          decoration: TextDecoration.none,
        ),
        child: child,
      ),
    );
    body = BackdropFilter(filter: presentationMaterialFilter(recipe), child: body);
    return CustomPaint(
      painter: _PopoverPainter(placement, radius, null, shadow),
      child: ClipPath(clipper: _PopoverClipper(placement, radius), child: SizedBox(width: width, child: body)),
    );
  }
}

/// A popover panel drawn in place (kit "Popovers (iPad Only)"): Thick material, r=38, the 56 × 13 arrow on [edge] at
/// [arrowOffset] (centre of the arrow along that edge; null = the middle). The arrow is painted OUTSIDE the box.
/// [IosPopover] shows and places it for you; use this only to draw one yourself (a mockup, a kit sheet).
class IosPopoverPanel extends StatefulWidget {
  const IosPopoverPanel({super.key, required this.child, this.edge = IosPopoverEdge.top, this.arrowOffset, this.width});
  final Widget child;
  final IosPopoverEdge edge;
  final double? arrowOffset;
  final double? width;

  @override
  State<IosPopoverPanel> createState() => _IosPopoverPanelState();
}

class _IosPopoverPanelState extends State<IosPopoverPanel> {
  late final _placement = ValueNotifier<_ArrowPlacement?>(_ArrowPlacement(widget.edge, widget.arrowOffset));

  @override
  void didUpdateWidget(IosPopoverPanel old) {
    super.didUpdateWidget(old);
    _placement.value = _ArrowPlacement(widget.edge, widget.arrowOffset);
  }

  @override
  void dispose() {
    _placement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PopoverBody(placement: _placement, width: widget.width, child: widget.child);
}

/// Places the popover next to its source and tells the arrow where to go.
class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout({required this.source, required this.prefer, required this.placement, required this.rtl});
  final Rect source;
  final IosPopoverEdge prefer;
  final ValueNotifier<_ArrowPlacement?> placement;
  final bool rtl;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: math.min(600, constraints.maxWidth - 40), maxHeight: constraints.maxHeight - 40);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const m = 20.0;
    final w = childSize.width;
    final h = childSize.height;
    const out = _kArrowHeight + _kArrowGap;
    final fits = {
      IosPopoverEdge.top: source.bottom + out + h <= size.height - m,
      IosPopoverEdge.bottom: source.top - out - h >= m,
      IosPopoverEdge.leading: source.right + out + w <= size.width - m,
      IosPopoverEdge.trailing: source.left - out - w >= m,
    };
    var side = prefer;
    if (side == IosPopoverEdge.auto || fits[side] != true) {
      side = const [IosPopoverEdge.top, IosPopoverEdge.bottom, IosPopoverEdge.leading, IosPopoverEdge.trailing]
          .firstWhere((s) => fits[s]!, orElse: () => IosPopoverEdge.top);
    }
    double left;
    double top;
    double arrow;
    if (side == IosPopoverEdge.top || side == IosPopoverEdge.bottom) {
      final cx = source.center.dx;
      left = (cx - w / 2).clamp(m, math.max(m, size.width - m - w));
      if (cx - left < _kCorner) {
        left = math.max(4, cx - _kCorner);
      } else if (left + w - cx < _kCorner) {
        left = math.min(size.width - 4 - w, cx + _kCorner - w);
      }
      top = side == IosPopoverEdge.top ? source.bottom + out : source.top - out - h;
      arrow = (cx - left).clamp(math.min(_kMinArrow, w / 2), math.max(w - _kMinArrow, w / 2));
    } else {
      final cy = source.center.dy;
      top = (cy - h / 2).clamp(m, math.max(m, size.height - m - h));
      if (cy - top < _kCorner) {
        top = math.max(4, cy - _kCorner);
      } else if (top + h - cy < _kCorner) {
        top = math.min(size.height - 4 - h, cy + _kCorner - h);
      }
      left = side == IosPopoverEdge.leading ? source.right + out : source.left - out - w;
      arrow = (cy - top).clamp(math.min(_kMinArrow, h / 2), math.max(h - _kMinArrow, h / 2));
    }
    placement.value = _ArrowPlacement(side, arrow);
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) => old.source != source || old.prefer != prefer || old.rtl != rtl;
}

/// iPad: a panel of Thick blur material with an arrow pointing at the control that opened it (a tap outside or Esc
/// closes it).
/// iPhone (compact width): the same content opens as a sheet from the bottom — iOS has no popovers on iPhone.
///
///     IosPopover(
///       semanticLabel: 'Filters',
///       trigger: (context, open) => IosButton(label: 'Filters', onPressed: open),
///       builder: (context, close) => Padding(
///         padding: const EdgeInsets.all(20),
///         child: Column(mainAxisSize: MainAxisSize.min, children: [
///           const Text('Filters'),
///           IosButton(label: 'Done', style: IosButtonStyle.prominent, onPressed: close),
///         ]),
///       ),
///     )
class IosPopover extends StatefulWidget {
  const IosPopover({
    super.key,
    required this.trigger,
    required this.builder,
    this.edge = IosPopoverEdge.auto,
    this.width = 320,
    this.semanticLabel,
    this.onOpenChanged,
  });

  final IosMenuTriggerBuilder trigger;

  /// The content. Call [close] from a "Done" button.
  final Widget Function(BuildContext context, VoidCallback close) builder;

  /// The arrow edge on iPad (see [IosPopoverEdge]).
  final IosPopoverEdge edge;

  /// Width of the popover on iPad (320 is typical). On iPhone the sheet is full width.
  final double? width;
  final String? semanticLabel;
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<IosPopover> createState() => _IosPopoverState();
}

class _IosPopoverState extends State<IosPopover> {
  final _portal = OverlayPortalController();
  final _sourceKey = GlobalKey();
  final _placement = ValueNotifier<_ArrowPlacement?>(null);
  Rect _source = Rect.zero;

  void _open() {
    final source = _sourceKey.currentContext;
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    if (source == null || overlay == null || _portal.isShowing) return;
    setState(() => _source = menuRectIn(source, overlay));
    _portal.show();
    widget.onOpenChanged?.call(true);
  }

  void _close() {
    if (!_portal.isShowing) return;
    _portal.hide();
    if (mounted) setState(() {});
    widget.onOpenChanged?.call(false);
  }

  @override
  void dispose() {
    _placement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        final theme = AppleTheme.of(context);
        final regular = MenuMetrics.of(context).regular;
        final content = Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: widget.semanticLabel,
          // Presented above the app: the "Elevated" background colours (they differ in Dark Mode).
          child: AppleTheme(data: theme.copyWith(elevated: true), child: Builder(builder: (context) => widget.builder(context, _close))),
        );
        Widget panel;
        if (regular) {
          panel = Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _PopoverLayout(
                source: _source,
                prefer: widget.edge,
                placement: _placement,
                rtl: Directionality.of(context) == TextDirection.rtl,
              ),
              child: MenuAppear(from: 0.85, child: _PopoverBody(placement: _placement, width: widget.width, child: content)),
            ),
          );
        } else {
          // iPhone: a sheet from the bottom (sheet radii 38 top / 58 bottom, 8 from the screen edges).
          const dims = IosDimensions.iphone;
          final shape = RoundedSuperellipseBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(dims.sheetTopRadius),
              bottom: Radius.circular(dims.sheetBottomRadius),
            ),
          );
          panel = Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 0),
              duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => FractionalTranslation(translation: Offset(0, t), child: child),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 64),
                child: DecoratedBox(
                  decoration: ShapeDecoration(color: theme.ios.bgPrimaryElevated, shape: shape),
                  child: ClipPath(
                    clipper: ShapeBorderClipper(shape: shape),
                    child: DefaultTextStyle(
                      style: appleFont(size: 17).copyWith(
                        fontSize: 17,
                        height: 22 / 17,
                        letterSpacing: -0.43,
                        color: theme.ios.labelPrimary,
                        decoration: TextDecoration.none,
                      ),
                      child: content,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
              _close();
              return null;
            }),
          },
          child: FocusScope(
            autofocus: true,
            child: SizedBox.expand(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => _close(),
                      child: ColoredBox(color: regular ? const Color(0x00000000) : theme.ios.overlay),
                    ),
                  ),
                  panel,
                ],
              ),
            ),
          ),
        );
      },
      child: KeyedSubtree(key: _sourceKey, child: widget.trigger(context, _open)),
    );
  }
}
