/// CanvasDrawingLayer — full-card freehand overlay above the AppFlowy editor.
///
/// Strokes are always painted so the user sees them regardless of mode; the
/// pointer-capturing layer only mounts when [active] is true, so editing,
/// text selection, and clicks pass through cleanly when the draw tool is off.
library;

import 'package:flutter/material.dart';

import '../drawing/drawing_canvas.dart';
import '../drawing/stroke_painter.dart';

class CanvasDrawingLayer extends StatelessWidget {
  const CanvasDrawingLayer({
    super.key,
    required this.controller,
    required this.active,
  });

  final DrawingController controller;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: StrokePainter(strokes: controller.strokes),
              size: Size.infinite,
            ),
          ),
          if (active)
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) =>
                  controller.beginStroke(e.localPosition, e.pressure),
              onPointerMove: (e) =>
                  controller.appendPoint(e.localPosition, e.pressure),
              onPointerUp: (_) => controller.endStroke(),
              onPointerCancel: (_) => controller.endStroke(),
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}
