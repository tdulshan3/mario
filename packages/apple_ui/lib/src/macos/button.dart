import 'package:flutter/widgets.dart';

import '../core/macos_tokens.dart';
import '_control_support.dart';

/// Push button styles of the kit page "Buttons" (the same names as the web/React variants).
enum MacButtonStyle {
  /// Grey fill, label-primary text (kit "Bordered"). The default for any normal action.
  bordered,

  /// Solid accent, white text (kit "Bordered - Prominent"): THE default action of a window, sheet or alert
  /// (the one Return triggers). At most one per window.
  prominent,

  /// Accent text on a light accent wash (kit "Bordered - Tinted"): stands out a little, not the default.
  tinted,

  /// Red text on a light red wash (kit "Bordered - Destructive"): deletes or can't be undone, not the default.
  destructive,

  /// Solid red, white text (kit "Bordered - Prominent - Destructive"): a dangerous action that IS the default.
  prominentDestructive,

  /// Accent text only, no background (kit "Borderless"): link-like, low emphasis ("Learn More…").
  borderless,
}

/// A macOS push button, toggle button or round arrow button (kit page "Buttons").
///
///     MacButton(label: 'Add Account', onPressed: add)                                  // bordered (default)
///     MacButton(label: 'Save', style: MacButtonStyle.prominent, onPressed: save)        // the default action
///     MacButton(label: 'Share', icon: AppleIcons.squareAndArrowUp, onPressed: share)    // icon + text
///     MacButton(icon: AppleIcons.trash, semanticLabel: 'Delete', onPressed: delete)     // icon only (square)
///     MacButton(label: 'Favorite', icon: AppleIcons.heart, isOn: fav, onPressed: () => setState(() => fav = !fav))
///     MacButton.arrow(semanticLabel: 'Sort Options', onPressed: openMenu)               // round ⌃⌄ button
///
/// [onPressed] null = disabled. The size follows [MacControlSizeScope] (mini 16 · small 20 · medium 24 ·
/// large 28 · XL 36 tall) unless [size] is set. No hover effect: macOS buttons only change while pressed.
/// Space or Return activates the focused button; the window turns coloured styles grey when it is inactive
/// ([MacWindowState]).
class MacButton extends StatelessWidget {
  const MacButton({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
    this.style = MacButtonStyle.bordered,
    this.isOn,
    this.size,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  })  : _arrow = false,
        assert(label != null || icon != null, 'MacButton needs a label, an icon, or both');

  /// The round arrow button (kit "Arrow Buttons"): a circle with ⌃⌄ that opens a menu of options.
  /// [semanticLabel] names it for VoiceOver ("Sort Options").
  const MacButton.arrow({
    super.key,
    required this.onPressed,
    required String this.semanticLabel,
    this.size,
    this.focusNode,
    this.autofocus = false,
  })  : label = null,
        icon = null,
        style = MacButtonStyle.bordered,
        isOn = null,
        _arrow = true;

  /// Title-case verb: "Save", "Move to Trash". Add "…" only when it opens a dialog that asks for more.
  final String? label;

  /// Leading symbol (`AppleIcons.*`), drawn 5 px before the label.
  final IconData? icon;
  final VoidCallback? onPressed;
  final MacButtonStyle style;

  /// Makes it a toggle button (kit "Buttons - Toggle"): true = on (accent text on an accent wash), false = off.
  /// Null (default) = a push button. Flip the value in [onPressed].
  final bool? isOn;

  /// Overrides the [MacControlSizeScope] size.
  final MacControlSize? size;

  /// Accessible name. Required for an icon-only button.
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool _arrow;

  @override
  Widget build(BuildContext context) {
    final look = ControlLook.of(context, size);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      toggled: isOn,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: ControlPressable(
        onPressed: onPressed,
        focusNode: focusNode,
        autofocus: autofocus,
        builder: (context, state) => _arrow ? _buildArrow(look, state) : _buildButton(look, state),
      ),
    );
  }

  Widget _buildArrow(ControlLook look, ControlState state) {
    final s = look.s;
    final enabled = onPressed != null;
    final fill = !enabled
        ? look.c.fillTertiary
        : state.pressed
            ? look.ld(controlBlack(0.19), controlWhite(0.19))
            : look.c.fillPrimary;
    final glyph = enabled ? look.c.labelPrimary : look.c.labelTertiary;
    // The kit draws the same ⌃⌄ as a pop-up button without a label (8 × 11.5 at medium).
    final em = s.popupFontSizeChevron * 16 / 11;
    return ControlBox(
      color: fill,
      radius: s.globalHeight / 2,
      focusRing: state.focused ? look.focusColor : null,
      child: SizedBox(
        width: s.globalHeight,
        height: s.globalHeight,
        child: Center(
          child: ControlGlyph(
            lines: ControlGlyph.popupIndicator,
            viewBox: const Size(16, 16),
            strokeWidth: 1.75,
            color: glyph,
            width: em,
            height: em,
          ),
        ),
      ),
    );
  }

  Widget _buildButton(ControlLook look, ControlState state) {
    final s = look.s;
    final enabled = onPressed != null;
    final colors = _ButtonColors.of(look, style, isOn);
    final fill = !enabled ? colors.fillDisabled : (state.pressed ? colors.fillPressed : colors.fill);
    final text = !enabled ? colors.labelDisabled : (state.pressed ? colors.labelPressed : colors.label);
    final iconOnly = label == null;
    final borderless = style == MacButtonStyle.borderless;
    final fontSize = s.globalFontSize;

    final children = <Widget>[
      if (icon != null)
        SizedBox(
          width: fontSize + 1,
          height: fontSize + 1,
          child: Center(child: Icon(icon, size: fontSize + 1, color: text)),
        ),
      if (icon != null && !iconOnly) const SizedBox(width: 5),
      if (!iconOnly)
        Text(label!, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: look.text(fontSize, text)),
    ];
    final padX = borderless ? (iconOnly ? 2.0 : 4.0) : (iconOnly ? 0.0 : s.buttonPaddingHorizontal);
    Widget content = Padding(
      padding: EdgeInsets.symmetric(horizontal: padX),
      child: Center(
        widthFactor: 1,
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: children),
      ),
    );
    final minWidth = borderless ? 0.0 : (iconOnly ? s.globalHeight : s.globalHeight * 1.5);
    content = ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: s.globalHeight, maxHeight: s.globalHeight),
      child: iconOnly && !borderless ? SizedBox(width: s.globalHeight, child: content) : content,
    );
    return ControlBox(
      color: fill,
      radius: s.buttonRadius,
      focusRing: state.focused ? look.focusColor : null,
      child: content,
    );
  }
}

/// The six colours of one button style (buttons.css custom properties).
class _ButtonColors {
  const _ButtonColors(this.fill, this.fillPressed, this.fillDisabled, this.label, this.labelPressed, this.labelDisabled);
  final Color fill;
  final Color fillPressed;
  final Color fillDisabled;
  final Color label;
  final Color labelPressed;
  final Color labelDisabled;

  static _ButtonColors of(ControlLook look, MacButtonStyle style, bool? isOn) {
    final c = look.c;
    final accent = look.accent;
    final red = c.accentRed;
    final bordered = _ButtonColors(look.borderedFill, look.borderedFillPressed, look.borderedFillDisabled, c.labelPrimary,
        c.labelPrimary, c.labelTertiary);

    if (isOn != null) {
      // Toggle (kit "Buttons - Toggle"): off looks bordered, on gets a vibrant-accent wash; pressed is the same in both.
      final vibrant = look.vibrantAccent;
      final pressedFill = controlFade(vibrant, 0.16);
      if (!isOn) {
        return _ButtonColors(bordered.fill, pressedFill, bordered.fillDisabled, bordered.label, accent, bordered.labelDisabled);
      }
      return _ButtonColors(
        controlFade(vibrant, look.dark ? 0.09 : 0.06),
        pressedFill,
        controlFade(vibrant, look.dark ? 0.03 : 0.02),
        accent,
        accent,
        controlFade(accent, look.dark ? 0.40 : 0.30),
      );
    }

    // Window not focused: coloured styles draw like bordered; borderless keeps its accent.
    if (look.inactive && style != MacButtonStyle.borderless) return bordered;

    switch (style) {
      case MacButtonStyle.bordered:
        return bordered;
      case MacButtonStyle.tinted:
        final deep = controlMix(accent, 0.88, controlBlackSolid);
        return _ButtonColors(
          controlFade(deep, look.dark ? 0.22 : 0.20),
          controlFade(deep, 0.28),
          controlFade(accent, look.dark ? 0.10 : 0.12),
          accent,
          accent,
          controlFade(accent, 0.40),
        );
      case MacButtonStyle.destructive:
        return _ButtonColors(
          controlFade(red, look.dark ? 0.22 : 0.20),
          controlFade(red, 0.28),
          controlFade(red, look.dark ? 0.12 : 0.10),
          red,
          red,
          controlFade(red, 0.40),
        );
      case MacButtonStyle.prominent:
        return _ButtonColors(
          look.dark ? accent : controlMix(accent, 0.97, controlBlackSolid),
          look.dark ? controlMix(accent, 0.94, controlWhiteSolid) : controlMix(accent, 0.88, controlBlackSolid),
          controlFade(accent, 0.40),
          c.glyphOnAccent,
          c.glyphOnAccent,
          controlWhite(0.5),
        );
      case MacButtonStyle.prominentDestructive:
        return _ButtonColors(
          red,
          look.dark ? controlMix(red, 0.94, controlWhiteSolid) : controlMix(red, 0.88, controlBlackSolid),
          controlFade(red, 0.40),
          controlWhiteSolid,
          controlWhiteSolid,
          controlWhite(0.5),
        );
      case MacButtonStyle.borderless:
        return _ButtonColors(
          controlClear,
          controlClear,
          controlClear,
          accent,
          look.dark ? controlMix(accent, 0.82, controlWhiteSolid) : controlMix(accent, 0.82, controlBlackSolid),
          controlFade(accent, 0.50),
        );
    }
  }
}
