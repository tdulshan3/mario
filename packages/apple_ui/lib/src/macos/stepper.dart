import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/macos_tokens.dart';
import '_control_support.dart';

/// Where the number field of a [MacStepper] goes (kit sets "Stepper/Outside Field", "Inside Field", "No Field").
enum MacStepperField {
  /// A number field with the stepper 4 px to its right: the macOS standard.
  outside,

  /// The stepper is the right end of the field (compact).
  inside,

  /// The stepper alone: show the value somewhere else ("Zoom 125%").
  none,
}

/// A stepper: up/down arrows that add or subtract [step], usually with a number field (kit page "Steppers").
///
///     MacStepper(value: copies, min: 1, max: 99, onChanged: (v) => setState(() => copies = v), semanticLabel: 'Copies')
///     MacStepper(value: opacity, min: 0, max: 100, field: MacStepperField.inside, onChanged: …, semanticLabel: 'Opacity')
///     MacStepper(value: zoom, min: 25, max: 400, step: 25, field: MacStepperField.none, onChanged: …, semanticLabel: 'Zoom')
///
/// [onChanged] null = disabled (field and both arrows). The value stops at [min]/[max]; the arrows stay enabled.
/// Holding an arrow repeats (after 400 ms, every 80 ms). In the field, typing sets the value (on Return or when the field
/// loses focus) and the Up/Down arrow keys step it; the arrow buttons beside a field are not Tab stops.
/// The field is 1.75 × the control height wide (42 at medium) unless [fieldWidth] is set. No hover effect.
class MacStepper extends StatefulWidget {
  const MacStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = double.negativeInfinity,
    this.max = double.infinity,
    this.step = 1,
    this.field = MacStepperField.outside,
    this.fieldWidth,
    this.semanticLabel,
    this.size,
    this.focusNode,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final double step;
  final MacStepperField field;

  /// Width of the field's text area (default 1.75 × the control height: 28 · 35 · 42 · 49 · 63).
  final double? fieldWidth;

  /// Accessible name ("Copies").
  final String? semanticLabel;
  final MacControlSize? size;

  /// Focus node of the number field.
  final FocusNode? focusNode;

  @override
  State<MacStepper> createState() => _MacStepperState();
}

class _MacStepperState extends State<MacStepper> {
  final _controller = TextEditingController();
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'MacStepper field'));
  bool _editing = false;
  int _pressed = 0; // 1 = up, -1 = down
  Timer? _repeat;

  bool get _enabled => widget.onChanged != null;

  int get _decimals {
    final text = widget.step.toString();
    if (text.contains('e')) return 6;
    final dot = text.indexOf('.');
    if (dot < 0) return 0;
    final frac = text.substring(dot + 1);
    return frac == '0' ? 0 : frac.length;
  }

  String _format(double v) => v.toStringAsFixed(_decimals);

  double _clamp(double v) => double.parse(v.clamp(widget.min, widget.max).toStringAsFixed(_decimals));

  @override
  void initState() {
    super.initState();
    _controller.text = _format(widget.value);
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(MacStepper old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownNode)?.removeListener(_onFocus);
      _node.addListener(_onFocus);
    }
    if (!_editing && _controller.text != _format(widget.value)) _controller.text = _format(widget.value);
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _node.removeListener(_onFocus);
    _ownNode?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_node.hasFocus) _commit();
    setState(() {});
  }

  void _commit() {
    _editing = false;
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed != null && _enabled) {
      final v = _clamp(parsed);
      if (v != widget.value) widget.onChanged!(v);
      _controller.text = _format(v);
    } else {
      _controller.text = _format(widget.value);
    }
  }

  void _bump(int dir) {
    if (!_enabled) return;
    final next = _clamp(widget.value + dir * widget.step);
    _editing = false;
    // The field shows widget.value: it updates when the parent rebuilds with the new value (didUpdateWidget).
    if (_controller.text != _format(widget.value)) _controller.text = _format(widget.value);
    if (next != widget.value) widget.onChanged!(next);
  }

  void _down(int dir) {
    setState(() => _pressed = dir);
    _bump(dir);
    _repeat?.cancel();
    _repeat = Timer(const Duration(milliseconds: 400), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 80), (_) => _bump(dir));
    });
  }

  void _up() {
    _repeat?.cancel();
    _repeat = null;
    if (_pressed != 0) setState(() => _pressed = 0);
  }

  KeyEventResult _fieldKey(FocusNode node, KeyEvent e) {
    if (controlKey(e, LogicalKeyboardKey.arrowUp)) {
      _bump(1);
      return KeyEventResult.handled;
    }
    if (controlKey(e, LogicalKeyboardKey.arrowDown)) {
      _bump(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final look = ControlLook.of(context, widget.size);
    final s = look.s;
    final h = s.globalHeight;
    final field = widget.field;
    final stepperW = s.stepperWidth;
    final textW = widget.fieldWidth ?? h * 1.75;
    const fieldRadius = 6.0;

    final stepper = _StepperArrows(
      look: look,
      enabled: _enabled,
      pressed: _pressed,
      focusable: field == MacStepperField.none,
      inside: field == MacStepperField.inside,
      fieldRadius: fieldRadius,
      onDown: _down,
      onUp: _up,
      onStep: _bump,
    );

    if (field == MacStepperField.none) {
      return Semantics(container: true, label: widget.semanticLabel, child: SizedBox(width: stepperW, height: h, child: stepper));
    }

    final focused = _node.hasFocus && !look.inactive;
    final fieldFill = _enabled ? look.ld(controlWhiteSolid, const Color(0xFF1E1E1E)) : look.ld(controlWhite(0.5), const Color(0x801E1E1E));
    final ring = _enabled ? look.ld(controlBlack(0.08), controlWhite(0.04)) : look.ld(controlBlack(0.04), controlWhite(0.04));
    final focusColor = controlFade(look.accent, 0.5);
    final textColor = _enabled ? look.c.labelPrimary : look.c.labelTertiary;

    final input = Padding(
      padding: EdgeInsets.only(left: s.fieldsInsetLeft, right: s.fieldsInsetRight),
      child: Center(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _fieldKey,
          child: EditableText(
            controller: _controller,
            focusNode: _node,
            readOnly: !_enabled,
            enableInteractiveSelection: _enabled,
            style: look.text(s.globalFontSize, textColor, lineHeight: 16).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            textAlign: TextAlign.center,
            cursorColor: look.accent,
            cursorWidth: 1,
            backgroundCursorColor: look.c.labelTertiary,
            selectionColor: controlFade(look.accent, 0.28),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
            maxLines: 1,
            onChanged: (_) => _editing = true,
            onSubmitted: (_) => setState(_commit),
            mouseCursor: _enabled ? SystemMouseCursors.text : SystemMouseCursors.basic,
          ),
        ),
      ),
    );

    Widget fieldBox(Widget child, double width, {required bool focusRing}) => CustomPaint(
          painter: _FieldPainter(fill: fieldFill, ring: ring, radius: fieldRadius, focus: focusRing ? focusColor : null),
          child: SizedBox(width: width, height: h, child: child),
        );

    final Widget body;
    if (field == MacStepperField.inside) {
      body = fieldBox(
        Row(children: [Expanded(child: input), SizedBox(width: stepperW, height: h, child: stepper)]),
        textW + stepperW,
        focusRing: focused,
      );
    } else {
      body = Row(mainAxisSize: MainAxisSize.min, children: [
        fieldBox(input, textW, focusRing: focused),
        const SizedBox(width: 4),
        SizedBox(width: stepperW, height: h, child: stepper),
      ]);
    }
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      value: _format(widget.value),
      increasedValue: _format(_clamp(widget.value + widget.step)),
      decreasedValue: _format(_clamp(widget.value - widget.step)),
      enabled: _enabled,
      onIncrease: _enabled ? () => _bump(1) : null,
      onDecrease: _enabled ? () => _bump(-1) : null,
      child: body,
    );
  }
}

/// The two arrow halves and the separator (steppers.css).
class _StepperArrows extends StatelessWidget {
  const _StepperArrows({
    required this.look,
    required this.enabled,
    required this.pressed,
    required this.focusable,
    required this.inside,
    required this.fieldRadius,
    required this.onDown,
    required this.onUp,
    required this.onStep,
  });
  final ControlLook look;
  final bool enabled;
  final int pressed;
  final bool focusable;
  final bool inside;
  final double fieldRadius;
  final void Function(int dir) onDown;
  final VoidCallback onUp;
  final void Function(int dir) onStep;

  @override
  Widget build(BuildContext context) {
    final s = look.s;
    final r = s.stepperRadius;
    Widget half(int dir) {
      final isUp = dir == 1;
      return Expanded(
        child: Semantics(
          button: true,
          enabled: enabled,
          label: isUp ? 'Increase' : 'Decrease',
          excludeSemantics: true,
          child: FocusableActionDetector(
            enabled: enabled && focusable,
            mouseCursor: SystemMouseCursors.basic,
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
                onStep(dir);
                return null;
              }),
            },
            child: Builder(builder: (context) {
              final focused = focusable && Focus.of(context).hasPrimaryFocus &&
                  FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
              final fill = !enabled
                  ? look.borderedFillDisabled
                  : (pressed == dir ? look.borderedFillPressed : look.borderedFill);
              final corner = inside ? 0.0 : r;
              final outer = inside ? fieldRadius : r;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: enabled ? (_) => onDown(dir) : null,
                onTapUp: enabled ? (_) => onUp() : null,
                onTapCancel: enabled ? onUp : null,
                child: CustomPaint(
                  painter: _HalfPainter(
                    fill: fill,
                    up: isUp,
                    leftRadius: corner,
                    rightRadius: outer,
                    focus: focused ? look.focusColor : null,
                  ),
                  child: Center(
                    child: ControlGlyph(
                      lines: isUp ? ControlGlyph.stepperUp : ControlGlyph.stepperDown,
                      viewBox: const Size(10.5, 6),
                      strokeWidth: 1.5,
                      color: enabled ? look.c.labelPrimary : look.c.labelTertiary,
                      width: s.stepperFontSize * 0.875,
                      height: s.stepperFontSize * 0.5,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      );
    }

    return Stack(children: [
      Column(children: [half(1), half(-1)]),
      Center(
        child: IgnorePointer(
          child: Container(
            width: s.stepperWidthSeparator,
            height: 1,
            decoration: BoxDecoration(
              color: enabled ? controlBlack(0.12) : controlBlack(0.06),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _HalfPainter extends CustomPainter {
  _HalfPainter({required this.fill, required this.up, required this.leftRadius, required this.rightRadius, required this.focus});
  final Color fill;
  final bool up;
  final double leftRadius;
  final double rightRadius;
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = up
        ? controlShapeCorners(rect, topLeft: leftRadius, topRight: rightRadius)
        : controlShapeCorners(rect, bottomLeft: leftRadius, bottomRight: rightRadius);
    canvas.drawPath(path, Paint()..color = fill);
    if (focus != null) {
      final outer = up
          ? controlShapeCorners(rect.inflate(3.5), topLeft: leftRadius + 3.5, topRight: rightRadius + 3.5, bottomLeft: 3.5, bottomRight: 3.5)
          : controlShapeCorners(rect.inflate(3.5), bottomLeft: leftRadius + 3.5, bottomRight: rightRadius + 3.5, topLeft: 3.5, topRight: 3.5);
      canvas.drawPath(Path.combine(PathOperation.difference, outer, path), Paint()..color = focus!);
    }
  }

  @override
  bool shouldRepaint(_HalfPainter old) =>
      old.fill != fill || old.up != up || old.leftRadius != leftRadius || old.rightRadius != rightRadius || old.focus != focus;
}

/// The number field: white (dark #1E1E1E) with a 1 px ring; while editing an accent ring 3.5 px outside + 1 px inside.
class _FieldPainter extends CustomPainter {
  _FieldPainter({required this.fill, required this.ring, required this.radius, required this.focus});
  final Color fill;
  final Color ring;
  final double radius;
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = controlShape(rect, radius);
    // box-shadow: 0 0 0 1px ring (outside), drawn first so the field covers its inner edge.
    canvas.drawPath(controlShape(rect.inflate(1), radius + 1), Paint()..color = ring);
    canvas.drawPath(shape, Paint()..color = fill);
    if (focus != null) {
      final outer = controlShape(rect.inflate(3.5), math.min(radius + 3.5, rect.inflate(3.5).shortestSide / 2));
      canvas.drawPath(Path.combine(PathOperation.difference, outer, shape), Paint()..color = focus!);
      final inner = controlShape(rect.deflate(1), math.max(0, radius - 1));
      canvas.drawPath(Path.combine(PathOperation.difference, shape, inner), Paint()..color = focus!);
    }
  }

  @override
  bool shouldRepaint(_FieldPainter old) => old.fill != fill || old.ring != ring || old.radius != radius || old.focus != focus;
}
