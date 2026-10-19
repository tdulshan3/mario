import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/theme.dart';
import '_chrome.dart';

enum _ItemKind { standalone, grouped, tab }

/// Tells a [MacToolbarButton] whether it stands alone, sits in a [MacToolbarGroup], or is a tab of [MacToolbar.tabs].
class _ItemScope extends InheritedWidget {
  const _ItemScope({required this.kind, required super.child});
  final _ItemKind kind;

  static _ItemKind of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ItemScope>()?.kind ?? _ItemKind.standalone;

  @override
  bool updateShouldNotify(_ItemScope old) => old.kind != kind;
}

/// A toolbar row (web `mac-toolbar`): items 8 px apart, vertically centred. [MacTitlebar] builds one for you from
/// its `leading` / `actions`; use this widget directly for a toolbar outside a title bar.
///
///     MacToolbar(children: [
///       MacToolbarGroup(children: [backButton, forwardButton]),
///       const MacToolbarSpacer(),
///       MacToolbarButton(icon: AppleIcons.squareAndArrowUp, label: 'Share', onPressed: share),
///     ])
///
/// [MacToolbar.tabs] is the tab bar of a utility panel or a Settings window (kit "Utility Panel Tab Bar"):
/// 44 × 30 tabs, the selected one (`pressed: true`) on a material rounded rectangle.
///
///     MacToolbar.tabs(children: [
///       for (final (i, t) in tabs.indexed)
///         MacToolbarButton(icon: t.icon, label: t.name, pressed: i == tab, onPressed: () => setState(() => tab = i)),
///     ])
///     // Settings window: add showLabel: true to each tab (icon above its name).
class MacToolbar extends StatelessWidget {
  const MacToolbar({super.key, required this.children}) : _tabs = false;

  /// A centred row of tabs: [MacToolbarButton]s with `pressed` = selected.
  const MacToolbar.tabs({super.key, required this.children}) : _tabs = true;

  final List<Widget> children;
  final bool _tabs;

  @override
  Widget build(BuildContext context) => MacToolbarScope(child: _build(context));

  Widget _build(BuildContext context) {
    if (_tabs) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        child: _ItemScope(
          kind: _ItemKind.tab,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: children),
          ),
        ),
      );
    }
    return Row(spacing: 8, children: children);
  }
}

/// Flexible space in a toolbar (web `mac-toolbar__spacer`): pushes the next items to the right.
/// Use it only directly inside a [MacToolbar] (or a Row).
class MacToolbarSpacer extends StatelessWidget {
  const MacToolbarSpacer({super.key});

  @override
  Widget build(BuildContext context) => const Expanded(child: SizedBox(height: 1));
}

/// Several toolbar buttons in one material capsule (kit "Button Group"): back/forward, 2–4 related actions.
/// 4 px between buttons; 72 × 24 (medium) or 100 × 36 (XL) for three buttons.
///
///     MacToolbarGroup(children: [
///       MacToolbarButton(icon: AppleIcons.chevronLeft, label: 'Back', onPressed: back),
///       MacToolbarButton(icon: AppleIcons.chevronRight, label: 'Forward', onPressed: null),   // disabled
///     ])
class MacToolbarGroup extends StatelessWidget {
  const MacToolbarGroup({super.key, required this.children, this.semanticLabel});

  final List<Widget> children;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final h = MacControlSizeScope.sizesOf(context).globalHeight;
    final pad = (h - 12) / 6; // 2 at medium · 4 at XL
    return Semantics(
      container: true,
      label: semanticLabel,
      explicitChildNodes: true,
      child: _ItemScope(
        kind: _ItemKind.grouped,
        child: SizedBox(
          height: h,
          child: _ToolbarCapsule(
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon button in the toolbar (kit "Button" alone, "_Buttons" in a group). Alone it is its own round material
/// capsule (24 px medium, 36 px XL); in a [MacToolbarGroup] it shares the group's capsule. Toolbar buttons are the
/// one macOS control with a hover highlight (a faint circle); pressed = darker circle, on = grey circle.
///
///     MacToolbarButton(icon: AppleIcons.squareAndArrowUp, label: 'Share', onPressed: share)
///     MacToolbarButton(icon: AppleIcons.tag, label: 'Show Tags', pressed: showTags,
///                      onPressed: () => setState(() => showTags = !showTags))         // toggle
///     MacToolbarButton(icon: AppleIcons.sidebarLeft, label: 'Hide Sidebar', onPressed: toggleSidebar)
///     MacToolbarButton(label: 'Done', text: 'Done', onPressed: done)                  // rare word button
/// [onPressed] null = disabled (tertiary glyph, no hover). [label] is required: the accessible name.
class MacToolbarButton extends StatelessWidget {
  const MacToolbarButton({
    super.key,
    this.icon,
    required this.label,
    required this.onPressed,
    this.pressed,
    this.text,
    this.showLabel = false,
    this.focusNode,
  }) : assert(icon != null || text != null, 'MacToolbarButton needs an icon (or a text for a word button)');

  final IconData? icon;

  /// The accessible name and tooltip ("Share", "New Folder").
  final String label;
  final VoidCallback? onPressed;

  /// Toggle state: true = on (grey circle; in [MacToolbar.tabs] = the selected tab). Null = not a toggle.
  final bool? pressed;

  /// Visible text instead of (or after) the icon. Rare: only for a word like "Done".
  final String? text;

  /// In [MacToolbar.tabs]: show [label] under the icon (Settings window tabs).
  final bool showLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final dark = theme.isDark;
    final kind = _ItemScope.of(context);
    final h = MacControlSizeScope.sizesOf(context).globalHeight;
    final pad = (h - 12) / 6; // 2 · 4
    final item = h - 2 * pad; // 20 · 28
    final iconSize = h / 4 + 9; // 15 · 18 (web icon sizes)
    final on = pressed == true;

    // Highlight circles (kit "_Buttons": Selected = Fills-Vibrant Secondary; hover and pressed around it).
    final hoverFill = c.fillTertiary; // black 5% · white 5%
    final selectedFill = c.fillPrimary; // black 10% · white 10%
    final pressedFill = dark ? const Color(0x29FFFFFF) : const Color(0x29000000); // 16%

    return MacPressable(
      onPressed: onPressed,
      semanticLabel: label,
      tooltip: label,
      toggled: kind == _ItemKind.tab ? null : pressed,
      selected: kind == _ItemKind.tab ? on : null,
      focusNode: focusNode,
      builder: (context, s) {
        final enabled = s.enabled;
        final glyph = enabled ? c.labelVibrantPrimary : c.labelTertiary;
        Color state = const Color(0x00000000);
        if (enabled) {
          if (s.hovered) state = hoverFill;
          if (on) state = selectedFill;
          if (s.pressed) state = pressedFill;
        }

        if (kind == _ItemKind.tab) {
          // Kit "_Button - Utility Panel Tab Bar": 44 × 30, padding 1 · 2, radius 9, 24 px symbol; selected = material.
          final labeled = showLabel;
          final symbol = icon == null ? null : _glyph(icon!, labeled ? 22 : 24, glyph);
          Widget content = labeled
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    ?symbol,
                    Text(label, maxLines: 1, softWrap: false, style: macChromeText(11, 13, glyph)),
                  ],
                )
              : (symbol ?? Text(text ?? label, style: macChromeText(13, 16, glyph, weight: FontWeight.w500)));
          content = ConstrainedBox(
            constraints: BoxConstraints(minWidth: labeled ? 64 : 44, minHeight: labeled ? 0 : 30),
            child: Padding(
              padding: labeled ? const EdgeInsets.fromLTRB(8, 5, 8, 4) : const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: Center(widthFactor: 1, heightFactor: 1, child: content),
            ),
          );
          if (on) {
            content = _ToolbarCapsule(radius: 9, child: content);
          } else {
            content = DecoratedBox(
              decoration: ShapeDecoration(
                color: state,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              ),
              child: content,
            );
          }
          return MacFocusRing(show: s.focused, radius: 9, offset: -1, child: content);
        }

        final children = <Widget>[
          if (icon != null) _glyph(icon!, iconSize, glyph),
          if (text != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad + 4),
              child: Text(text!, maxLines: 1, softWrap: false, style: macChromeText(13, 16, glyph, weight: FontWeight.w500)),
            ),
        ];
        final content = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, spacing: 4, children: children);
        final circle = DecoratedBox(
          decoration: ShapeDecoration(color: state, shape: const StadiumBorder()),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: item, minHeight: item, maxHeight: item),
            child: Center(widthFactor: 1, child: content),
          ),
        );
        if (kind == _ItemKind.grouped) {
          return MacFocusRing(show: s.focused, offset: -1, child: circle);
        }
        // Alone: its own capsule (24 · 36), the highlight circle inset by the capsule padding.
        return MacFocusRing(
          show: s.focused,
          offset: -1,
          child: SizedBox(
            height: h,
            child: _ToolbarCapsule(
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: h),
                child: Padding(padding: EdgeInsets.all(pad), child: circle),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _glyph(IconData icon, double size, Color color) {
    // Web icons are drawn on a 16 grid filling the box; the CupertinoIcons glyphs are a little smaller.
    return SizedBox.square(
      dimension: size,
      child: OverflowBox(
        minWidth: 0,
        minHeight: 0,
        maxWidth: size * 1.2,
        maxHeight: size * 1.2,
        child: Icon(icon, size: size * 1.1, color: color),
      ),
    );
  }
}

/// The capsule of toolbar items: the classic Thin blur material ([MacGlassStyle.control]: blur + saturation, a 0.5 px
/// hairline, a soft shadow; no side edges or highlights). In an inactive window it turns into a flat capsule with a
/// 0.5 px outline. [radius] null = capsule.
/// Used by toolbar buttons, groups and the selected tab.
class _ToolbarCapsule extends StatelessWidget {
  const _ToolbarCapsule({required this.child, this.radius});
  final Widget child;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final dark = AppleTheme.of(context).isDark;
    if (MacWindowState.isInactive(context)) {
      // Kit Active = False: no material; fill black 2% · white 5%, 0.5 px ring #EBEBEB · #E6E6E6.
      return CustomPaint(
        painter: _FlatCapsulePainter(
          radius: radius,
          // Dark: the kit's #0D0D0D "plus lighter" fill (+5% on any background); Light: black 2%.
          fill: dark ? const Color(0xFF0D0D0D) : const Color(0x05000000),
          plus: dark,
          ring: dark ? const Color(0xFFE6E6E6) : const Color(0xFFEBEBEB),
        ),
        child: child,
      );
    }
    return MacGlass(style: MacGlassStyle.control, radius: radius, child: child);
  }
}

RRect _capsule(Rect rect, double? radius) {
  final r = (radius ?? rect.shortestSide / 2).clamp(0.0, rect.shortestSide / 2);
  return RRect.fromRectAndRadius(rect, Radius.circular(r));
}

class _FlatCapsulePainter extends CustomPainter {
  _FlatCapsulePainter({required this.radius, required this.fill, required this.ring, this.plus = false});
  final bool plus;
  final double? radius;
  final Color fill;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = _capsule(rect, radius);
    canvas.save();
    canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(rect.inflate(4)), Path()..addRRect(shape)));
    canvas.drawRRect(shape.inflate(0.5), Paint()..color = ring);
    canvas.restore();
    canvas.drawRRect(
      shape,
      Paint()
        ..color = fill
        ..blendMode = plus ? BlendMode.plus : BlendMode.srcOver,
    );
  }

  @override
  bool shouldRepaint(_FlatCapsulePainter old) =>
      old.radius != radius || old.fill != fill || old.ring != ring || old.plus != plus;
}
