// Shared parts of the macOS text controls (text field, text area, search field, combo box):
// the kit "_Input Fields" bezel, its colours and the focus ring. Private to apple_ui (not exported).
import 'package:flutter/cupertino.dart' show CupertinoTextField, OverlayVisibilityMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/theme.dart';
import '../core/typography.dart';

/// Forces an interaction look on the Mac controls below, for static kit sheets and screenshots only
/// (the CSS demo classes `.is-focused` / `.is-pressed`). Not exported: apps never need it.
class MacDemoStates extends InheritedWidget {
  const MacDemoStates({super.key, this.focused = false, this.pressed = false, required super.child});

  /// Draw the editing focus ring as if the control had keyboard focus.
  final bool focused;

  /// Draw the pressed look (combo box arrow button).
  final bool pressed;

  static MacDemoStates? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MacDemoStates>();

  @override
  bool updateShouldNotify(MacDemoStates old) => old.focused != focused || old.pressed != pressed;
}

/// Colours of the kit "_Input Fields" bezel (text field, search field, combo box) for one appearance.
class MacFieldColors {
  MacFieldColors._(this.dark, this.accent);

  factory MacFieldColors.of(BuildContext context) {
    final theme = AppleTheme.of(context);
    return MacFieldColors._(theme.isDark, theme.accentColor);
  }

  final bool dark;
  final Color accent;

  /// White / #1E1E1E (the window background).
  Color get fill => dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

  /// 1 px edge outside: black 8 % / white 4 %.
  Color get ring => dark ? const Color(0x0AFFFFFF) : const Color(0x14000000);

  /// Disabled fill: white 50 % / #1E1E1E 50 %.
  Color get fillDisabled => dark ? const Color(0x801E1E1E) : const Color(0x80FFFFFF);

  /// Disabled edge: black 4 % / white 4 %.
  Color get ringDisabled => dark ? const Color(0x0AFFFFFF) : const Color(0x0A000000);

  /// Focus ring: accent 50 % (3.5 px outside + 1 px inside).
  Color get focus => accent.withValues(alpha: accent.a * 0.5);
}

/// Text style of a field: SF Pro / Inter Medium at the control size's font size (10 · 11 · 13 · 13 · 13).
TextStyle macFieldTextStyle(
  BuildContext context, {
  required double fontSize,
  required Color color,
  FontWeight weight = FontWeight.w500,
  double? lineHeight,
}) {
  final lh = lineHeight ?? (fontSize <= 10 ? 13.0 : (fontSize <= 11 ? 14.0 : 16.0));
  return appleFont(size: fontSize).copyWith(
    fontSize: fontSize,
    height: lh / fontSize,
    letterSpacing: 0,
    fontWeight: weight,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
    decoration: TextDecoration.none,
  );
}

/// True when the editing focus ring may show: the window is active.
bool macFocusRingAllowed(BuildContext context) => !MacWindowState.isInactive(context);

/// Paints the field bezel: [ring] 1 px outside, the [fill], and with [focus] the accent ring
/// (3.5 px outside over the edge + 1 px inside), like macos.css `.mac-textfield:focus`.
/// [radius] null = capsule (search field).
class MacFieldBezelPainter extends CustomPainter {
  MacFieldBezelPainter({required this.fill, required this.ring, this.focus, this.radius = 6, this.ringWidth = 1});

  final Color fill;
  final Color ring;
  final double ringWidth;
  final Color? focus;
  final double? radius;

  // Circular corners, like the kit bezel and macos.css (a continuous-corner shape makes the 3.5 px ring too round).
  Path _shape(Rect rect, double? r) {
    final rr = (r ?? rect.shortestSide / 2).clamp(0.0, rect.shortestSide / 2);
    return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(rr)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = _shape(rect, radius);
    Path outside(double spread) {
      final grown = _shape(rect.inflate(spread), radius == null ? null : radius! + spread);
      return Path.combine(PathOperation.difference, grown, shape);
    }

    // Outer shadows (CSS box-shadow: only outside the box). The focus ring paints over the 1 px edge.
    canvas.drawPath(outside(ringWidth), Paint()..color = ring);
    if (focus != null) canvas.drawPath(outside(3.5), Paint()..color = focus!);
    canvas.drawPath(shape, Paint()..color = fill);
    if (focus != null) {
      final inner = _shape(rect.deflate(1), radius == null ? null : (radius! - 1).clamp(0.0, double.infinity));
      canvas.drawPath(Path.combine(PathOperation.difference, shape, inner), Paint()..color = focus!);
    }
  }

  @override
  bool shouldRepaint(MacFieldBezelPainter old) =>
      old.fill != fill || old.ring != ring || old.ringWidth != ringWidth || old.focus != focus || old.radius != radius;
}

/// Width rule shared by the fields: [width] if given; else fill the available width, or [fallback]
/// (the kit's default width) when the parent gives unbounded width (a Row, a Stack).
class MacFieldWidth extends StatelessWidget {
  const MacFieldWidth({super.key, required this.width, required this.fallback, required this.child});
  final double? width;
  final double fallback;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (width != null) return SizedBox(width: width, child: child);
    // LimitedBox only limits an unbounded width; SizedBox(infinity) then takes the full (or limited) width.
    return LimitedBox(
      maxWidth: fallback,
      child: SizedBox(width: double.infinity, child: child),
    );
  }
}

/// Keeps an internal controller in step with a controlled `value` (no-op when the app passes its own controller).
/// Only a CHANGED `value` is applied, so a parent that rebuilds with the same value never resets what people typed.
void syncControlledText(TextEditingController? external, String? oldValue, String? value, TextEditingController internal) {
  if (external != null || value == null || value == oldValue || value == internal.text) return;
  internal.value = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );
}

/// The editable part of every Mac text control: a borderless CupertinoTextField with the Mac caret (2 px, accent,
/// control-size height), Mac selection colour, and Return that keeps the focus (or moves on with [TextInputAction.next]).
Widget macCupertinoField(
  BuildContext context, {
  required TextEditingController controller,
  required FocusNode focusNode,
  required TextStyle style,
  required TextStyle placeholderStyle,
  required EdgeInsets padding,
  required double cursorHeight,
  String? placeholder,
  bool obscureText = false,
  bool enabled = true,
  bool readOnly = false,
  bool autofocus = false,
  TextInputType? keyboardType,
  TextInputAction? textInputAction,
  List<TextInputFormatter>? inputFormatters,
  Iterable<String>? autofillHints,
  int? maxLength,
  TextAlign textAlign = TextAlign.start,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  int? minLines,
  int? maxLines = 1,
  bool alignTop = false,
}) {
  final accent = AppleTheme.of(context).accentColor;
  return DefaultSelectionStyle(
    selectionColor: accent.withValues(alpha: 0.28),
    cursorColor: accent,
    child: CupertinoTextField(
      controller: controller,
      focusNode: focusNode,
      decoration: const BoxDecoration(), // the bezel is painted by the Mac widget
      padding: padding,
      placeholder: placeholder,
      placeholderStyle: placeholderStyle,
      style: style,
      textAlignVertical: alignTop ? TextAlignVertical.top : TextAlignVertical.center,
      textAlign: textAlign,
      cursorColor: accent,
      cursorWidth: 2,
      cursorHeight: cursorHeight,
      cursorRadius: const Radius.circular(1),
      obscureText: obscureText,
      obscuringCharacter: '•',
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      maxLength: maxLength,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: () {
        if (textInputAction == TextInputAction.next) focusNode.nextFocus();
      },
      minLines: minLines,
      maxLines: maxLines,
      clearButtonMode: OverlayVisibilityMode.never,
      scrollPadding: EdgeInsets.zero,
    ),
  );
}

/// An SF-Symbol-like glyph from the icon font, drawn so that it looks [glyphSize] points tall (the kit's symbol size),
/// centred in its layout box. CupertinoIcons glyphs sit inside a larger em box, hence the 17/13 scale (as macos.css).
Widget macSymbol(IconData icon, double glyphSize, Color color, {double scale = 17 / 13}) {
  final drawn = glyphSize * scale;
  return SizedBox(
    width: glyphSize,
    height: glyphSize,
    child: OverflowBox(
      maxWidth: drawn,
      maxHeight: drawn,
      child: Icon(icon, size: drawn, color: color),
    ),
  );
}
