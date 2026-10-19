import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '_control_support.dart';
import 'menus.dart';

/// A pop-up button (kit "Pop-Up Button"): shows the CURRENT value + ⌃⌄ and opens a menu to pick ONE value,
/// like an HTML `<select>`. The menu marks the current value with a checkmark.
///
///     MacPopUpButton<String>(
///       options: const ['Name', 'Date Modified', 'Size', 'Kind'],
///       value: sortBy,
///       onChanged: (v) => setState(() => sortBy = v),
///       semanticLabel: 'Sort by',
///     )
///     MacPopUpButton<Sort>(options: Sort.values, value: sort, labelOf: (s) => s.title, onChanged: …)
///
/// It is as wide as its longest option; wrap it in `SizedBox(width: …)` to line pop-ups up in a column (the label then
/// truncates). [onChanged] null = disabled. [toolbar] = the material capsule version for toolbars (medium or XL).
/// The menu opens on mouse-down, or with Space, Return, ↑ or ↓ when it has keyboard focus. No hover effect
/// (the toolbar version highlights on hover, like every toolbar item). Put a label with a colon before it in forms.
class MacPopUpButton<T> extends StatelessWidget {
  const MacPopUpButton({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelOf,
    this.toolbar = false,
    this.semanticLabel,
    this.size,
  });

  final List<T> options;
  final T value;
  final ValueChanged<T>? onChanged;

  /// The text of an option. Default: `option.toString()`.
  final String Function(T option)? labelOf;
  final bool toolbar;

  /// Accessible name ("Sort by"). Required when there is no visible label before it.
  final String? semanticLabel;
  final MacControlSize? size;

  String _label(T o) => labelOf?.call(o) ?? '$o';

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return MacMenu(
      enabled: enabled,
      semanticLabel: semanticLabel,
      items: [
        for (final o in options)
          MacMenuItem(label: _label(o), checked: o == value, onSelected: enabled ? () => onChanged!(o) : null),
      ],
      trigger: _MenuButtonFace(
        size: size,
        enabled: enabled,
        toolbar: toolbar,
        popup: true,
        label: _label(value),
        sizingLabels: [for (final o in options) _label(o)],
        semanticLabel: semanticLabel,
      ),
    );
  }
}

/// A pull-down button (kit "Pulldown Button"): a FIXED title (or icon) + ⌄ that opens a menu of COMMANDS.
/// Its title never changes; never use it to pick a value (that is [MacPopUpButton]).
///
///     MacPullDownButton(
///       label: 'Actions',
///       items: [
///         MacMenuItem(label: 'Duplicate', onSelected: duplicate),
///         MacMenuItem(label: 'Rename…', onSelected: rename),
///         const MacMenuDivider(),
///         MacMenuItem(label: 'Move to Trash', onSelected: trash),
///       ],
///     )
///     MacPullDownButton(icon: AppleIcons.ellipsisCircle, semanticLabel: 'More Actions', toolbar: true, items: […])
///
/// [items] are [MacMenuItem]s, [MacMenuDivider]s and [MacMenuHeader]s (see menus). [enabled] false = disabled.
/// [toolbar] = the material capsule version (icon + ⌄, medium or XL). An icon-only pull-down needs [semanticLabel].
class MacPullDownButton extends StatelessWidget {
  const MacPullDownButton({
    super.key,
    this.label,
    this.icon,
    required this.items,
    this.enabled = true,
    this.toolbar = false,
    this.semanticLabel,
    this.size,
  }) : assert(label != null || icon != null, 'MacPullDownButton needs a label, an icon, or both');

  final String? label;
  final IconData? icon;
  final List<Widget> items;
  final bool enabled;
  final bool toolbar;
  final String? semanticLabel;
  final MacControlSize? size;

  @override
  Widget build(BuildContext context) => MacMenu(
        enabled: enabled,
        semanticLabel: semanticLabel ?? label,
        items: items,
        trigger: _MenuButtonFace(
          size: size,
          enabled: enabled,
          toolbar: toolbar,
          popup: false,
          label: label,
          icon: icon,
          semanticLabel: semanticLabel,
        ),
      );
}

/// The button part of a pop-up / pull-down (pop-up-buttons.css). It looks pressed while the mouse is down on it and
/// while its menu is open; the menu itself opens from [MacMenu] (mouse-down) or from the keyboard here.
class _MenuButtonFace extends StatefulWidget {
  const _MenuButtonFace({
    required this.size,
    required this.enabled,
    required this.toolbar,
    required this.popup,
    required this.label,
    this.icon,
    this.sizingLabels = const [],
    this.semanticLabel,
  });
  final MacControlSize? size;
  final bool enabled;
  final bool toolbar;
  final bool popup;
  final String? label;
  final IconData? icon;
  final List<String> sizingLabels;
  final String? semanticLabel;

  @override
  State<_MenuButtonFace> createState() => _MenuButtonFaceState();
}

class _MenuButtonFaceState extends State<_MenuButtonFace> {
  bool _down = false;
  bool _focused = false;
  bool _hovered = false;

  void _openFromKeyboard() => MacMenu.maybeOf(context)?.open(highlightFirst: true);

  @override
  Widget build(BuildContext context) {
    final look = ControlLook.of(context, widget.size);
    final s = look.s;
    final h = s.globalHeight;
    final enabled = widget.enabled;
    final open = MacMenu.isOpenOf(context);
    final pressed = enabled && (_down || open);
    final toolbar = widget.toolbar || MacToolbarScope.isInToolbar(context);
    final c = look.c;

    final Color text = !enabled ? c.labelTertiary : (toolbar ? c.labelVibrantPrimary : c.labelPrimary);
    final fontSize = s.globalFontSize;

    // Indicator: ⌃⌄ (pop-up) or ⌄ (pull-down), centred in a box at the right end.
    final double pad = toolbar ? h / 6 + 2 : 0;
    final double boxW;
    final double glyph;
    if (widget.popup) {
      boxW = toolbar ? h / 6 + 4 : h;
      glyph = toolbar ? h / 4 + 5 : s.popupFontSizeChevron * 16 / 11;
    } else {
      boxW = toolbar ? h / 6 + 6 : h;
      glyph = toolbar ? h / 4 + 3 : s.disclosureFontSize * 12 / 13;
    }
    final indicator = SizedBox(
      width: boxW,
      height: h,
      child: OverflowBox(
        minWidth: 0,
        minHeight: 0,
        maxWidth: glyph,
        maxHeight: glyph,
        child: ControlGlyph(
          lines: widget.popup ? ControlGlyph.popupIndicator : ControlGlyph.chevronDownBold,
          viewBox: const Size(16, 16),
          strokeWidth: widget.popup ? 1.75 : 2,
          color: text,
          width: glyph,
          height: glyph,
        ),
      ),
    );

    final gap = toolbar ? 2.0 : 8.0;
    final textStyle = look.text(fontSize, text);
    Widget? labelWidget;
    if (widget.label != null) {
      labelWidget = Text(widget.label!, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: textStyle);
      if (widget.sizingLabels.length > 1) {
        // As wide as the longest option, like a <select>.
        labelWidget = Stack(children: [
          for (final l in widget.sizingLabels)
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Text(l, maxLines: 1, softWrap: false, style: textStyle),
            ),
          labelWidget,
        ]);
      }
    }
    final iconSize = toolbar ? h / 4 + 9 : fontSize + 1;
    final iconWidget = widget.icon == null
        ? null
        : SizedBox(width: iconSize, height: iconSize, child: Center(child: Icon(widget.icon, size: iconSize, color: text)));

    Widget content = LayoutBuilder(builder: (context, constraints) {
      final fill = constraints.hasTightWidth;
      final leading = <Widget>[
        ?iconWidget,
        if (iconWidget != null && labelWidget != null) SizedBox(width: toolbar ? 2 : 8),
        if (labelWidget != null) fill ? Expanded(child: Align(alignment: Alignment.centerLeft, child: labelWidget)) : labelWidget,
      ];
      return Padding(
        padding: EdgeInsets.only(left: toolbar ? pad : s.popupInsetLeft, right: toolbar ? pad : 0),
        child: Row(
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          children: [
            ...leading,
            SizedBox(width: gap),
            if (fill && labelWidget == null) const Spacer(),
            indicator,
          ],
        ),
      );
    });
    content = SizedBox(height: h, child: content);

    Widget face;
    if (toolbar) {
      final Color? overlay = !enabled
          ? null
          : pressed
              ? look.ld(controlBlack(0.16), controlWhite(0.16))
              : _hovered
                  ? look.ld(controlBlack(0.05), controlWhite(0.05))
                  : null;
      face = ControlFocusRing(
        visible: _focused,
        color: look.focusColor,
        radius: h / 2,
        child: ControlToolbarCapsule(overlay: overlay, child: content),
      );
    } else {
      final fillColor = !enabled ? look.borderedFillDisabled : (pressed ? look.borderedFillPressed : look.borderedFill);
      face = ControlBox(color: fillColor, radius: s.buttonRadius, focusRing: _focused ? look.focusColor : null, child: content);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      value: widget.popup ? widget.label : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        onShowHoverHighlight: toolbar ? (v) => setState(() => _hovered = v) : null,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowDown): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _openFromKeyboard();
            return null;
          }),
        },
        child: Listener(
          onPointerDown: enabled ? (e) => e.buttons == kPrimaryButton ? setState(() => _down = true) : null : null,
          onPointerUp: (_) => _down ? setState(() => _down = false) : null,
          onPointerCancel: (_) => _down ? setState(() => _down = false) : null,
          child: face,
        ),
      ),
    );
  }
}
