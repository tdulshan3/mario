// The small vector glyphs of macos.css (icons.css masks, 16 × 16 view box) for the M3 controls:
// chevrons, magnifying glass, clear button, photo, info and more. Private to apple_ui (not exported).
import 'package:flutter/widgets.dart';

enum MacGlyphKind {
  chevronDown,
  chevronUp,
  chevronRight,
  chevronDownBold,
  chevronRightBold,
  chevronUpDownBold,
  magnifyingglass,
  xmarkCircleFill,
  photo,
  infoCircle,
  ellipsis,
}

/// Draws one glyph scaled to a [size] × [size] box (the CSS mask size), centred in its layout box.
class MacGlyph extends StatelessWidget {
  const MacGlyph(this.kind, {super.key, required this.size, required this.color});
  final MacGlyphKind kind;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _GlyphPainter(kind, color));
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color);
  final MacGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 16;
    canvas.save();
    canvas.translate((size.width - 16 * k) / 2, (size.height - 16 * k) / 2);
    canvas.scale(k);
    Paint stroke(double w) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    Path poly(List<double> p) {
      final path = Path()..moveTo(p[0], p[1]);
      for (var i = 2; i < p.length; i += 2) {
        path.lineTo(p[i], p[i + 1]);
      }
      return path;
    }

    switch (kind) {
      case MacGlyphKind.chevronDown:
        canvas.drawPath(poly([4, 6.25, 8, 10, 12, 6.25]), stroke(1.35));
      case MacGlyphKind.chevronUp:
        canvas.drawPath(poly([4, 9.75, 8, 6, 12, 9.75]), stroke(1.35));
      case MacGlyphKind.chevronRight:
        canvas.drawPath(poly([6.25, 4, 10, 8, 6.25, 12]), stroke(1.35));
      case MacGlyphKind.chevronDownBold:
        canvas.drawPath(poly([3, 5.75, 8, 10.25, 13, 5.75]), stroke(2));
      case MacGlyphKind.chevronRightBold:
        canvas.drawPath(poly([6.2, 4.8, 9.8, 8, 6.2, 11.2]), stroke(1.75));
      case MacGlyphKind.chevronUpDownBold:
        canvas.drawPath(poly([4.9, 6.1, 8, 3, 11.1, 6.1]), stroke(1.75));
        canvas.drawPath(poly([4.9, 9.9, 8, 13, 11.1, 9.9]), stroke(1.75));
      case MacGlyphKind.magnifyingglass:
        canvas.drawCircle(const Offset(6.75, 6.75), 4.25, stroke(1.35));
        canvas.drawLine(const Offset(9.9, 9.9), const Offset(13.5, 13.5), stroke(1.35));
      case MacGlyphKind.xmarkCircleFill:
        canvas.saveLayer(const Rect.fromLTWH(0, 0, 16, 16), Paint());
        canvas.drawCircle(const Offset(8, 8), 7, fill);
        final cut = stroke(1.5)..blendMode = BlendMode.clear;
        canvas.drawLine(const Offset(5.9, 5.9), const Offset(10.1, 10.1), cut);
        canvas.drawLine(const Offset(10.1, 5.9), const Offset(5.9, 10.1), cut);
        canvas.restore();
      case MacGlyphKind.photo:
        canvas.drawRRect(RRect.fromLTRBR(1.75, 2.75, 14.25, 13.25, const Radius.circular(1)), stroke(1.35));
        canvas.drawPath(poly([1.75, 11, 5.25, 7.5, 8.25, 10.5, 10.25, 8.5, 14.25, 12.5]), stroke(1.35));
        canvas.drawCircle(const Offset(10.75, 5.75), 1.1, stroke(1.35));
      case MacGlyphKind.infoCircle:
        canvas.drawCircle(const Offset(8, 8), 6.3, stroke(1.35));
        canvas.drawLine(const Offset(8, 7.25), const Offset(8, 11.25), stroke(1.35));
        canvas.drawCircle(const Offset(8, 4.9), 0.85, fill);
      case MacGlyphKind.ellipsis:
        for (final x in const [3.5, 8.0, 12.5]) {
          canvas.drawCircle(Offset(x, 8), 1.2, fill);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.kind != kind || old.color != color;
}

/// A glyph of [glyph] × [glyph] drawn centred in a [width] × [height] layout box (CSS: mask centred in the element).
Widget macGlyphBox(MacGlyphKind kind, {required double width, required double height, required double glyph, required Color color}) {
  return SizedBox(
    width: width,
    height: height,
    child: OverflowBox(
      maxWidth: glyph,
      maxHeight: glyph,
      minWidth: glyph,
      minHeight: glyph,
      child: MacGlyph(kind, size: glyph, color: color),
    ),
  );
}
