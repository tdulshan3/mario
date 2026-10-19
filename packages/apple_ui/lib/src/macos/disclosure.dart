import 'package:flutter/widgets.dart';

import '../core/macos_tokens.dart';
import '_control_support.dart';

Duration _motion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : const Duration(milliseconds: 200);

/// A disclosure triangle (kit "_Chevron" of Forms): a chevron that points right when closed and turns to point
/// down when open, showing [child] below [title].
///
///     MacDisclosure(
///       title: 'Advanced Options',
///       open: showAdvanced,
///       onToggle: (v) => setState(() => showAdvanced = v),
///       child: MacCheckbox(value: logging, onChanged: (v) => setState(() => logging = v), label: 'Enable logging'),
///     )
///     MacDisclosure(open: expanded, onToggle: …, semanticLabel: 'Show contents of Documents')   // chevron only (tree rows)
///
/// Clicking the chevron or the title toggles it (Space/Return from the keyboard). The content is indented to line up
/// with the title text (chevron box + 8). [onToggle] null = disabled. The rotation animates (0.2 s; off with
/// Reduce Motion). Keep rarely used options closed by default and remember what people chose.
class MacDisclosure extends StatelessWidget {
  const MacDisclosure({
    super.key,
    this.title,
    required this.open,
    required this.onToggle,
    this.child,
    this.semanticLabel,
    this.size,
    this.focusNode,
  });

  /// The section title (SF Pro Medium). Null = a stand-alone 16 × 16 chevron button.
  final String? title;
  final bool open;
  final ValueChanged<bool>? onToggle;

  /// Shown below the title while [open].
  final Widget? child;

  /// Accessible name. Required without a [title].
  final String? semanticLabel;
  final MacControlSize? size;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final look = ControlLook.of(context, size);
    final s = look.s;
    final fs = s.globalFontSize;
    final enabled = onToggle != null;
    final color = enabled ? look.c.labelPrimary : look.c.labelTertiary;
    final boxW = fs * 8 / 13;
    final glyph = fs * 14.7 / 13;
    final duration = _motion(context);

    final chevron = SizedBox(
      width: boxW,
      height: 16,
      child: OverflowBox(
        minWidth: 0,
        minHeight: 0,
        maxWidth: glyph,
        maxHeight: glyph,
        child: AnimatedRotation(
          turns: open ? 0.25 : 0,
          duration: duration,
          curve: Curves.ease,
          child: ControlGlyph(
            lines: ControlGlyph.chevronRight,
            viewBox: const Size(16, 16),
            strokeWidth: 1.35,
            color: color,
            width: glyph,
            height: glyph,
          ),
        ),
      ),
    );

    final summary = Semantics(
      button: true,
      expanded: open,
      enabled: enabled,
      label: semanticLabel ?? title,
      excludeSemantics: true,
      child: ControlPressable(
        onPressed: enabled ? () => onToggle!(!open) : null,
        focusNode: focusNode,
        builder: (context, state) {
          final Widget row = title == null
              ? SizedBox(width: 16, height: 16, child: Center(child: chevron))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  chevron,
                  const SizedBox(width: 8),
                  Flexible(child: Text(title!, style: look.text(fs, color, lineHeight: 16))),
                ]);
          return ControlFocusRing(
            visible: state.focused,
            color: look.focusColor,
            radius: 4,
            offset: title == null ? 0 : 1,
            child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 16), child: row),
          );
        },
      ),
    );
    if (title == null || child == null) return summary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        summary,
        if (open) Padding(padding: EdgeInsets.only(left: boxW + 8), child: child),
      ],
    );
  }
}

/// A disclosure button (kit "Disclosure Button"): a rounded square (a circle at large/XL) with ⌄ that expands a view
/// to show more options (like the full file browser of a Save panel); it shows ⌃ while expanded. No text.
///
///     MacDisclosureButton(open: showMore, onToggle: (v) => setState(() => showMore = v), semanticLabel: 'Show More Options')
///
/// [onToggle] null = disabled. Put it at the end of the row whose view it expands. On a blur material ([MacGlass])
/// the pressed and disabled fills are slightly lighter, like the kit's Over-glass variants. No hover effect.
class MacDisclosureButton extends StatelessWidget {
  const MacDisclosureButton({
    super.key,
    required this.open,
    required this.onToggle,
    required this.semanticLabel,
    this.size,
    this.focusNode,
  });

  final bool open;
  final ValueChanged<bool>? onToggle;

  /// What it shows or hides ("Show More Options").
  final String semanticLabel;
  final MacControlSize? size;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final look = ControlLook.of(context, size);
    final s = look.s;
    final enabled = onToggle != null;
    final h = s.globalHeight;
    final glyph = s.disclosureFontSize * 16 / 13;
    final duration = _motion(context);
    return Semantics(
      button: true,
      expanded: open,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: ControlPressable(
        onPressed: enabled ? () => onToggle!(!open) : null,
        focusNode: focusNode,
        builder: (context, state) {
          final Color fill;
          if (!enabled) {
            fill = look.overGlass ? look.ld(controlBlack(0.03), controlWhite(0.04)) : look.borderedFillDisabled;
          } else if (state.pressed) {
            fill = look.overGlass ? look.ld(controlBlack(0.14), controlWhite(0.15)) : look.borderedFillPressed;
          } else {
            fill = look.borderedFill;
          }
          return ControlBox(
            color: fill,
            radius: s.disclosureRadius,
            focusRing: state.focused ? look.focusColor : null,
            child: SizedBox(
              width: h,
              height: h,
              child: Center(
                child: AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: duration,
                  curve: Curves.ease,
                  child: ControlGlyph(
                    lines: ControlGlyph.chevronDownBold,
                    viewBox: const Size(16, 16),
                    strokeWidth: 2,
                    color: enabled ? look.c.labelPrimary : look.c.labelTertiary,
                    width: glyph,
                    height: glyph,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
