/// DrawingCanvas — interactive freehand surface backed by [Stroke]s.
library;

import 'package:flutter/material.dart';

import '../../ui/colors.dart';
import 'stroke.dart';
import 'stroke_painter.dart';

class DrawingController extends ChangeNotifier {
  DrawingController({List<Stroke>? initial})
      : _strokes = List<Stroke>.from(initial ?? const <Stroke>[]);

  List<Stroke> _strokes;
  final List<Stroke> _redo = [];
  StrokeMode _mode = StrokeMode.pen;
  Color _color = const Color(0xFF1A1A1A);
  double _width = 4;
  Stroke? _live;

  /// Bumps whenever the *committed* stroke set changes — a stroke finished,
  /// undo/redo, erase, or clear — as opposed to the per-point live updates that
  /// drive [notifyListeners]. Autosave listeners watch this so they fire once
  /// per change instead of once per pointer move.
  final ValueNotifier<int> committed = ValueNotifier<int>(0);

  @override
  void dispose() {
    committed.dispose();
    super.dispose();
  }

  List<Stroke> get strokes =>
      List<Stroke>.unmodifiable(_live == null ? _strokes : [..._strokes, _live!]);

  StrokeMode get mode => _mode;
  Color get color => _color;
  double get width => _width;
  bool get canUndo => _strokes.isNotEmpty || _live != null;
  bool get canRedo => _redo.isNotEmpty;

  void setMode(StrokeMode m) {
    _mode = m;
    notifyListeners();
  }

  void setColor(Color c) {
    _color = c;
    notifyListeners();
  }

  void setWidth(double w) {
    _width = w;
    notifyListeners();
  }

  void beginStroke(Offset p, double pressure) {
    if (_mode == StrokeMode.eraser) {
      _eraseAt(p);
      return;
    }
    _live = Stroke(
      points: [StrokePoint(p.dx, p.dy, pressure)],
      colorValue: _color.toARGB32(),
      width: _mode == StrokeMode.highlighter ? _width * 3 : _width,
      mode: _mode,
    );
    notifyListeners();
  }

  void appendPoint(Offset p, double pressure) {
    if (_mode == StrokeMode.eraser) {
      _eraseAt(p);
      return;
    }
    final live = _live;
    if (live == null) return;
    _live = Stroke(
      points: [...live.points, StrokePoint(p.dx, p.dy, pressure)],
      colorValue: live.colorValue,
      width: live.width,
      mode: live.mode,
    );
    notifyListeners();
  }

  void endStroke() {
    if (_live == null) return;
    _strokes = [..._strokes, _live!];
    _live = null;
    _redo.clear();
    if (_strokes.length > 200) {
      _strokes = _strokes.sublist(_strokes.length - 200);
    }
    notifyListeners();
    committed.value++;
  }

  void _eraseAt(Offset p) {
    final hit = _hitTestStrokeIndex(p);
    if (hit == -1) return;
    final removed = _strokes[hit];
    _strokes = [..._strokes.take(hit), ..._strokes.skip(hit + 1)];
    _redo.add(removed);
    notifyListeners();
    committed.value++;
  }

  int _hitTestStrokeIndex(Offset p) {
    for (var i = _strokes.length - 1; i >= 0; i--) {
      final s = _strokes[i];
      final tolerance = (s.width * 1.5).clamp(6.0, 30.0);
      for (final pt in s.points) {
        final dx = pt.x - p.dx;
        final dy = pt.y - p.dy;
        if (dx * dx + dy * dy <= tolerance * tolerance) return i;
      }
    }
    return -1;
  }

  void undo() {
    if (_strokes.isEmpty) return;
    final last = _strokes.last;
    _strokes = _strokes.sublist(0, _strokes.length - 1);
    _redo.add(last);
    notifyListeners();
    committed.value++;
  }

  void redo() {
    if (_redo.isEmpty) return;
    final s = _redo.removeLast();
    _strokes = [..._strokes, s];
    notifyListeners();
    committed.value++;
  }

  void clearAll() {
    if (_strokes.isEmpty) return;
    _strokes = const [];
    _redo.clear();
    notifyListeners();
    committed.value++;
  }

  List<Stroke> snapshot() => List<Stroke>.unmodifiable(_strokes);
}

class DrawingCanvas extends StatelessWidget {
  const DrawingCanvas({
    super.key,
    required this.controller,
    required this.size,
    this.boundaryKey,
  });

  final DrawingController controller;
  final Size size;
  final GlobalKey? boundaryKey;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF101010) : Colors.white;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;

    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: RepaintBoundary(
        key: boundaryKey,
        child: Listener(
          onPointerDown: (e) => controller.beginStroke(e.localPosition, e.pressure),
          onPointerMove: (e) => controller.appendPoint(e.localPosition, e.pressure),
          onPointerUp: (_) => controller.endStroke(),
          onPointerCancel: (_) => controller.endStroke(),
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, __) => CustomPaint(
              painter: StrokePainter(
                strokes: controller.strokes,
                background: bg,
              ),
              size: size,
            ),
          ),
        ),
      ),
    );
  }
}
