// Shared helpers for the iOS controls (toggle, checkbox, slider, stepper, page control). Not exported.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lets a small control (a 28 pt switch, a 22 pt circle) take taps in a [minSize] area around it without changing
/// its layout size, like the transparent 44 pt hit areas of the web version. The parent must be at least that big
/// for the extra area to work (a list row is).
class IosMinTapArea extends SingleChildRenderObjectWidget {
  const IosMinTapArea({super.key, this.minSize = const Size(44, 44), super.child});
  final Size minSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderIosMinTapArea(minSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderIosMinTapArea).minSize = minSize;
}

class _RenderIosMinTapArea extends RenderProxyBox {
  _RenderIosMinTapArea(this._minSize);
  Size _minSize;
  set minSize(Size v) => _minSize = v;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final dx = ((_minSize.width - size.width) / 2).clamp(0.0, double.infinity);
    final dy = ((_minSize.height - size.height) / 2).clamp(0.0, double.infinity);
    final area = Rect.fromLTRB(-dx, -dy, size.width + dx, size.height + dy);
    if (!area.contains(position)) return false;
    // Taps in the extra area count as taps on the control's nearest point.
    final inside = Offset(position.dx.clamp(0.0, size.width), position.dy.clamp(0.0, size.height));
    if (hitTestChildren(result, position: inside)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
