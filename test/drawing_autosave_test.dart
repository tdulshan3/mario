/// Verifies the autosave trigger for drawings: DrawingController.committed
/// bumps once per *committed* change (stroke finished / undo / redo / erase /
/// clear) and NOT during a live stroke or on tool (color/width/mode) changes.
/// The editor and the drawing block listen to this to autosave.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/drawing/drawing_canvas.dart';
import 'package:mario/features/drawing/stroke.dart';

void main() {
  test('committed bumps only on committed stroke-set changes', () {
    final c = DrawingController();
    var committed = 0;
    var notifies = 0;
    c.committed.addListener(() => committed++);
    c.addListener(() => notifies++);

    // A live stroke: many repaint notifications, but nothing committed yet.
    c.beginStroke(const Offset(0, 0), 0.5);
    c.appendPoint(const Offset(5, 5), 0.5);
    c.appendPoint(const Offset(9, 9), 0.5);
    expect(committed, 0, reason: 'no commit mid-stroke');
    expect(notifies, greaterThan(0), reason: 'repaints fire per point');

    c.endStroke();
    expect(committed, 1);

    c.undo();
    expect(committed, 2);

    c.redo();
    expect(committed, 3);

    // Tool changes must not look like a content change to autosave.
    c.setColor(const Color(0xFF00FF00));
    c.setWidth(8);
    c.setMode(StrokeMode.highlighter);
    expect(committed, 3, reason: 'tool changes do not commit strokes');

    // Back to pen, draw + clear.
    c.setMode(StrokeMode.pen);
    c.beginStroke(const Offset(1, 1), 0.5);
    c.endStroke();
    expect(committed, 4);

    c.clearAll();
    expect(committed, 5);

    c.dispose();
  });
}
