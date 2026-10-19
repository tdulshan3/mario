// Shared helpers of the window chrome widgets (windows, toolbars, sidebars, scroll views, layout).
// Not exported: the names are public only so the other files of lib/src/macos can use them.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/theme.dart';
import '../core/typography.dart';

/// A text style with exact CSS metrics (size / line height / weight), in [color].
TextStyle macChromeText(double size, double lineHeight, Color color, {FontWeight weight = FontWeight.w400, bool tabular = false}) =>
    appleFont(size: size).copyWith(
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      letterSpacing: 0,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: TextDecoration.none,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

/// Keyboard focus ring colour (base.css `--mac-focus-color`): the accent at 55%.
Color macFocusColor(BuildContext context) => AppleTheme.of(context).accentColor.withValues(alpha: 0.55);

/// The vibrant accent used for sidebar symbols (`--mac-accent-vibrant`): the app accent, else vibrant blue.
Color macAccentVibrant(BuildContext context) {
  final theme = AppleTheme.of(context);
  return theme.accent ?? theme.mac.accentVibrantBlue;
}

/// Draws the 3.5 px keyboard focus ring (CSS `outline: 3.5px solid var(--mac-focus-color)`) around [child] when [show].
/// [offset] = CSS outline-offset (negative = inside). [radius] null = capsule.
class MacFocusRing extends StatelessWidget {
  const MacFocusRing({super.key, required this.show, required this.child, this.radius, this.offset = 0});
  final bool show;
  final Widget child;
  final double? radius;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return CustomPaint(foregroundPainter: _RingPainter(macFocusColor(context), radius, offset), child: child);
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.radius, this.offset);
  final Color color;
  final double? radius;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 3.5;
    final rect = (Offset.zero & size).inflate(offset + w / 2);
    final base = radius ?? size.shortestSide / 2;
    final r = (base + offset + w / 2).clamp(0.0, rect.shortestSide / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color || old.radius != radius || old.offset != offset;
}

/// Interaction state handed to [MacPressable.builder].
@immutable
class MacPressState {
  const MacPressState({required this.enabled, required this.hovered, required this.pressed, required this.focused});
  final bool enabled;
  final bool hovered;
  final bool pressed;

  /// Keyboard focus (only while the keyboard is used: the ring is not shown for mouse clicks).
  final bool focused;
}

/// A focusable, clickable area with macOS behaviour: arrow pointer, Return/Space activate, keyboard-only focus ring,
/// hover and pressed state for the builder. [onPressed] null = disabled (not focusable).
class MacPressable extends StatefulWidget {
  const MacPressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.semanticLabel,
    this.tooltip,
    this.toggled,
    this.selected,
    this.focusNode,
    this.autofocus = false,
    this.keys = const {},
    this.onPressedChanged,
    this.onHoverChanged,
    this.onFocusChanged,
    this.isButton = true,
    this.isLink = false,
  });

  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, MacPressState state) builder;
  final String? semanticLabel;
  final String? tooltip;
  final bool? toggled;
  final bool? selected;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Extra keys handled while focused (for example Left/Right on a sidebar folder).
  final Map<ShortcutActivator, VoidCallback> keys;
  final ValueChanged<bool>? onPressedChanged;
  final ValueChanged<bool>? onHoverChanged;
  final ValueChanged<bool>? onFocusChanged;
  final bool isButton;
  final bool isLink;

  @override
  State<MacPressable> createState() => _MacPressableState();
}

class _MacPressableState extends State<MacPressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
    widget.onPressedChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final state = MacPressState(
      enabled: _enabled,
      hovered: _hovered && _enabled,
      pressed: _pressed && _enabled,
      focused: _focused && _enabled,
    );
    final shortcuts = <ShortcutActivator, Intent>{for (final k in widget.keys.keys) k: _KeyIntent(k)};
    return Semantics(
      button: widget.isButton && !widget.isLink,
      link: widget.isLink,
      enabled: _enabled,
      toggled: widget.toggled,
      selected: widget.selected,
      label: widget.semanticLabel,
      tooltip: widget.tooltip,
      onTap: widget.onPressed,
      excludeSemantics: widget.semanticLabel != null,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        mouseCursor: SystemMouseCursors.basic,
        shortcuts: shortcuts,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
          _KeyIntent: CallbackAction<_KeyIntent>(
            onInvoke: (i) {
              widget.keys[i.key]?.call();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (v) {
          if (_hovered != v) {
            setState(() => _hovered = v);
            widget.onHoverChanged?.call(v);
          }
        },
        onShowFocusHighlight: (v) {
          if (_focused != v) {
            setState(() => _focused = v);
            widget.onFocusChanged?.call(v);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => _setPressed(true) : null,
          onTapUp: _enabled ? (_) => _setPressed(false) : null,
          onTapCancel: _enabled ? () => _setPressed(false) : null,
          onTap: widget.onPressed,
          child: widget.builder(context, state),
        ),
      ),
    );
  }
}

class _KeyIntent extends Intent {
  const _KeyIntent(this.key);
  final ShortcutActivator key;
}

/// Paints a stroked path given in a 16 × 16 grid (the skill's web icon grid, stroke 1.35, round caps) scaled to [size].
class MacGridGlyphPainter extends CustomPainter {
  MacGridGlyphPainter(this.path, this.color, {this.strokeWidth = 1.35});
  final Path path;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 16;
    canvas.save();
    canvas.translate((size.width - 16 * s) / 2, (size.height - 16 * s) / 2);
    canvas.scale(s);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(MacGridGlyphPainter old) => old.path != path || old.color != color || old.strokeWidth != strokeWidth;
}

/// Chevron pointing down (icons.css `chevron-down`, 16 grid). Rotate −90° for "collapsed".
final Path macChevronDownPath = Path()
  ..moveTo(4, 6.25)
  ..lineTo(8, 10)
  ..lineTo(12, 6.25);

/// A small disclosure chevron: down when [expanded], right when collapsed (CSS: mask 11 px, rotate(-90deg)).
class MacChevron extends StatelessWidget {
  const MacChevron({super.key, required this.expanded, required this.color, this.size = 11, this.strokeWidth = 1.6});
  final bool expanded;
  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: expanded ? 0 : -1.5707963267948966,
      child: CustomPaint(
        size: Size.square(size),
        painter: MacGridGlyphPainter(macChevronDownPath, color, strokeWidth: strokeWidth),
      ),
    );
  }
}

/// True when the window around [context] is not focused (`mac-inactive`).
bool macInactive(BuildContext context) => MacWindowState.isInactive(context);

/// Arrow keys as activators (used by sidebars).
const macArrowLeft = SingleActivator(LogicalKeyboardKey.arrowLeft);
const macArrowRight = SingleActivator(LogicalKeyboardKey.arrowRight);
