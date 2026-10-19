import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '_panel_support.dart';

/// Where a popover sits next to the control it points at (web `data-mac-edge`). The arrow is on the opposite
/// edge of the popover: [bottom] = below the control, arrow on the popover's top edge pointing up.
enum MacPopoverEdge { bottom, top, left, right }

/// Where the arrow sits along its edge (web `data-mac-arrow`): [center]; [start] / [end] = the kit's corner
/// variants (tip 27 px from the top/left or bottom/right corner, merged into the corner); [none] = no arrow.
enum MacPopoverArrow { center, start, end, none }

@immutable
class _ArrowGeometry {
  const _ArrowGeometry(this.edge, this.arrow, [this.tip]);
  final MacPopoverEdge edge;
  final MacPopoverArrow arrow;

  /// Arrow tip along the edge, from the top/left corner. Null = from [arrow] and the size.
  final double? tip;

  @override
  bool operator ==(Object other) => other is _ArrowGeometry && other.edge == edge && other.arrow == arrow && other.tip == tip;

  @override
  int get hashCode => Object.hash(edge, arrow, tip);
}

// The kit's arrow ("Cartouche", 46 × 10.5 + a 4 px band over the body edge), drawn for the top edge pointing up:
// tip at (23, 0), body edge at y = 10.5 (popovers.css mask paths).
final Path _arrowCenter = () {
  final p = Path()
    ..moveTo(0, 10.5)
    ..lineTo(5.28, 10.5)
    ..cubicTo(7.78, 10.5, 8.9, 10.44, 10.03, 10)
    ..cubicTo(11.16, 9.56, 12.17, 8.58, 13.11, 7.65)
    ..lineTo(15.76, 5)
    ..lineTo(19.07, 1.69)
    ..cubicTo(20.4, .31, 21.65, 0, 23, 0)
    ..cubicTo(24.35, 0, 25.6, .3, 26.93, 1.69)
    ..lineTo(30.24, 5)
    ..lineTo(32.89, 7.65)
    ..cubicTo(33.83, 8.58, 34.85, 9.56, 35.97, 10)
    ..cubicTo(37.1, 10.44, 38.22, 10.5, 40.72, 10.5)
    ..lineTo(46, 10.5)
    ..lineTo(46, 14.5)
    ..lineTo(0, 14.5)
    ..close();
  return Path.combine(PathOperation.union, p, p.shift(const Offset(0, -0.5)));
}();

// Corner variant ("start"): the left shoulder merges into the body's rounded corner.
final Path _arrowCorner = () {
  final p = Path()
    ..moveTo(6.98, 12.73)
    ..cubicTo(8.99, 11.65, 10.47, 10.28, 12.71, 8.05)
    ..lineTo(15.76, 5)
    ..lineTo(19.07, 1.69)
    ..cubicTo(20.4, .3, 21.64, 0, 23, 0)
    ..cubicTo(24.36, 0, 25.6, .3, 26.92, 1.69)
    ..lineTo(30.23, 5)
    ..lineTo(32.88, 7.65)
    ..cubicTo(33.82, 8.58, 34.83, 9.56, 35.96, 10)
    ..cubicTo(37.09, 10.44, 38.21, 10.5, 40.71, 10.5)
    ..lineTo(46, 10.5)
    ..lineTo(46, 14.5)
    ..lineTo(6.98, 14.5)
    ..close();
  return Path.combine(PathOperation.union, p, p.shift(const Offset(0, -0.5)));
}();

const double _kCorner = 27; // closest the arrow tip gets to a corner (kit corner variants)
const double _kMerge = 43; // below this the arrow merges into the corner
const double _kRadius = 20;

/// Body (radius 20) + arrow as one outline. [body] is the popover box; [spread] grows the body (CSS shadows).
Path _popoverPath(Rect body, _ArrowGeometry g, double spread) {
  final b = body.inflate(spread);
  if (b.width <= 0 || b.height <= 0) return Path();
  final r = (_kRadius + spread).clamp(0.0, b.shortestSide / 2);
  final bodyPath = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(r)).getOuterPath(b);
  if (g.arrow == MacPopoverArrow.none) return bodyPath;
  final vertical = g.edge == MacPopoverEdge.bottom || g.edge == MacPopoverEdge.top; // arrow on top/bottom edge
  final along = vertical ? body.width : body.height;
  final tip = g.tip ??
      switch (g.arrow) {
        MacPopoverArrow.start => _kCorner,
        MacPopoverArrow.end => along - _kCorner,
        _ => along / 2,
      };
  final s = g.arrow == MacPopoverArrow.end ? -1.0 : 1.0;
  // X = a·x + b·y + tx ; Y = c·x + d·y + ty   (local arrow coordinates → popover coordinates)
  final double a, bb, tx, c, d, ty;
  switch (g.edge) {
    case MacPopoverEdge.bottom: // popover below the control: arrow on the top edge, pointing up
      a = s; bb = 0; tx = body.left + tip - 23 * s;
      c = 0; d = 1; ty = body.top - 10.5;
    case MacPopoverEdge.top: // above: arrow on the bottom edge, pointing down
      a = s; bb = 0; tx = body.left + tip - 23 * s;
      c = 0; d = -1; ty = body.bottom + 10.5;
    case MacPopoverEdge.right: // right of the control: arrow on the left edge, pointing left
      a = 0; bb = 1; tx = body.left - 10.5;
      c = s; d = 0; ty = body.top + tip - 23 * s;
    case MacPopoverEdge.left: // left of the control: arrow on the right edge, pointing right
      a = 0; bb = -1; tx = body.right + 10.5;
      c = s; d = 0; ty = body.top + tip - 23 * s;
  }
  final m = Matrix4.identity()
    ..setEntry(0, 0, a)
    ..setEntry(0, 1, bb)
    ..setEntry(0, 3, tx)
    ..setEntry(1, 0, c)
    ..setEntry(1, 1, d)
    ..setEntry(1, 3, ty);
  final arrow = (g.arrow == MacPopoverArrow.center ? _arrowCenter : _arrowCorner).transform(m.storage);
  return Path.combine(PathOperation.union, bodyPath, arrow);
}

const double _kArrowRoom = 11; // the material layer reaches this far outside the box (arrow 10.5)

/// The 0.5 px hairline of the popover material, outside the body and the arrow.
class _HairlinePainter extends CustomPainter {
  _HairlinePainter(this.geometry, this.color) : super(repaint: geometry);
  final ValueListenable<_ArrowGeometry> geometry;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final path = _popoverPath(bounds.deflate(_kArrowRoom), geometry.value, 0);
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(bounds), path));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 // half of it is outside the shape: 0.5 px
        ..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HairlinePainter old) => old.geometry != geometry || old.color != color;
}

class _PopoverBody extends StatelessWidget {
  const _PopoverBody({required this.geometry, required this.child, required this.padding, this.width, this.height});
  final ValueListenable<_ArrowGeometry> geometry;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final dark = theme.isDark;
    final vertical = geometry.value.edge == MacPopoverEdge.bottom || geometry.value.edge == MacPopoverEdge.top;
    final hasArrow = geometry.value.arrow != MacPopoverArrow.none;
    // The classic Ultra Thick blur material with its 0.5 px hairline and the kit's drop shadow (0 8 48); no rims.
    // The hairline is stroked around body AND arrow (a spread shadow would only grow the body).
    final material = panelMaterial(dark, drop: [panelDropShadow(dark)]);
    bool isHairline(PanelShadow s) => s.dx == 0 && s.dy == 0 && s.blur == 0 && !s.inset;
    final hairline = material.shadows.where(isHairline).map((s) => s.color).firstOrNull;
    // The edge with the arrow is at least 86 px long (20 corner + 46 arrow + 20 corner).
    Widget content = ConstrainedBox(
      constraints: BoxConstraints(minWidth: hasArrow && vertical ? 86 : 0, minHeight: hasArrow && !vertical ? 86 : 0),
      child: Padding(padding: padding, child: child),
    );
    if (width != null || height != null) content = SizedBox(width: width, height: height, child: content);
    return DefaultTextStyle(
      style: MacTypography.of(context).body,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -_kArrowRoom,
            top: -_kArrowRoom,
            right: -_kArrowRoom,
            bottom: -_kArrowRoom,
            child: IgnorePointer(
              child: CustomPaint(
                foregroundPainter: hairline == null ? null : _HairlinePainter(geometry, hairline),
                child: PanelSurface(
                  shape: (rect, spread) => _popoverPath(rect.deflate(_kArrowRoom), geometry.value, spread),
                  fill: material.fill,
                  backdrop: material.backdrop,
                  shadows: material.shadows.where((s) => !isHairline(s)).toList(),
                  repaint: geometry,
                ),
              ),
            ),
          ),
          content,
        ],
      ),
    );
  }
}

/// The popover panel drawn in place (kit "Popover"; CSS `mac-popover mac-popover--static`): Ultra Thick blur material,
/// radius 20, 20 px padding, the arrow on the edge that faces the control. For mockups and screenshots; a live
/// popover that opens next to a control is [MacPopover].
///
///     MacPopoverPanel(edge: MacPopoverEdge.bottom, width: 220, child: Text('Arrow on the top edge, centred'))
///     MacPopoverPanel(edge: MacPopoverEdge.top, arrow: MacPopoverArrow.start, child: …)   // kit "Bottom (Leading)"
///     MacPopoverPanel(edge: MacPopoverEdge.right, arrowOffset: 60, child: …)              // arrow 60 px from the top
class MacPopoverPanel extends StatelessWidget {
  const MacPopoverPanel({
    super.key,
    required this.child,
    this.edge = MacPopoverEdge.bottom,
    this.arrow = MacPopoverArrow.center,
    this.arrowOffset,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;

  /// Where the popover sits next to its control; the arrow is on the opposite edge.
  final MacPopoverEdge edge;
  final MacPopoverArrow arrow;

  /// Arrow tip position along its edge, from the top/left corner (overrides [arrow]'s position).
  final double? arrowOffset;
  final double? width;
  final double? height;

  /// Kit "Content Area": 20 px on every side.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => _PopoverBody(
        geometry: _Fixed(_ArrowGeometry(edge, arrow, arrowOffset)),
        padding: padding,
        width: width,
        height: height,
        child: child,
      );
}

class _Fixed<T> implements ValueListenable<T> {
  const _Fixed(this.value);
  @override
  final T value;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// A popover: a small panel of blur material with an arrow that points at [child] (the control that opened it).
/// It shows details or a few settings about that control; changes apply at once (no OK button).
///
///     bool _showStorage = false;
///
///     MacPopover(
///       isOpen: _showStorage,
///       onDismiss: () => setState(() => _showStorage = false),   // click outside or Escape
///       edge: MacPopoverEdge.bottom,                               // below the control (default)
///       content: const SizedBox(width: 220, child: Text('128 GB of 512 GB used')),
///       child: MacButton(label: 'Storage', onPressed: () => setState(() => _showStorage = !_showStorage)),
///     )
///
/// It sits [gap] px from the control (arrow tip), centred on it, kept 8 px inside the window; it flips to the
/// opposite side when there is no room, and the arrow merges into a corner when the control is near one.
/// Content gets 20 px padding: add none. Keyboard: focus moves into the popover; Escape closes it.
class MacPopover extends StatefulWidget {
  const MacPopover({
    super.key,
    required this.isOpen,
    required this.content,
    required this.child,
    this.onDismiss,
    this.edge = MacPopoverEdge.bottom,
    this.gap = 4,
    this.semanticLabel,
  });

  /// Controlled: show the popover while true.
  final bool isOpen;

  /// What the popover shows (it already has 20 px padding).
  final Widget content;

  /// The control the arrow points at.
  final Widget child;

  /// Called on a click outside the popover (and outside [child]) or Escape: set [isOpen] to false here.
  final VoidCallback? onDismiss;

  /// Preferred side: below the control (toolbar and top controls), above (near the window bottom), or beside it.
  final MacPopoverEdge edge;

  /// Distance from the control to the arrow tip (web `data-mac-offset`, default 4).
  final double gap;

  /// Accessible name when the popover holds controls ("Text Size").
  final String? semanticLabel;

  @override
  State<MacPopover> createState() => _MacPopoverState();
}

class _MacPopoverState extends State<MacPopover> {
  final OverlayPortalController _portal = OverlayPortalController();
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'MacPopover');
  late final ValueNotifier<_ArrowGeometry> _geometry = ValueNotifier(_ArrowGeometry(widget.edge, MacPopoverArrow.center));
  FocusNode? _restore;

  @override
  void initState() {
    super.initState();
    _portal.show(); // always attached; draws nothing while closed
    if (widget.isOpen) _opened();
  }

  @override
  void didUpdateWidget(MacPopover old) {
    super.didUpdateWidget(old);
    if (widget.isOpen && !old.isOpen) _opened();
    if (!widget.isOpen && old.isOpen) _closed();
  }

  void _opened() {
    _restore = FocusManager.instance.primaryFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isOpen) return;
      _portal.show(); // bring to the top of the overlay
      if (_scope.focusedChild == null) _scope.requestFocus();
    });
  }

  void _closed() {
    final restore = _restore;
    _restore = null;
    if (_scope.hasFocus && restore?.context != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => restore!.requestFocus());
    }
  }

  @override
  void dispose() {
    _scope.dispose();
    _geometry.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape && widget.onDismiss != null) {
      widget.onDismiss!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context, info) {
        if (!widget.isOpen) return const SizedBox.shrink();
        final anchor = MatrixUtils.transformRect(info.childPaintTransform, Offset.zero & info.childSize);
        return CustomSingleChildLayout(
          delegate: _PopoverLayout(anchor: anchor, edge: widget.edge, gap: widget.gap, geometry: _geometry),
          child: TapRegion(
            groupId: this,
            onTapOutside: (_) => widget.onDismiss?.call(),
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              namesRoute: widget.semanticLabel != null,
              label: widget.semanticLabel,
              child: FocusScope(
                node: _scope,
                onKeyEvent: _onKey,
                // Controls in a popover opened from a toolbar keep their normal (non-toolbar) look.
                child: _PopoverBody(
                  geometry: _geometry,
                  padding: const EdgeInsets.all(20),
                  child: MacToolbarScope(inToolbar: false, child: widget.content),
                ),
              ),
            ),
          ),
        );
      },
      child: TapRegion(groupId: this, child: widget.child),
    );
  }
}

/// popovers.js placePopover: next to the anchor on the preferred side (flipped when there is no room), centred
/// on it and kept 8 px inside the window; the arrow tip points at the anchor's centre.
class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout({required this.anchor, required this.edge, required this.gap, required this.geometry});
  final Rect anchor;
  final MacPopoverEdge edge;
  final double gap;
  final ValueNotifier<_ArrowGeometry> geometry;

  static const double _edge = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
        maxWidth: math.max(0.0, constraints.maxWidth - 2 * _edge),
        maxHeight: math.max(0.0, constraints.maxHeight - 2 * _edge),
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final w = child.width, h = child.height;
    final d = 10.5 + gap;
    final room = {
      MacPopoverEdge.bottom: size.height - anchor.bottom - d - _edge,
      MacPopoverEdge.top: anchor.top - d - _edge,
      MacPopoverEdge.right: size.width - anchor.right - d - _edge,
      MacPopoverEdge.left: anchor.left - d - _edge,
    };
    const opposite = {
      MacPopoverEdge.bottom: MacPopoverEdge.top,
      MacPopoverEdge.top: MacPopoverEdge.bottom,
      MacPopoverEdge.left: MacPopoverEdge.right,
      MacPopoverEdge.right: MacPopoverEdge.left,
    };
    var side = edge;
    final vertical = side == MacPopoverEdge.bottom || side == MacPopoverEdge.top;
    final need = vertical ? h : w;
    if (room[side]! < need && room[opposite[side]]! > room[side]!) side = opposite[side]!;
    double clamp(double v, double lo, double hi) => math.max(lo, math.min(hi, v));
    double x, y, tip, along;
    if (vertical) {
      y = side == MacPopoverEdge.bottom ? anchor.bottom + d : anchor.top - d - h;
      x = clamp(anchor.center.dx - w / 2, _edge, size.width - _edge - w);
      tip = anchor.center.dx - x;
      along = w;
    } else {
      x = side == MacPopoverEdge.right ? anchor.right + d : anchor.left - d - w;
      y = clamp(anchor.center.dy - h / 2, _edge, size.height - _edge - h);
      tip = anchor.center.dy - y;
      along = h;
    }
    var shape = MacPopoverArrow.center;
    tip = clamp(tip, _kCorner, along - _kCorner);
    if (tip < _kMerge) {
      if (tip < (_kCorner + _kMerge) / 2) {
        tip = _kCorner;
        shape = MacPopoverArrow.start;
      } else {
        tip = _kMerge;
      }
    } else if (tip > along - _kMerge) {
      if (tip > along - (_kCorner + _kMerge) / 2) {
        tip = along - _kCorner;
        shape = MacPopoverArrow.end;
      } else {
        tip = along - _kMerge;
      }
    }
    geometry.value = _ArrowGeometry(side, shape, tip);
    return Offset(x.roundToDouble(), y.roundToDouble());
  }

  @override
  bool shouldRelayout(_PopoverLayout old) => old.anchor != anchor || old.edge != edge || old.gap != gap;
}
