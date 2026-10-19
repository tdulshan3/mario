import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/macos_tokens.dart';
import '_control_support.dart';

Duration _motion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : const Duration(milliseconds: 200);

/// An on/off switch (kit "Toggles - Switches"): a setting that applies AT ONCE (Wi-Fi, "Show in menu bar").
/// In an OK/Cancel dialog use [MacCheckbox] instead.
///
///     MacSwitch(value: wifi, onChanged: (v) => setState(() => wifi = v), label: 'Wi-Fi')
///     MacSwitch(value: bt, onChanged: (v) => setState(() => bt = v), semanticLabel: 'Bluetooth', size: MacControlSize.mini)
///
/// Off = grey track, knob left; on = accent track, knob right. While pressed the track darkens and the white knob turns
/// light grey (the classic macOS switch).
/// [onChanged] null = disabled (the label dims; a disabled ON switch looks like an enabled one, like the kit).
/// [label] is drawn BEFORE the switch, 8 px away; in a settings row put the text on the left and the switch at the
/// right end instead (mini size, see forms). The window state does not change switches.
class MacSwitch extends StatelessWidget {
  const MacSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.semanticLabel,
    this.size,
    this.focusNode,
    this.autofocus = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Text before the switch. Clicking it toggles the switch too.
  final String? label;

  /// Accessible name when there is no [label].
  final String? semanticLabel;
  final MacControlSize? size;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final look = ControlLook.of(context, size);
    final s = look.s;
    final enabled = onChanged != null;
    final duration = _motion(context);
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: ControlPressable(
        onPressed: enabled ? () => onChanged!(!value) : null,
        focusNode: focusNode,
        autofocus: autofocus,
        builder: (context, state) {
          final w = s.toggleSwitchTrackWidth;
          final h = s.toggleSwitchTrackHeight;
          final pressed = state.pressed;
          final accent = look.accent;
          final Color track;
          if (value) {
            track = pressed ? controlMix(accent, 0.92, look.dark ? controlWhiteSolid : controlBlackSolid) : accent;
          } else {
            track = !enabled
                ? look.ld(controlBlack(0.05), controlWhite(0.05))
                : pressed
                    ? look.ld(controlBlack(0.16), controlWhite(0.16))
                    : look.ld(controlBlack(0.085), controlWhite(0.085));
          }
          final knobW = s.toggleSwitchKnobWidth;
          final knobH = s.toggleSwitchKnobHeight;
          final inset = s.toggleSwitchKnobInset;
          final left = value ? w - knobW - inset : inset;
          Widget sw = SizedBox(
            width: w,
            height: h,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: track),
                  duration: duration,
                  curve: Curves.ease,
                  builder: (context, color, _) =>
                      ControlBox(color: color ?? track, radius: h / 2, focusRing: state.focused ? look.focusColor : null),
                ),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: Curves.ease,
                left: left,
                top: (h - knobH) / 2,
                width: knobW,
                height: knobH,
                child: ControlKnob(
                  width: knobW,
                  height: knobH,
                  shadow: ControlShadow(0, 3, 36, 0, controlBlack(0.05)),
                  color: pressed ? controlKnobPressed : controlWhiteSolid,
                ),
              ),
            ]),
          );
          if (label == null) return sw;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label!, style: look.text(s.globalFontSize, enabled ? look.c.labelPrimary : look.c.labelTertiary, lineHeight: 16)),
            const SizedBox(width: 8),
            sw,
          ]);
        },
      ),
    );
  }
}

/// A checkbox (kit "Toggles - Checkboxes"): an option that is applied with OK/Save, or one of several independent options.
///
///     MacCheckbox(value: showHidden, onChanged: (v) => setState(() => showHidden = v), label: 'Show hidden files')
///     MacCheckbox(value: null, onChanged: (v) => setAll(v), label: 'All media')   // mixed (some children on)
///
/// [value] null = mixed (a dash). Clicking a mixed checkbox calls [onChanged] with true.
/// [onChanged] null = disabled (the label dims too). The label sits to the right, 3 px away (5 at large, 7 at XL),
/// SF Pro Medium. Inactive window ([MacWindowState]): the accent turns grey.
class MacCheckbox extends StatelessWidget {
  const MacCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.semanticLabel,
    this.size,
    this.focusNode,
    this.autofocus = false,
  });

  /// true = on, false = off, null = mixed.
  final bool? value;
  final ValueChanged<bool>? onChanged;

  /// Text after the box (sentence case, no end punctuation). Clicking it toggles the box.
  final String? label;

  /// Accessible name when there is no [label].
  final String? semanticLabel;
  final MacControlSize? size;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final look = ControlLook.of(context, size);
    final enabled = onChanged != null;
    return Semantics(
      checked: value ?? false,
      mixed: value == null,
      enabled: enabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: ControlPressable(
        onPressed: enabled ? () => onChanged!(value != true) : null,
        focusNode: focusNode,
        autofocus: autofocus,
        builder: (context, state) => _ToggleRow(
          look: look,
          label: label,
          enabled: enabled,
          box: _CheckGlyphBox(look: look, radio: false, value: value, enabled: enabled, state: state),
        ),
      ),
    );
  }
}

/// A group of radio buttons (kit "Toggles - Radio Buttons"): exactly one of 2–5 choices that are all visible.
///
///     MacRadioGroup<String>(
///       options: const ['Automatic', 'Light', 'Dark'],
///       value: appearance,
///       onChanged: (v) => setState(() => appearance = v),
///       semanticLabel: 'Appearance',
///     )
///     MacRadioGroup<Sort>(options: Sort.values, value: sort, labelOf: (s) => s.title, horizontal: true, onChanged: …)
///
/// A column 8 px apart, or a row 16 px apart ([horizontal], for 2–3 short choices). Always preselect one option.
/// [onChanged] null = the whole group disabled; [disabled] disables single options. Tab moves into the group (to the
/// chosen option), the arrow keys move the choice. [mixed] options show a dash (several selected objects disagree).
class MacRadioGroup<T> extends StatefulWidget {
  const MacRadioGroup({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelOf,
    this.disabled = const {},
    this.mixed = const {},
    this.horizontal = false,
    this.semanticLabel,
    this.size,
  });

  final List<T> options;

  /// The chosen option (null = none, only while nothing applies).
  final T? value;
  final ValueChanged<T>? onChanged;

  /// The text of an option. Default: `option.toString()`.
  final String Function(T option)? labelOf;
  final Set<T> disabled;
  final Set<T> mixed;
  final bool horizontal;

  /// Accessible name of the group ("Appearance").
  final String? semanticLabel;
  final MacControlSize? size;

  @override
  State<MacRadioGroup<T>> createState() => _MacRadioGroupState<T>();
}

class _MacRadioGroupState<T> extends State<MacRadioGroup<T>> {
  final List<FocusNode> _nodes = [];

  void _syncNodes() {
    while (_nodes.length < widget.options.length) {
      _nodes.add(FocusNode(debugLabel: 'MacRadio ${_nodes.length}'));
    }
    while (_nodes.length > widget.options.length) {
      _nodes.removeLast().dispose();
    }
    final value = widget.value;
    final chosen = value == null ? -1 : widget.options.indexOf(value);
    for (var i = 0; i < _nodes.length; i++) {
      // Only the chosen option (or the first, if none) is a Tab stop; arrows move inside the group.
      _nodes[i].skipTraversal = chosen >= 0 ? i != chosen : i != 0;
    }
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  bool _enabled(int i) => widget.onChanged != null && !widget.disabled.contains(widget.options[i]);

  KeyEventResult _onKey(int i, KeyEvent e) {
    int dir = 0;
    if (controlKey(e, LogicalKeyboardKey.arrowDown) || controlKey(e, LogicalKeyboardKey.arrowRight)) dir = 1;
    if (controlKey(e, LogicalKeyboardKey.arrowUp) || controlKey(e, LogicalKeyboardKey.arrowLeft)) dir = -1;
    if (dir == 0) return KeyEventResult.ignored;
    final n = widget.options.length;
    for (var step = 1; step < n; step++) {
      final j = (i + dir * step) % n;
      final k = j < 0 ? j + n : j;
      if (_enabled(k)) {
        widget.onChanged!(widget.options[k]);
        _nodes[k].requestFocus();
        break;
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    _syncNodes();
    final look = ControlLook.of(context, widget.size);
    final items = <Widget>[];
    for (var i = 0; i < widget.options.length; i++) {
      final option = widget.options[i];
      final enabled = _enabled(i);
      final selected = option == widget.value;
      final isMixed = widget.mixed.contains(option);
      final text = widget.labelOf?.call(option) ?? '$option';
      items.add(Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        mixed: isMixed,
        enabled: enabled,
        label: text,
        excludeSemantics: true,
        child: ControlPressable(
          onPressed: enabled ? () => widget.onChanged!(option) : null,
          focusNode: _nodes[i],
          onKeyEvent: (node, e) => _onKey(i, e),
          builder: (context, state) => _ToggleRow(
            look: look,
            label: text,
            enabled: enabled,
            box: _CheckGlyphBox(look: look, radio: true, value: isMixed ? null : selected, enabled: enabled, state: state),
          ),
        ),
      ));
    }
    final group = widget.horizontal
        ? Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: items)
        : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: items);
    return Semantics(container: true, label: widget.semanticLabel, explicitChildNodes: true, child: group);
  }
}

/// Box/circle + label, like a `<label>` around a toggle (toggles.css).
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.look, required this.label, required this.enabled, required this.box});
  final ControlLook look;
  final String? label;
  final bool enabled;
  final Widget box;

  @override
  Widget build(BuildContext context) {
    if (label == null) return box;
    final s = look.s;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      box,
      SizedBox(width: s.radioButtonSpacing),
      Text(label!, style: look.text(s.globalFontSize, enabled ? look.c.labelPrimary : look.c.labelTertiary, lineHeight: 16)),
    ]);
  }
}

/// The checkbox square or radio circle with its glyph (checkmark, dot, or mixed dash).
class _CheckGlyphBox extends StatelessWidget {
  const _CheckGlyphBox({required this.look, required this.radio, required this.value, required this.enabled, required this.state});
  final ControlLook look;
  final bool radio;

  /// true = on, false = off, null = mixed.
  final bool? value;
  final bool enabled;
  final ControlState state;

  @override
  Widget build(BuildContext context) {
    final s = look.s;
    final dark = look.dark;
    final accent = look.accent;
    final on = value != false;
    final pressed = state.pressed;

    // toggles.css colours (Light | Dark), then the inactive-window overrides.
    final off = look.ld(controlBlack(0.10), controlWhite(0.10));
    final offPressed = look.ld(controlBlack(0.19), controlWhite(0.19));
    var offDisabled = look.ld(controlBlack(0.05), controlWhite(0.05));
    var onIdle = dark ? controlMix(accent, 0.95, controlWhiteSolid) : accent;
    var onPressed = dark ? controlMix(accent, 0.92, controlWhiteSolid) : controlMix(accent, 0.90, controlBlackSolid);
    var onDisabled = dark
        ? controlFade(controlMix(accent, 0.98, controlWhiteSolid), 0.45)
        : controlFade(controlMix(accent, 0.95, controlBlackSolid), 0.45);
    var glyph = controlWhiteSolid;
    var glyphDisabled = controlWhite(0.5);
    if (look.inactive) {
      if (radio) {
        onIdle = off;
        onPressed = offPressed;
        onDisabled = offDisabled;
      } else {
        onIdle = look.ld(controlBlack(0.14), controlWhite(0.10));
        onPressed = look.ld(controlBlack(0.18), controlWhite(0.19));
        onDisabled = look.ld(controlBlack(0.05), controlWhite(0.03));
        offDisabled = look.ld(controlBlack(0.05), controlWhite(0.03));
      }
      glyph = look.ld(controlBlack(0.70), controlWhiteSolid);
      glyphDisabled = look.ld(controlBlack(0.22), controlWhite(0.22));
    }
    final Color fill;
    if (!enabled) {
      fill = on ? onDisabled : offDisabled;
    } else if (on) {
      fill = pressed ? onPressed : onIdle;
    } else {
      fill = pressed ? offPressed : off;
    }
    final mark = enabled ? glyph : glyphDisabled;

    final side = radio ? s.radioButtonWidth : s.checkboxesWidth;
    final radius = radio ? side / 2 : s.checkboxesRadius;
    Widget? glyphWidget;
    if (value == null) {
      glyphWidget = Container(
        width: s.radioButtonWidthDash,
        height: s.radioButtonHeightDash,
        decoration: ShapeDecoration(color: mark, shape: const StadiumBorder()),
      );
    } else if (value!) {
      glyphWidget = radio
          ? Container(
              width: s.radioButtonWidthDot,
              height: s.radioButtonWidthDot,
              decoration: ShapeDecoration(color: mark, shape: const CircleBorder()),
            )
          : ControlGlyph(
              lines: ControlGlyph.checkmark,
              viewBox: const Size(9.31, 8.93),
              strokeWidth: 1.75,
              color: mark,
              width: s.checkboxesWidthCheckmark,
              height: s.checkboxesHeightCheckmark,
            );
    }
    return ControlBox(
      color: fill,
      radius: radius,
      focusRing: state.focused ? look.focusColor : null,
      child: SizedBox(
        width: side,
        height: side,
        child: glyphWidget == null ? null : Center(child: glyphWidget),
      ),
    );
  }
}
