import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '_glyphs.dart';

/// A macOS image well (kit page "Image Wells"): a small bezeled box (30 × 30 in the kit) that shows ONE image,
/// scaled to fit, and lets people replace it. An empty well shows a photo glyph.
///
///     MacImageWell(
///       image: picture == null ? null : MemoryImage(picture!),   // any ImageProvider; null = empty
///       onPressed: pickPicture,                                  // click, Space or Return: open your file picker
///       onDelete: () => setState(() => picture = null),          // Delete / Backspace while focused
///       size: 64,
///       semanticLabel: 'Account Picture',
///     )
///     MacImageWell(image: AssetImage('assets/icon.png'), onPressed: null)   // disabled: drawn at 50 %
///
/// Flutter has no built-in file picker or file drop: open a picker (for example package file_selector) in
/// [onPressed], and while a file is dragged over the well (package desktop_drop) set [isDropTarget] to draw the
/// accent drop ring. Dropping or picking REPLACES the image. [onPressed] null = disabled.
class MacImageWell extends StatefulWidget {
  const MacImageWell({
    super.key,
    this.image,
    required this.onPressed,
    this.onDelete,
    this.size = 30,
    this.isDropTarget = false,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  });

  /// The image (shown whole, letterboxed, 3 px inside the bezel). Null = empty well.
  final ImageProvider? image;

  /// Click / Space / Return: let people choose an image. Null = disabled.
  final VoidCallback? onPressed;

  /// Delete or Backspace while the well has focus: remove the image.
  final VoidCallback? onDelete;

  /// Width and height (30 in the kit; 64–128 for an account picture).
  final double size;

  /// A file is being dragged over the well: accent ring.
  final bool isDropTarget;

  /// What the image is ("Account Picture").
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<MacImageWell> createState() => _MacImageWellState();
}

class _MacImageWellState extends State<MacImageWell> {
  bool _focusVisible = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final dark = theme.isDark;
    final ring = widget.isDropTarget || (_focusVisible && _enabled);
    final accent = theme.accentColor;

    Widget content = widget.image != null
        ? Image(image: widget.image!, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true)
        : Center(
            child: MacGlyph(MacGlyphKind.photo, size: (widget.size - 6) * 0.6, color: c.labelTertiary),
          );

    Widget well = CustomPaint(
      painter: _WellPainter(
        fill: c.fillQuinary, // black 2 % · white 2 %
        edge: dark ? const Color(0x1AFFFFFF) : const Color(0x0D000000), // 0.5 px outside
        highlight: dark ? const Color(0x0FFFFFFF) : const Color(0xFFFFFFFF), // 1 px inside, on top
        inner: dark ? const Color(0x40000000) : const Color(0x0D000000), // 1.5 px inside
        focus: ring ? accent.withValues(alpha: accent.a * 0.55) : null,
      ),
      child: SizedBox.square(
        dimension: widget.size,
        child: Padding(padding: const EdgeInsets.all(3), child: content),
      ),
    );
    if (!_enabled) well = Opacity(opacity: 0.5, child: well);

    return Semantics(
      image: true,
      button: _enabled,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        mouseCursor: SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focusVisible = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.delete): _DeleteIntent(),
          SingleActivator(LogicalKeyboardKey.backspace): _DeleteIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed?.call()),
          _DeleteIntent: CallbackAction<_DeleteIntent>(onInvoke: (_) => widget.onDelete?.call()),
        },
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onPressed, child: well),
      ),
    );
  }
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

/// The kit bezel: radius 3, 0.5 px edge outside, a 1.5 px dark line and a 1 px white highlight inside;
/// with [focus], the 3.5 px accent ring outside.
class _WellPainter extends CustomPainter {
  _WellPainter({required this.fill, required this.edge, required this.highlight, required this.inner, this.focus});
  final Color fill;
  final Color edge;
  final Color highlight;
  final Color inner;
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    Path shape(Rect r, double radius) => RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius)).getOuterPath(r);
    final body = shape(rect, 3);
    Path band(double w) => Path.combine(PathOperation.difference, body, shape(rect.deflate(w), (3 - w).clamp(0.0, 3.0)));
    canvas.drawPath(Path.combine(PathOperation.difference, shape(rect.inflate(0.5), 3.5), body), Paint()..color = edge);
    if (focus != null) {
      canvas.drawPath(Path.combine(PathOperation.difference, shape(rect.inflate(3.5), 6.5), body), Paint()..color = focus!);
    }
    canvas.drawPath(body, Paint()..color = fill);
    canvas.drawPath(band(1.5), Paint()..color = inner);
    canvas.drawPath(band(1), Paint()..color = highlight);
  }

  @override
  bool shouldRepaint(_WellPainter old) =>
      old.fill != fill || old.edge != edge || old.highlight != highlight || old.inner != inner || old.focus != focus;
}
