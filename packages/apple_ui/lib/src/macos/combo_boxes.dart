import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '_glyphs.dart';
import '_popup_list.dart';
import '_text_input.dart';

/// A macOS combo box (kit page "Combo Boxes"): a text field with an attached arrow button that opens a list of
/// suggestions. People type ANY value or pick one from the list. Use it only when typed values are allowed
/// (a font size, a zoom level, a recent server); for a fixed set of values use a pop-up button.
///
///     MacComboBox(
///       items: const ['9', '10', '12', '14', '18', '24', '36'],
///       value: fontSize,
///       onChanged: (v) => setState(() => fontSize = v),   // typed text AND picked items
///       width: 80,
///       semanticLabel: 'Font Size',
///     )
///     MacComboBox(items: zoomLevels, controller: _zoom, placeholder: 'Zoom')
///     MacComboBox(items: sizes, value: '12', enabled: false)
///
/// Keyboard: ↓ or Option-↓ opens the whole list, ↑ ↓ move, Return takes the highlighted item, Escape closes.
/// Typing shows only the items that contain the text. Width: [width], else the width it gets (100 inside a Row).
class MacComboBox extends StatefulWidget {
  const MacComboBox({
    super.key,
    required this.items,
    this.controller,
    this.value,
    this.onChanged,
    this.onSubmitted,
    this.placeholder,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.width,
    this.size,
    this.keyboardType,
    this.inputFormatters,
    this.semanticLabel,
  });

  /// The suggestions, in a useful order (ascending numbers, most recent first, A–Z). Up to about 10.
  final List<String> items;
  final TextEditingController? controller;

  /// Controlled text (used when [controller] is null).
  final String? value;

  /// The new text: typed, or an item picked from the list.
  final ValueChanged<String>? onChanged;

  /// Return pressed with no list item highlighted.
  final ValueChanged<String>? onSubmitted;
  final String? placeholder;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final double? width;

  /// Control size. Null = the nearest [MacControlSizeScope].
  final MacControlSize? size;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? semanticLabel;

  @override
  State<MacComboBox> createState() => _MacComboBoxState();
}

class _MacComboBoxState extends State<MacComboBox> {
  TextEditingController? _own;
  FocusNode? _ownFocus;
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _tapGroup = Object();
  List<int> _visible = const []; // indexes into widget.items shown in the open list
  int? _highlight; // index into _visible
  bool _pressed = false;
  bool _choosing = false;

  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController(text: widget.value ?? ''));
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'MacComboBox'));

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(MacComboBox old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
    syncControlledText(widget.controller, old.value, widget.value, _controller);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _own?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) _close();
    setState(() {});
  }

  bool get _isOpen => _portal.isShowing;

  void _open({required bool showAll}) {
    if (!widget.enabled) return;
    final q = showAll ? '' : _controller.text.trim().toLowerCase();
    final visible = [
      for (var i = 0; i < widget.items.length; i++)
        if (q.isEmpty || widget.items[i].toLowerCase().contains(q)) i,
    ];
    if (visible.isEmpty) {
      _close();
      return;
    }
    final current = _controller.text.trim().toLowerCase();
    final match = visible.indexWhere((i) => widget.items[i].toLowerCase() == current);
    setState(() {
      _visible = visible;
      _highlight = match < 0 ? null : match;
    });
    _portal.show();
  }

  void _close() {
    if (_portal.isShowing) _portal.hide();
    if (mounted) setState(() => _highlight = null);
  }

  void _choose(int visibleIndex) {
    final value = widget.items[_visible[visibleIndex]];
    _choosing = true;
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _choosing = false;
    widget.onChanged?.call(value);
    _close();
    _focus.requestFocus();
  }

  void _move(int step) {
    if (_visible.isEmpty) return;
    final i = _highlight;
    final next = i == null ? (step > 0 ? 0 : _visible.length - 1) : (i + step).clamp(0, _visible.length - 1);
    setState(() => _highlight = next);
  }

  void _onTextChanged(String text) {
    widget.onChanged?.call(text);
    if (_choosing) return;
    if (text.trim().isEmpty) {
      _close();
    } else {
      _open(showAll: false);
      setState(() => _highlight = null);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (!_isOpen) {
        _open(showAll: true);
      } else if (!HardwareKeyboard.instance.isAltPressed) {
        _move(1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && _isOpen) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) && _isOpen && _highlight != null) {
      _choose(_highlight!);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _isOpen) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final controlSize = widget.size ?? MacControlSizeScope.of(context);
    final s = MacSizes.of(controlSize);
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final fc = MacFieldColors.of(context);
    final demo = MacDemoStates.maybeOf(context);
    final focused = widget.enabled && (_focus.hasFocus || (demo?.focused ?? false)) && macFocusRingAllowed(context);
    final pressed = widget.enabled && (_pressed || (demo?.pressed ?? false));
    final dark = theme.isDark;
    final textColor = widget.enabled ? c.labelPrimary : c.labelTertiary;
    final style = macFieldTextStyle(context, fontSize: s.globalFontSize, color: textColor);
    final inset = s.comboButtonInset; // 2 · 2 · 2 · 2 · 3
    final buttonFill = !widget.enabled
        ? (dark ? const Color(0x0AFFFFFF) : const Color(0x0A000000))
        : pressed
        ? (dark ? const Color(0x29FFFFFF) : const Color(0x29000000))
        : (dark ? const Color(0x12FFFFFF) : const Color(0x14000000));

    final field = macCupertinoField(
      context,
      controller: _controller,
      focusNode: _focus,
      style: style,
      placeholder: widget.placeholder,
      placeholderStyle: style.copyWith(color: widget.enabled ? c.labelSecondary : c.labelTertiary),
      // Text starts at the field inset and stops "Text - Inset - Right" (20 · 24 · 28 · 28 · 34) before the edge.
      padding: EdgeInsets.only(left: s.fieldsInsetLeft, right: s.comboButtonTextInsetRight - s.comboButtonWidthButton - inset),
      cursorHeight: s.cursorHeight,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      onChanged: _onTextChanged,
      onSubmitted: (v) {
        if (_isOpen && _highlight != null) {
          _choose(_highlight!);
        } else {
          _close();
          widget.onSubmitted?.call(v);
        }
      },
    );

    final button = Semantics(
      button: true,
      label: 'Show Suggestions',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.enabled
            ? () {
                if (_isOpen) {
                  _close();
                } else {
                  _open(showAll: true);
                }
                _focus.requestFocus();
              }
            : null,
        child: Container(
          width: s.comboButtonWidthButton, // 16 · 20 · 24 · 24 · 30
          decoration: BoxDecoration(color: buttonFill, borderRadius: BorderRadius.circular(s.comboButtonRadiusButton)),
          alignment: Alignment.center,
          child: MacGlyph(MacGlyphKind.chevronDownBold, size: s.comboButtonFontSizeChevron * 0.97, color: textColor),
        ),
      ),
    );

    Widget box = CustomPaint(
      painter: MacFieldBezelPainter(
        fill: widget.enabled ? fc.fill : fc.fillDisabled,
        ring: widget.enabled ? fc.ring : fc.ringDisabled,
        focus: focused ? fc.focus : null,
      ),
      child: SizedBox(
        height: s.globalHeight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, inset, inset, inset),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: field),
              button,
            ],
          ),
        ),
      ),
    );
    box = Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: box);

    return Semantics(
      label: widget.semanticLabel,
      expanded: _isOpen,
      child: TapRegion(
        groupId: _tapGroup,
        onTapOutside: (_) => _close(),
        child: CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (overlayContext) => _buildList(context, controlSize),
            child: MacFieldWidth(width: widget.width, fallback: 100, child: box),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, MacControlSize size) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.hasSize == true ? box!.size.width : null;
    // Open upward when there is no room below the field.
    var up = false;
    if (box != null && box.hasSize) {
      final screen = MediaQuery.sizeOf(context);
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      final rows = _visible.length.clamp(0, 8);
      final listH = MacSizes.of(size).menuHeight * rows + 10;
      up = bottom + 4 + listH > screen.height && box.localToGlobal(Offset.zero).dy > listH + 8;
    }
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: up ? Alignment.topLeft : Alignment.bottomLeft,
      followerAnchor: up ? Alignment.bottomLeft : Alignment.topLeft,
      offset: Offset(0, up ? -4 : 4),
      child: Align(
        alignment: up ? Alignment.bottomLeft : Alignment.topLeft,
        child: TapRegion(
          groupId: _tapGroup,
          child: MacPopupList(
            entries: [for (final i in _visible) MacPopupListEntry(widget.items[i])],
            highlighted: _highlight,
            onHighlight: (i) => setState(() => _highlight = i),
            onSelect: _choose,
            width: width,
            size: size,
          ),
        ),
      ),
    );
  }
}
