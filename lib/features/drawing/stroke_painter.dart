/// StrokePainter — renders a list of [Stroke]s using perfect_freehand outlines.
library;

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import 'stroke.dart';

class StrokePainter extends CustomPainter {
  StrokePainter({required this.strokes, this.background});

  final List<Stroke> strokes;
  final Color? background;

  @override
  void paint(Canvas canvas, Size size) {
    if (background != null) {
      final bgPaint = Paint()..color = background!;
      canvas.drawRect(Offset.zero & size, bgPaint);
    }
    for (final s in strokes) {
      final outline = getStroke(
        s.points
            .map((p) => PointVector(p.x, p.y, p.pressure))
            .toList(growable: false),
        options: StrokeOptions(
          size: s.width,
          thinning: s.mode == StrokeMode.highlighter ? 0.0 : 0.5,
          smoothing: 0.5,
          streamline: 0.5,
          simulatePressure: s.mode != StrokeMode.highlighter,
        ),
      );
      if (outline.isEmpty) continue;
      final path = Path()..moveTo(outline.first.dx, outline.first.dy);
      for (var i = 1; i < outline.length; i++) {
        path.lineTo(outline[i].dx, outline[i].dy);
      }
      path.close();
      final paint = Paint()
        ..color = s.color.withValues(alpha: s.effectiveOpacity)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant StrokePainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
