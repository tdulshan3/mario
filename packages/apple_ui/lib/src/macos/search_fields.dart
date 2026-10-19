import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '_glyphs.dart';
import '_text_input.dart';

/// A macOS search field (kit pages "Search Fields" and "Toolbars › Search"): a capsule with a magnifying glass,
/// the text, and a clear button (xmark.circle.fill) that appears while there is text. Escape or the clear button
/// empties it. Filter as people type ([onChanged]); use [onSubmitted] only for slow searches.
///
///     MacSearchField(value: query, onChanged: (q) => setState(() => query = q))      // content field (white bezel)
///     MacSearchField(toolbar: true, width: 180, onChanged: filter)                   // toolbar field (material)
///     MacSearchField(placeholder: 'Search Mail', controller: _search)
///     MacSearchField(enabled: false)
///
/// The main search field of a window sits at the trailing end of the toolbar ([toolbar] true).
/// Width: [width] if given, else the width it gets (120 inside a Row). Keep it at least 120 wide.
class MacSearchField extends StatefulWidget {
  const MacSearchField({
    super.key,
    this.controller,
    this.value,
    this.onChanged,
    this.onSubmitted,
    this.placeholder = 'Search',
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.width,
    this.size,
    this.toolbar = false,
    this.semanticLabel = 'Search',
  });

  final TextEditingController? controller;

  /// Controlled text (used when [controller] is null).
  final String? value;

  /// Every change, including clearing (with '').
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// "Search" or "Search" + scope ("Search Mail"). No "…".
  final String? placeholder;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final double? width;

  /// Control size. Null = the nearest [MacControlSizeScope]. Toolbars use medium or xl.
  final MacControlSize? size;

  /// The search field of a window toolbar, on the Thin blur material.
  final bool toolbar;

  /// Accessible name (default "Search").
  final String semanticLabel;

  @override
  State<MacSearchField> createState() => _MacSearchFieldState();
}

class _MacSearchFieldState extends State<MacSearchField> {
  TextEditingController? _own;
  FocusNode? _ownFocus;

  // Mario patch: keys the row holding the text field. The toolbar bezel below
  // changes shape with focus (the ring wraps the row in a CustomPaint) and with
  // the window's active state (MacGlass vs a flat bezel). Without a key each of
  // those rebuilt the CupertinoTextField from scratch, and the new one never
  // reattached to the text input — so clicking the field focused it and every
  // keystroke after that went nowhere. A GlobalKey moves the field across the
  // reshaping with its state, and its input connection, intact.
  final GlobalKey _rowKey = GlobalKey(debugLabel: 'MacSearchField');

  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController(text: widget.value ?? ''));
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'MacSearchField'));

  @override
  void initState() {
    super.initState();
    _focus.addListener(_rebuild);
    _controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(MacSearchField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_rebuild);
      _focus.addListener(_rebuild);
    }
    if (old.controller != widget.controller) {
      (old.controller ?? _own)?.removeListener(_rebuild);
      _controller.addListener(_rebuild);
    }
    syncControlledText(widget.controller, old.value, widget.value, _controller);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_rebuild);
    _controller.removeListener(_rebuild);
    _own?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _clear() {
    if (_controller.text.isEmpty) return;
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final controlSize = widget.size ?? MacControlSizeScope.of(context);
    final s = MacSizes.of(controlSize);
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final fc = MacFieldColors.of(context);
    final inactive = MacWindowState.isInactive(context);
    final demo = MacDemoStates.maybeOf(context);
    final focused = widget.enabled && (_focus.hasFocus || (demo?.focused ?? false)) && !inactive;
    final hasText = _controller.text.isNotEmpty;
    final toolbar = widget.toolbar || MacToolbarScope.isInToolbar(context);
    final xl = controlSize == MacControlSize.xl;

    // Colours: content field = text-field bezel + label colours; toolbar field = material + vibrant labels.
    final Color glyph, text, placeholder, clear;
    if (toolbar) {
      glyph = widget.enabled ? c.labelVibrantSecondary : c.labelVibrantTertiary;
      text = widget.enabled ? c.labelVibrantPrimary : c.labelVibrantTertiary;
      placeholder = glyph;
      clear = c.labelVibrantSecondary;
    } else {
      glyph = widget.enabled ? c.labelPrimary : c.labelTertiary;
      text = glyph;
      placeholder = widget.enabled ? c.labelSecondary : c.labelTertiary;
      clear = c.labelSecondary;
    }
    final glyphSize = toolbar ? 13.0 : s.fieldsFontSizeSearchGlyph; // 11 · 13 · 13 · 13 · 13
    final glyphBoxH = toolbar ? 16.0 : s.fieldsLeadingSearchGlyph; // 13 · 15 · 15 · 15 · 15
    final gap = toolbar ? (xl ? 6.0 : 4.0) : 2.0;
    final padL = toolbar ? (xl ? 10.0 : 6.0) : s.fieldsInsetLeft;
    final padR = toolbar ? (xl ? 10.0 : 6.0) : s.fieldsInsetRight;
    final style = macFieldTextStyle(context, fontSize: s.globalFontSize, color: text);

    final field = macCupertinoField(
      context,
      controller: _controller,
      focusNode: _focus,
      style: style,
      placeholder: widget.placeholder,
      placeholderStyle: style.copyWith(color: placeholder),
      padding: EdgeInsets.zero,
      cursorHeight: s.cursorHeight,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );

    Widget row = Padding(
      padding: EdgeInsets.only(left: padL, right: padR),
      child: Row(
        children: [
          SizedBox(
            child: macGlyphBox(
              MacGlyphKind.magnifyingglass,
              width: glyphSize + 3,
              height: glyphBoxH,
              glyph: glyphSize * 17 / 13,
              color: glyph,
            ),
          ),
          SizedBox(width: gap),
          Expanded(child: field),
          if (hasText && widget.enabled) ...[
            SizedBox(width: gap),
            Semantics(
              button: true,
              label: 'Clear',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clear,
                child: macGlyphBox(
                  MacGlyphKind.xmarkCircleFill,
                  width: glyphSize + 3,
                  height: glyphBoxH,
                  glyph: glyphSize * 15 / 13,
                  color: clear,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    // Escape empties the field (and only then: with no text it goes on to close a sheet or popover).
    row = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape && _controller.text.isNotEmpty) {
          _clear();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: row,
    );
    row = KeyedSubtree(key: _rowKey, child: row);

    Widget bezel;
    if (toolbar) {
      final accent = theme.accentColor;
      final ringFocus = focused
          ? CustomPaint(
              painter: _ToolbarFocusPainter(accent),
              child: SizedBox(height: s.globalHeight, child: row),
            )
          : SizedBox(height: s.globalHeight, child: row);
      bezel = inactive
          ? CustomPaint(
              painter: MacFieldBezelPainter(
                fill: theme.isDark ? c.fillVibrantTertiary : c.fillVibrantQuinary,
                ring: theme.isDark ? const Color(0xFFE6E6E6) : const Color(0xFFEBEBEB),
                ringWidth: 0.5,
                radius: null,
              ),
              child: SizedBox(height: s.globalHeight, child: row),
            )
          : MacGlass(child: ringFocus);
    } else {
      bezel = CustomPaint(
        painter: MacFieldBezelPainter(
          fill: widget.enabled ? fc.fill : fc.fillDisabled,
          ring: widget.enabled ? fc.ring : fc.ringDisabled,
          focus: focused ? fc.focus : null,
          radius: null,
        ),
        child: SizedBox(height: s.globalHeight, child: row),
      );
    }

    return Semantics(
      label: widget.semanticLabel,
      child: MacFieldWidth(width: widget.width, fallback: toolbar ? 130 : 120, child: bezel),
    );
  }
}

/// Toolbar search field focus: accent 15 % 1 px + accent 25 % 3.5 px outside the capsule.
class _ToolbarFocusPainter extends CustomPainter {
  _ToolbarFocusPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    Path capsule(Rect r) => Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2)));
    final shape = capsule(rect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, capsule(rect.inflate(3.5)), shape),
      Paint()..color = accent.withValues(alpha: accent.a * 0.25),
    );
    canvas.drawPath(
      Path.combine(PathOperation.difference, capsule(rect.inflate(1)), shape),
      Paint()..color = accent.withValues(alpha: accent.a * 0.15),
    );
  }

  @override
  bool shouldRepaint(_ToolbarFocusPainter old) => old.accent != accent;
}
