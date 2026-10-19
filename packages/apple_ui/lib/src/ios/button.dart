import 'package:flutter/widgets.dart';

import '../core/glass.dart';
import '../core/theme.dart';
import '../core/typography.dart';

/// Button styles of the kit page "Buttons".
enum IosButtonStyle {
  /// Grey fill, tint label (kit "Bordered"). The default.
  bordered,

  /// Tint fill, white label (kit "Bordered - Prominent"): THE primary action of a screen. One per screen.
  prominent,

  /// Tint label only (kit "Borderless").
  borderless,

  /// The classic Regular blur material (kit "Button - Liquid Glass", drawn as a material: blur + saturation under a
  /// translucent fill, no rims): ONLY for buttons floating above content, maps or media. The name stays for
  /// compatibility.
  glass,

  /// A solid accent fill, white label (kit "Glass Prominent", no blur).
  glassProminent,
}

/// Small 28 · Medium 34 (default) · Large 50 tall (kit Size).
enum IosButtonSize { small, medium, large }

/// An iOS button (kit page "Buttons").
///
///     IosButton(label: 'Continue', style: IosButtonStyle.prominent, size: IosButtonSize.large, onPressed: next)
///     IosButton(label: 'Play', icon: AppleIcons.play, onPressed: play)
///     IosButton(icon: AppleIcons.plus, semanticLabel: 'Add', style: IosButtonStyle.glass, onPressed: add)   // icon only
///     IosButton(label: 'Delete', destructive: true, onPressed: delete)
/// [onPressed] null = disabled.
class IosButton extends StatefulWidget {
  const IosButton({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
    this.style = IosButtonStyle.bordered,
    this.size = IosButtonSize.medium,
    this.destructive = false,
    this.semanticLabel,
  }) : assert(label != null || icon != null, 'IosButton needs a label, an icon, or both');

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final IosButtonStyle style;
  final IosButtonSize size;

  /// Red: the button deletes or removes something.
  final bool destructive;

  /// Accessible name. Required for an icon-only button.
  final String? semanticLabel;

  @override
  State<IosButton> createState() => _IosButtonState();
}

class _IosButtonState extends State<IosButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;
  bool get _glass => widget.style == IosButtonStyle.glass || widget.style == IosButtonStyle.glassProminent;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final iconOnly = widget.label == null;
    final tint = widget.destructive ? c.red : theme.accentColor;

    // Kit metrics. Content buttons: Small 28 (pad 10, gap 3, 15 Regular), Medium 34 (pad 14, 15 Regular),
    // Large 50 (pad 20, 17 Regular). Glass: Small 28 (pad 10, 15 Medium), Medium 34 (pad 12, 17 Medium),
    // Large 50 (pad 20, 17 Medium). Icon only: a circle as wide as tall; glass symbol buttons are 50 wide.
    final height = switch (widget.size) {
      IosButtonSize.small => 28.0,
      IosButtonSize.medium => 34.0,
      IosButtonSize.large => 50.0,
    };
    final padX = switch (widget.size) {
      IosButtonSize.small => 10.0,
      IosButtonSize.medium => _glass ? 12.0 : 14.0,
      IosButtonSize.large => 20.0,
    };
    final fontSize = _glass ? (widget.size == IosButtonSize.small ? 15.0 : 17.0) : (widget.size == IosButtonSize.large ? 17.0 : 15.0);
    final lineHeight = fontSize == 17 ? 22.0 : 20.0;
    final tracking = fontSize == 17 ? -0.43 : -0.23;
    final side = iconOnly && _glass ? 50.0 : height;
    final iconSize = iconOnly && _glass ? 19.0 * 1.2 : fontSize * 1.2; // icons drawn 1.2x their point size, like SF Symbols

    // Colours (kit Light/Dark; disabled = tertiary label, grey fill).
    Color fill;
    Color label;
    switch (widget.style) {
      case IosButtonStyle.prominent:
        fill = _enabled ? tint : c.fillTertiary;
        label = _enabled ? const Color(0xFFFFFFFF) : c.labelTertiary;
      case IosButtonStyle.bordered:
        fill = !_enabled ? c.fillTertiary : (widget.destructive ? c.buttonDestructiveBg : c.fillTertiary);
        label = _enabled ? tint : c.labelTertiary;
      case IosButtonStyle.borderless:
        fill = const Color(0x00000000);
        label = _enabled ? tint : c.labelTertiary;
      case IosButtonStyle.glass:
        fill = const Color(0x00000000);
        label = !_enabled ? c.labelControlTertiary : (widget.destructive ? c.red : c.labelControlPrimary);
      case IosButtonStyle.glassProminent:
        fill = const Color(0x00000000);
        label = _enabled ? const Color(0xFFFFFFFF) : c.labelControlTertiary;
    }

    final text = appleFont(size: fontSize).copyWith(
      fontSize: fontSize,
      height: lineHeight / fontSize,
      letterSpacing: tracking,
      fontWeight: _glass ? FontWeight.w500 : FontWeight.w400,
      color: label,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: TextDecoration.none,
    );

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null)
          SizedBox(
            width: iconOnly && _glass ? 19 : fontSize, // the icon takes 1em of layout space and is drawn 1.2em
            height: iconOnly && _glass ? 19 : fontSize,
            child: OverflowBox(
              maxWidth: iconSize,
              maxHeight: iconSize,
              child: Icon(widget.icon, size: iconSize, color: label, weight: iconOnly && _glass ? 600 : null),
            ),
          ),
        if (widget.icon != null && !iconOnly) SizedBox(width: widget.size == IosButtonSize.small ? 3 : 4),
        if (!iconOnly) Text(widget.label!, style: text, maxLines: 1, softWrap: false),
      ],
    );
    content = SizedBox(
      height: side,
      width: iconOnly ? side : null,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : padX),
        child: Center(widthFactor: 1, child: content),
      ),
    );

    // Pressed tint: darker (lighter in Dark Mode), like CSS brightness(0.88) / brightness(1.2).
    final pressedTint = theme.isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000);
    Widget button;
    if (_glass) {
      final prominent = widget.style == IosButtonStyle.glassProminent && _enabled;
      button = AppleGlass(
        style: prominent ? AppleGlassStyle.prominent : AppleGlassStyle.regular,
        tint: prominent ? tint : null,
        // The pressed tint goes INSIDE the material: a ColorFiltered layer around it would cut the backdrop blur.
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(color: _pressed && _enabled ? pressedTint : const Color(0x00000000)),
          child: content,
        ),
      );
    } else {
      final radius = widget.style == IosButtonStyle.borderless && widget.size == IosButtonSize.large ? 12.0 : height / 2;
      button = DecoratedBox(
        decoration: ShapeDecoration(color: fill, shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius))),
        child: content,
      );
    }

    // Pressed: filled and material styles darken (lighten in Dark Mode; material ones above), borderless fades.
    if (_pressed && _enabled && !_glass) {
      if (widget.style == IosButtonStyle.borderless) {
        button = Opacity(opacity: 0.35, child: button);
      } else {
        button = ColorFiltered(colorFilter: ColorFilter.mode(pressedTint, BlendMode.srcATop), child: button);
      }
    }

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel ?? widget.label,
      // excludeSemantics drops the GestureDetector's tap action, so screen readers need it here.
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: button,
        ),
      ),
    );
  }
}
