import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '_text_input.dart';

/// A macOS text field (kit page "Text Fields"): one line of text in the white bezel, 6 px corners,
/// SF Pro Medium, accent focus ring while editing. Height and text size follow the control size
/// (mini 16 · small 20 · medium 24 (default) · large 28 · xl 36).
///
///     final _name = TextEditingController();
///     MacTextField(controller: _name, placeholder: 'Jane Appleseed', onSubmitted: (_) => save())
///     MacTextField(value: email, onChanged: (v) => setState(() => email = v), placeholder: 'name@example.com')
///     MacTextField(obscureText: true, semanticLabel: 'Password')            // secure field
///     MacTextField(value: 'jane@icloud.com', enabled: false)               // disabled
///     MacTextField(size: MacControlSize.small, width: 160)                // small field, fixed width
///
/// Put a label next to it: `MacForm(columns: true, children: [MacFormRow(label: 'Name:', child: MacTextField(...))])`.
/// Width: [width] if given, else the field fills the width it gets (120, the kit width, inside a Row).
class MacTextField extends StatefulWidget {
  const MacTextField({
    super.key,
    this.controller,
    this.value,
    this.onChanged,
    this.onSubmitted,
    this.placeholder,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.focusNode,
    this.width,
    this.size,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.autofillHints,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.semanticLabel,
  });

  /// The text. Leave it null and use [value] + [onChanged] for a controlled field.
  final TextEditingController? controller;

  /// Controlled text (used when [controller] is null): the field shows it and follows its changes.
  final String? value;

  /// Every change of the text.
  final ValueChanged<String>? onChanged;

  /// Return was pressed. The field keeps the focus (macOS); with [textInputAction] next, focus moves on.
  final ValueChanged<String>? onSubmitted;

  /// A hint or example, never the label ("name@example.com", "Optional").
  final String? placeholder;

  /// Secure field: shows dots (passwords).
  final bool obscureText;
  final bool enabled;

  /// Selectable but not editable (looks idle).
  final bool readOnly;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Fixed width. Null = fill the available width (120 when unbounded).
  final double? width;

  /// Control size. Null = the nearest [MacControlSizeScope] (medium by default).
  final MacControlSize? size;
  final TextInputType? keyboardType;

  /// [TextInputAction.next]: Return moves to the next field.
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;

  /// Autofill: [AutofillHints.email], [AutofillHints.password], [AutofillHints.username]…
  final Iterable<String>? autofillHints;
  final int? maxLength;
  final TextAlign textAlign;

  /// Accessible name when no visible label is linked (a [MacFormRow] label is linked automatically).
  final String? semanticLabel;

  @override
  State<MacTextField> createState() => _MacTextFieldState();
}

class _MacTextFieldState extends State<MacTextField> {
  TextEditingController? _own;
  FocusNode? _ownFocus;

  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController(text: widget.value ?? ''));
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'MacTextField'));

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(MacTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
    syncControlledText(widget.controller, old.value, widget.value, _controller);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _own?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MacSizes.of(widget.size ?? MacControlSizeScope.of(context));
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final fc = MacFieldColors.of(context);
    final demo = MacDemoStates.maybeOf(context);
    final focused = widget.enabled && (_focus.hasFocus || (demo?.focused ?? false)) && macFocusRingAllowed(context);
    final textColor = widget.enabled ? c.labelPrimary : c.labelTertiary;
    final style = macFieldTextStyle(context, fontSize: s.globalFontSize, color: textColor);
    final placeholderStyle = style.copyWith(color: widget.enabled ? c.labelSecondary : c.labelTertiary);

    final field = macCupertinoField(
      context,
      controller: _controller,
      focusNode: _focus,
      style: style,
      placeholder: widget.placeholder,
      placeholderStyle: placeholderStyle,
      padding: EdgeInsets.only(left: s.fieldsInsetLeft, right: s.fieldsInsetRight),
      cursorHeight: s.cursorHeight,
      obscureText: widget.obscureText,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      maxLength: widget.maxLength,
      textAlign: widget.textAlign,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      maxLines: 1,
    );

    return Semantics(
      label: widget.semanticLabel,
      child: MacFieldWidth(
        width: widget.width,
        fallback: 120,
        child: CustomPaint(
          painter: MacFieldBezelPainter(
            fill: widget.enabled ? fc.fill : fc.fillDisabled,
            ring: widget.enabled ? fc.ring : fc.ringDisabled,
            focus: focused ? fc.focus : null,
          ),
          child: SizedBox(height: s.globalHeight, child: field),
        ),
      ),
    );
  }
}

/// A multi-line macOS text area (`mac-textarea`): the text-field bezel with body text (Regular 13 / 16).
/// Shows [rows] lines (default 4); more text scrolls. With [maxRows] it grows from [rows] up to [maxRows] lines.
///
///     final _notes = TextEditingController();
///     MacTextArea(controller: _notes, rows: 4, placeholder: 'Optional')
///     MacTextArea(value: bio, onChanged: (v) => setState(() => bio = v), rows: 2, maxRows: 5)   // grows 2…5 lines
///
/// It fills the width it gets (a text view fills its column); set [width] only to make it narrower.
class MacTextArea extends StatefulWidget {
  const MacTextArea({
    super.key,
    this.controller,
    this.value,
    this.onChanged,
    this.placeholder,
    this.rows = 4,
    this.maxRows,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.focusNode,
    this.width,
    this.size,
    this.inputFormatters,
    this.maxLength,
    this.semanticLabel,
  }) : assert(rows >= 1);

  final TextEditingController? controller;

  /// Controlled text (used when [controller] is null).
  final String? value;
  final ValueChanged<String>? onChanged;
  final String? placeholder;

  /// Visible lines (the height).
  final int rows;

  /// Grow up to this many lines before scrolling. Null = always [rows] tall.
  final int? maxRows;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Fixed width. Null = fill the available width (240 when unbounded).
  final double? width;
  final MacControlSize? size;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final String? semanticLabel;

  @override
  State<MacTextArea> createState() => _MacTextAreaState();
}

class _MacTextAreaState extends State<MacTextArea> {
  TextEditingController? _own;
  FocusNode? _ownFocus;

  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController(text: widget.value ?? ''));
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'MacTextArea'));

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(MacTextArea old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
    syncControlledText(widget.controller, old.value, widget.value, _controller);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _own?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = MacSizes.of(widget.size ?? MacControlSizeScope.of(context));
    final c = AppleTheme.of(context).mac;
    final fc = MacFieldColors.of(context);
    final demo = MacDemoStates.maybeOf(context);
    final focused = widget.enabled && (_focus.hasFocus || (demo?.focused ?? false)) && macFocusRingAllowed(context);
    final style = macFieldTextStyle(
      context,
      fontSize: s.globalFontSize,
      color: widget.enabled ? c.labelPrimary : c.labelTertiary,
      weight: FontWeight.w400,
      lineHeight: 16,
    );
    final padV = (s.globalHeight - 16) / 2;

    final field = macCupertinoField(
      context,
      controller: _controller,
      focusNode: _focus,
      style: style,
      placeholder: widget.placeholder,
      placeholderStyle: style.copyWith(color: widget.enabled ? c.labelSecondary : c.labelTertiary),
      padding: EdgeInsets.fromLTRB(s.fieldsInsetLeft, padV, s.fieldsInsetRight, padV),
      cursorHeight: 16,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      inputFormatters: widget.inputFormatters,
      maxLength: widget.maxLength,
      onChanged: widget.onChanged,
      minLines: widget.rows,
      maxLines: widget.maxRows ?? widget.rows,
      alignTop: true,
    );

    return Semantics(
      label: widget.semanticLabel,
      child: MacFieldWidth(
        width: widget.width,
        fallback: 240,
        child: CustomPaint(
          painter: MacFieldBezelPainter(
            fill: widget.enabled ? fc.fill : fc.fillDisabled,
            ring: widget.enabled ? fc.ring : fc.ringDisabled,
            focus: focused ? fc.focus : null,
          ),
          child: field,
        ),
      ),
    );
  }
}
