import 'package:flutter/cupertino.dart' show CupertinoTextField, OverlayVisibilityMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/glass.dart';
import '../core/icons.dart';
import '../core/theme.dart';
import '../core/typography.dart';

/// When the clear button (xmark.circle.fill) of an [IosTextField] shows.
enum IosClearButtonMode {
  /// While the field is being edited and has text (iOS forms). The default.
  whileEditing,

  /// Whenever the field has text.
  always,

  /// Never.
  never,
}

/// Text 17 Medium like the kit's fields ("Text Field", "_Search").
TextStyle _fieldText(BuildContext context, Color color) {
  final t = IosTypography.of(context).body;
  return t.copyWith(fontWeight: FontWeight.w500, color: color);
}

/// The clear button: xmark.circle.fill 17 pt, a 20 pt box, 44 pt tap area.
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.color, required this.onPressed});
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Clear text',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 32,
          height: 44,
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: 20, height: 20, child: Icon(AppleIcons.xmarkCircleFill, size: 18, color: color)),
          ),
        ),
      ),
    );
  }
}

/// An iOS text field: one 52 pt row of a form (kit "Text Field"). Text 17 Medium, placeholder in the tertiary label
/// colour, an accent caret and a clear button while you type. Put several in an [IosTextFieldGroup] (or in list rows).
///
///     IosTextField(placeholder: 'Name', controller: name)
///     IosTextField(placeholder: 'Password', obscureText: true)                  // secure field
///     IosTextField(placeholder: 'Email', keyboardType: TextInputType.emailAddress, onSubmitted: (_) => next())
class IosTextField extends StatefulWidget {
  const IosTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.clearButtonMode = IosClearButtonMode.whileEditing,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.autofillHints = const <String>[],
    this.inputFormatters,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Grey text shown while the field is empty. Also its accessible name unless [semanticLabel] is set.
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Dots instead of letters (iOS SecureField). The clear button is then never shown.
  final bool obscureText;
  final IosClearButtonMode clearButtonMode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final Iterable<String> autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  /// false = disabled: tertiary text, not editable.
  final bool enabled;
  final bool autofocus;

  /// Accessible name when the placeholder is not enough.
  final String? semanticLabel;

  @override
  State<IosTextField> createState() => _IosTextFieldState();
}

class _IosTextFieldState extends State<IosTextField> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  TextEditingController get _controller => widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(IosTextField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_rebuild);
      _controller.addListener(_rebuild);
    }
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_rebuild);
      _focus.addListener(_rebuild);
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    _focus.removeListener(_rebuild);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  bool get _showClear {
    if (!widget.enabled || widget.obscureText || _controller.text.isEmpty) return false;
    return switch (widget.clearButtonMode) {
      IosClearButtonMode.whileEditing => _focus.hasFocus,
      IosClearButtonMode.always => true,
      IosClearButtonMode.never => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final style = _fieldText(context, widget.enabled ? c.labelPrimary : c.labelTertiary);
    return Semantics(
      textField: true,
      label: widget.semanticLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          // Kit: padding 0/16; the text sits below the 1 pt separator line.
          padding: const EdgeInsets.fromLTRB(16, 1, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: CupertinoTextField.borderless(
                  decoration: const BoxDecoration(), // no box, also when disabled
                  controller: _controller,
                  focusNode: _focus,
                  padding: EdgeInsets.zero,
                  placeholder: widget.placeholder,
                  placeholderStyle: style.copyWith(color: c.labelTertiary),
                  style: style,
                  obscureText: widget.obscureText,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  textCapitalization: widget.textCapitalization,
                  autocorrect: widget.autocorrect,
                  autofillHints: widget.autofillHints,
                  inputFormatters: widget.inputFormatters,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  cursorColor: theme.accentColor,
                  cursorWidth: 2,
                  cursorHeight: 22,
                  cursorRadius: const Radius.circular(1),
                  keyboardAppearance: theme.isDark ? Brightness.dark : Brightness.light,
                  clearButtonMode: OverlayVisibilityMode.never,
                ),
              ),
              if (_showClear)
                _ClearButton(
                  color: c.labelTertiary,
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged?.call('');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Multi-line text (iOS TextEditor / TextField(axis: .vertical)) with the text-field row look. Grows with its text
/// between [minLines] and [maxLines] (null = no limit).
///
///     IosTextView(placeholder: 'Notes', controller: notes, minLines: 3)
class IosTextView extends StatelessWidget {
  const IosTextView({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.onChanged,
    this.minLines = 1,
    this.maxLines,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int? maxLines;
  final bool enabled;
  final bool autofocus;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final style = _fieldText(context, enabled ? c.labelPrimary : c.labelTertiary);
    return Semantics(
      textField: true,
      label: semanticLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          child: CupertinoTextField.borderless(
            decoration: const BoxDecoration(), // no box, also when disabled
            controller: controller,
            focusNode: focusNode,
            padding: EdgeInsets.zero,
            placeholder: placeholder,
            placeholderStyle: style.copyWith(color: c.labelTertiary),
            style: style,
            minLines: minLines,
            maxLines: maxLines,
            keyboardType: TextInputType.multiline,
            enabled: enabled,
            autofocus: autofocus,
            onChanged: onChanged,
            cursorColor: theme.accentColor,
            cursorWidth: 2,
            cursorRadius: const Radius.circular(1),
            keyboardAppearance: theme.isDark ? Brightness.dark : Brightness.light,
          ),
        ),
      ),
    );
  }
}

/// A card of text fields (kit "Grouped Table View": radius 26, grouped secondary background) with a separator
/// (Separators/Vibrant, inset 16 on both sides) between the fields.
///
///     IosTextFieldGroup(children: [IosTextField(placeholder: 'First Name'), IosTextField(placeholder: 'Last Name')])
class IosTextFieldGroup extends StatelessWidget {
  const IosTextFieldGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    // Separators/Vibrant drawn plus-darker (#E6E6E6) / plus-lighter (#1A1A1A) = black 9.8 % / white 10.2 %.
    final separator = theme.isDark ? const Color(0x1AFFFFFF) : const Color(0x19000000);
    return ClipPath(
      clipper: const ShapeBorderClipper(shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(26)))),
      child: ColoredBox(
        color: theme.ios.groupedBgSecondary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++)
              if (i == 0)
                children[i]
              else
                Stack(
                  children: [
                    children[i],
                    Positioned(top: 0, left: 16, right: 16, height: 1, child: ColoredBox(color: separator)),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

/// Search field size: [regular] 48 tall (iPhone bottom toolbar, tab bar search) · [small] 44 tall (iPad top toolbar).
enum IosSearchFieldSize { regular, small }

/// The search field of toolbars and tab bars on the Regular blur material (kit "_Search - 48pt" / "_Search - 44pt"):
/// magnifying glass, text 17 Medium, a microphone when [onDictate] is set, a clear button while you type.
///
///     IosSearchField(controller: query, onSubmitted: search)
///     IosSearchField(size: IosSearchFieldSize.small, placeholder: 'Search')   // iPad top toolbar, 190–260 wide
class IosSearchField extends StatefulWidget {
  const IosSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onDictate,
    this.size = IosSearchFieldSize.regular,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel = 'Search',
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Shows the microphone (dictation) button; called when it is tapped.
  final VoidCallback? onDictate;
  final IosSearchFieldSize size;
  final bool enabled;
  final bool autofocus;
  final String semanticLabel;

  @override
  State<IosSearchField> createState() => _IosSearchFieldState();
}

class _IosSearchFieldState extends State<IosSearchField> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  TextEditingController get _controller => widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(IosSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_rebuild);
      _controller.addListener(_rebuild);
    }
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_rebuild);
      _focus.addListener(_rebuild);
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    _focus.removeListener(_rebuild);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    // Labels - Vibrant - Controls. Dark: the kit draws them plus-lighter over the dark material (= #5A5A5A / #A4A4A4).
    final label = widget.enabled ? c.labelControlPrimary : c.labelControlTertiary;
    final placeholder = theme.isDark ? const Color(0xFF5A5A5A) : c.labelControlTertiary;
    final symbol = theme.isDark ? const Color(0xFFA4A4A4) : c.labelControlSecondary;
    final style = appleFont(size: 17).copyWith(
      fontSize: 17,
      height: 20 / 17,
      letterSpacing: -0.43,
      fontWeight: FontWeight.w500,
      color: label,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: TextDecoration.none,
    );
    final typing = _focus.hasFocus && _controller.text.isNotEmpty;
    final height = widget.size == IosSearchFieldSize.small ? 44.0 : 48.0;
    return Semantics(
      textField: true,
      label: widget.semanticLabel,
      child: AppleGlass(
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.only(left: 11, right: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  height: 20,
                  // magnifyingglass 17 Medium (drawn about 21 pt, like the SF Symbol).
                  child: OverflowBox(maxWidth: 26, maxHeight: 26, child: Icon(AppleIcons.magnifyingglass, size: 25, color: label)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: CupertinoTextField.borderless(
                    decoration: const BoxDecoration(), // no box, also when disabled
                    controller: _controller,
                    focusNode: _focus,
                    padding: EdgeInsets.zero,
                    placeholder: widget.placeholder,
                    placeholderStyle: style.copyWith(color: placeholder),
                    style: style,
                    textInputAction: TextInputAction.search,
                    enabled: widget.enabled,
                    autofocus: widget.autofocus,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    cursorColor: theme.accentColor,
                    cursorWidth: 2,
                    cursorHeight: 22,
                    cursorRadius: const Radius.circular(1),
                    keyboardAppearance: theme.isDark ? Brightness.dark : Brightness.light,
                  ),
                ),
                if (typing)
                  _ClearButton(
                    color: symbol,
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged?.call('');
                    },
                  )
                else if (widget.onDictate != null) ...[
                  const SizedBox(width: 4),
                  Semantics(
                    button: true,
                    label: 'Dictate',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.enabled ? widget.onDictate : null,
                      child: SizedBox(
                        width: 18,
                        height: 44,
                        child: Center(child: Icon(AppleIcons.mic, size: 20, color: symbol)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
