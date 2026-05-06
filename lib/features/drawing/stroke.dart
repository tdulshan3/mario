/// Stroke + StrokePoint — drawing data model with JSON round-trip for AppFlowy embeds.
library;

import 'dart:ui' show Color;

enum StrokeMode { pen, highlighter, eraser }

class StrokePoint {
  final double x;
  final double y;
  final double pressure;

  const StrokePoint(this.x, this.y, [this.pressure = 0.5]);

  Map<String, dynamic> toMap() => {'x': x, 'y': y, 'p': pressure};

  factory StrokePoint.fromMap(Map<String, dynamic> m) => StrokePoint(
        (m['x'] as num).toDouble(),
        (m['y'] as num).toDouble(),
        (m['p'] as num?)?.toDouble() ?? 0.5,
      );
}

class Stroke {
  final List<StrokePoint> points;
  final int colorValue;
  final double width;
  final StrokeMode mode;

  const Stroke({
    required this.points,
    required this.colorValue,
    required this.width,
    required this.mode,
  });

  Color get color => Color(colorValue);

  /// Highlighter strokes draw at fixed alpha; pen strokes opaque.
  double get effectiveOpacity =>
      mode == StrokeMode.highlighter ? 0.35 : 1.0;

  Map<String, dynamic> toMap() => {
        'points': points.map((p) => p.toMap()).toList(),
        'color': colorValue,
        'width': width,
        'mode': mode.name,
      };

  factory Stroke.fromMap(Map<String, dynamic> m) => Stroke(
        points: (m['points'] as List)
            .map((e) => StrokePoint.fromMap(Map<String, dynamic>.from(e)))
            .toList(growable: false),
        colorValue: m['color'] as int? ?? 0xFF000000,
        width: (m['width'] as num?)?.toDouble() ?? 4.0,
        mode: StrokeMode.values.firstWhere(
          (e) => e.name == (m['mode'] as String? ?? 'pen'),
          orElse: () => StrokeMode.pen,
        ),
      );
}

List<Stroke> strokesFromJson(List? raw) {
  if (raw == null) return const [];
  return raw
      .map((e) => Stroke.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList(growable: true);
}

List<Map<String, dynamic>> strokesToJson(List<Stroke> strokes) =>
    strokes.map((s) => s.toMap()).toList(growable: false);
