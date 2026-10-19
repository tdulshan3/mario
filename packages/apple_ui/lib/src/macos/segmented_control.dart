import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '_control_support.dart';

/// One segment of a [MacSegmentedControl]: a short title-case [label] OR an [icon] (never mixed within one control).
///
///     MacSegment(value: 'week', label: 'Week')
///     MacSegment(value: ViewMode.list, icon: AppleIcons.listBullet, semanticLabel: 'List')
@immutable
class MacSegment<T> {
  const MacSegment({required this.value, this.label, this.icon, this.semanticLabel, this.enabled = true})
      : assert(label != null || icon != null, 'A segment needs a label or an icon');

  final T value;
  final String? label;
  final IconData? icon;

  /// Accessible name (and what a tooltip would say). Required for icon segments.
  final String? semanticLabel;

  /// False = this segment is disabled.
  final bool enabled;
}

enum _Mode { single, multiple, momentary }

/// A segmented control (kit page "Segmented Controls"): 2–5 joined segments.
///
///     // Single choice (a view switcher): the selected segment turns accent-coloured.
///     MacSegmentedControl<String>(
///       segments: const [MacSegment(value: 'day', label: 'Day'), MacSegment(value: 'week', label: 'Week')],
///       value: scope,
///       onChanged: (v) => setState(() => scope = v),
///       semanticLabel: 'Scope',
///     )
///     // Several on/off options (Bold · Italic · Underline):
///     MacSegmentedControl<String>.multiple(segments: …, values: styles, onChanged: (s) => setState(() => styles = s))
///     // One-shot commands (‹ · ›): every segment is a push button and stays unselected.
///     MacSegmentedControl<String>.momentary(segments: …, onPressed: (v) => v == 'back' ? goBack() : goForward())
///
/// [equal] makes every segment as wide as the widest (and lets the control stretch when its width is forced).
/// [toolbar] = the toolbar version: a material capsule with a grey selected pill (use icons; medium or XL size).
/// A null callback disables the whole control; [MacSegment.enabled] disables one segment. Inactive window:
/// the selected segment turns grey. No hover effect except in the toolbar version. Single choice: Tab moves to the
/// selected segment, the arrow keys move the selection.
class MacSegmentedControl<T> extends StatefulWidget {
  const MacSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.equal = false,
    this.toolbar = false,
    this.semanticLabel,
    this.size,
  })  : _mode = _Mode.single,
        values = null,
        onValuesChanged = null,
        onPressed = null;

  /// Multiple selection: each segment turns on and off by itself.
  const MacSegmentedControl.multiple({
    super.key,
    required this.segments,
    required Set<T> this.values,
    required ValueChanged<Set<T>>? onChanged,
    this.equal = false,
    this.toolbar = false,
    this.semanticLabel,
    this.size,
  })  : _mode = _Mode.multiple,
        value = null,
        onChanged = null,
        onValuesChanged = onChanged,
        onPressed = null;

  /// Momentary: every segment is a push button (kit "_Segment - Not selectable").
  const MacSegmentedControl.momentary({
    super.key,
    required this.segments,
    required this.onPressed,
    this.equal = false,
    this.toolbar = false,
    this.semanticLabel,
    this.size,
  })  : _mode = _Mode.momentary,
        value = null,
        values = null,
        onChanged = null,
        onValuesChanged = null;

  final List<MacSegment<T>> segments;

  /// Single choice: the selected segment's value.
  final T? value;

  /// Single choice: called with the newly selected value.
  final ValueChanged<T>? onChanged;

  /// Multiple selection: the values that are on.
  final Set<T>? values;

  /// Multiple selection: called with the new set.
  final ValueChanged<Set<T>>? onValuesChanged;

  /// Momentary: called with the pressed segment's value.
  final ValueChanged<T>? onPressed;
  final bool equal;
  final bool toolbar;

  /// Accessible name of the group ("View").
  final String? semanticLabel;
  final MacControlSize? size;
  final _Mode _mode;

  @override
  State<MacSegmentedControl<T>> createState() => _MacSegmentedControlState<T>();
}

class _MacSegmentedControlState<T> extends State<MacSegmentedControl<T>> {
  final List<FocusNode> _nodes = [];
  int _pressed = -1;

  bool get _controlEnabled => switch (widget._mode) {
        _Mode.single => widget.onChanged != null,
        _Mode.multiple => widget.onValuesChanged != null,
        _Mode.momentary => widget.onPressed != null,
      };

  bool _enabled(int i) => _controlEnabled && widget.segments[i].enabled;

  bool _selected(int i) => switch (widget._mode) {
        _Mode.single => widget.segments[i].value == widget.value,
        _Mode.multiple => widget.values!.contains(widget.segments[i].value),
        _Mode.momentary => false,
      };

  void _activate(int i) {
    final v = widget.segments[i].value;
    switch (widget._mode) {
      case _Mode.single:
        widget.onChanged!(v);
      case _Mode.multiple:
        final next = {...widget.values!};
        if (!next.remove(v)) next.add(v);
        widget.onValuesChanged!(next);
      case _Mode.momentary:
        widget.onPressed!(v);
    }
  }

  void _syncNodes() {
    while (_nodes.length < widget.segments.length) {
      _nodes.add(FocusNode(debugLabel: 'MacSegment ${_nodes.length}'));
    }
    while (_nodes.length > widget.segments.length) {
      _nodes.removeLast().dispose();
    }
    if (widget._mode == _Mode.single) {
      final chosen = widget.segments.indexWhere((s) => s.value == widget.value);
      for (var i = 0; i < _nodes.length; i++) {
        _nodes[i].skipTraversal = chosen >= 0 ? i != chosen : i != 0;
      }
    } else {
      for (final n in _nodes) {
        n.skipTraversal = false;
      }
    }
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  KeyEventResult _onKey(int i, KeyEvent e) {
    if (widget._mode != _Mode.single) return KeyEventResult.ignored;
    int dir = 0;
    if (controlKey(e, LogicalKeyboardKey.arrowRight) || controlKey(e, LogicalKeyboardKey.arrowDown)) dir = 1;
    if (controlKey(e, LogicalKeyboardKey.arrowLeft) || controlKey(e, LogicalKeyboardKey.arrowUp)) dir = -1;
    if (dir == 0) return KeyEventResult.ignored;
    for (var j = i + dir; j >= 0 && j < widget.segments.length; j += dir) {
      if (_enabled(j)) {
        _activate(j);
        _nodes[j].requestFocus();
        break;
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    _syncNodes();
    final look = ControlLook.of(context, widget.size);
    final s = look.s;
    final h = s.globalHeight;
    final toolbar = widget.toolbar || MacToolbarScope.isInToolbar(context);
    final colors = _SegmentColors.of(look, toolbar);
    final pad = toolbar ? h / 6 - 2 : 0.0;
    final space = toolbar ? 15 - h / 3 : -1.0;

    final children = <Widget>[];
    for (var i = 0; i < widget.segments.length; i++) {
      final seg = widget.segments[i];
      final enabled = _enabled(i);
      final selected = _selected(i);
      final prevHides = i > 0 && (_selected(i - 1) || _pressed == i - 1);
      children.add(Semantics(
        button: widget._mode == _Mode.momentary,
        inMutuallyExclusiveGroup: widget._mode == _Mode.single,
        checked: widget._mode == _Mode.momentary ? null : selected,
        enabled: enabled,
        label: seg.semanticLabel ?? seg.label,
        excludeSemantics: true,
        child: ControlPressable(
          onPressed: enabled ? () => _activate(i) : null,
          focusNode: _nodes[i],
          trackHover: toolbar,
          onKeyEvent: (node, e) => _onKey(i, e),
          builder: (context, state) {
            if (state.pressed != (_pressed == i)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _pressed = state.pressed ? i : (_pressed == i ? -1 : _pressed));
              });
            }
            final Color fill;
            if (selected) {
              fill = !enabled ? colors.selectedDisabled : (state.pressed ? colors.selectedPressed : colors.selected);
            } else if (state.pressed) {
              fill = colors.pressed;
            } else if (toolbar && state.hovered) {
              fill = colors.hover;
            } else {
              fill = controlClear;
            }
            final Color text;
            if (selected) {
              text = enabled ? colors.selectedLabel : colors.selectedLabelDisabled;
            } else {
              text = enabled ? colors.label : look.c.labelTertiary;
            }
            final showSeparator = i > 0 && !selected && !state.pressed && !prevHides;
            final iconSize = toolbar ? h / 4 + 9 : s.globalFontSize + 1;
            final radius = toolbar ? 1000.0 : s.buttonRadius;
            return CustomPaint(
              painter: _SegmentPainter(
                fill: fill,
                radius: radius,
                separator: showSeparator ? colors.separator : null,
                separatorHeight: toolbar ? h / 3 + 8 : s.segmentedControlHeightSeparator,
                separatorX: toolbar ? -space / 2 - 0.5 : 0,
                focus: state.focused ? look.focusColor : null,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: toolbar ? h * 2 / 3 + 8 : 0),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: toolbar ? 7.5 - h / 8 : s.segmentedControlMargins),
                  child: Center(
                    widthFactor: 1,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (seg.icon != null)
                        SizedBox(width: iconSize, height: iconSize, child: Center(child: Icon(seg.icon, size: iconSize, color: text))),
                      if (seg.icon != null && seg.label != null) const SizedBox(width: 4),
                      if (seg.label != null)
                        Text(seg.label!, maxLines: 1, softWrap: false, style: look.text(s.globalFontSize, text)),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ));
    }

    Widget row = _SegmentRow(spacing: space, equal: widget.equal, height: h - 2 * pad, children: children);
    row = Padding(padding: EdgeInsets.all(pad), child: row);

    final Widget track = toolbar
        ? ControlToolbarCapsule(child: row)
        : CustomPaint(painter: _TrackPainter(colors: [look.c.fillQuinary, colors.track], radius: s.buttonRadius), child: row);
    return Semantics(container: true, label: widget.semanticLabel, explicitChildNodes: true, child: SizedBox(height: h, child: track));
  }
}

/// segmented-controls.css colours for the current state.
class _SegmentColors {
  _SegmentColors({
    required this.track,
    required this.pressed,
    required this.hover,
    required this.separator,
    required this.selected,
    required this.selectedPressed,
    required this.selectedDisabled,
    required this.label,
    required this.selectedLabel,
    required this.selectedLabelDisabled,
  });
  final Color track;
  final Color pressed;
  final Color hover;
  final Color separator;
  final Color selected;
  final Color selectedPressed;
  final Color selectedDisabled;
  final Color label;
  final Color selectedLabel;
  final Color selectedLabelDisabled;

  static _SegmentColors of(ControlLook look, bool toolbar) {
    final c = look.c;
    if (toolbar) {
      return _SegmentColors(
        track: controlClear,
        pressed: look.ld(controlBlack(0.16), controlWhite(0.16)),
        hover: c.fillTertiary,
        separator: look.ld(controlBlack(0.15), controlWhite(0.15)),
        selected: c.fillPrimary,
        selectedPressed: look.ld(controlBlack(0.16), controlWhite(0.16)),
        selectedDisabled: c.fillTertiary,
        label: c.labelVibrantPrimary,
        selectedLabel: c.labelVibrantPrimary,
        selectedLabelDisabled: c.labelTertiary,
      );
    }
    final accent = look.overGlass ? look.vibrantAccent : look.accent;
    final selected = look.dark ? controlMix(accent, 0.9608, controlWhiteSolid) : controlMix(accent, 0.9686, controlBlackSolid);
    if (look.inactive) {
      return _SegmentColors(
        track: look.borderedFill,
        pressed: look.borderedFillPressed,
        hover: controlClear,
        separator: c.labelTertiary,
        selected: c.fillPrimary,
        selectedPressed: look.ld(controlBlack(0.19), controlWhite(0.19)),
        selectedDisabled: look.ld(controlBlack(0.05), controlWhite(0.03)),
        label: c.labelPrimary,
        selectedLabel: c.labelPrimary,
        selectedLabelDisabled: c.labelTertiary,
      );
    }
    return _SegmentColors(
      track: look.borderedFill,
      pressed: look.borderedFillPressed,
      hover: controlClear,
      separator: c.labelTertiary,
      selected: selected,
      selectedPressed: look.dark ? controlMix(accent, 0.8588, controlWhiteSolid) : controlMix(accent, 0.851, controlBlackSolid),
      selectedDisabled: controlFade(selected, 0.45),
      label: c.labelPrimary,
      selectedLabel: c.glyphOnAccent,
      selectedLabelDisabled: c.glyphOnAccentDisabled,
    );
  }
}

class _SegmentPainter extends CustomPainter {
  _SegmentPainter({
    required this.fill,
    required this.radius,
    required this.separator,
    required this.separatorHeight,
    required this.separatorX,
    required this.focus,
  });
  final Color fill;
  final double radius;
  final Color? separator;
  final double separatorHeight;
  final double separatorX;
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (separator != null) {
      canvas.drawRect(
        Rect.fromLTWH(separatorX, (size.height - separatorHeight) / 2, 1, separatorHeight),
        Paint()..color = separator!,
      );
    }
    if (fill.a > 0) canvas.drawPath(controlShape(rect, radius), Paint()..color = fill);
    if (focus != null) paintFocusRing(canvas, rect, radius, focus!);
  }

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.fill != fill || old.radius != radius || old.separator != separator || old.separatorHeight != separatorHeight ||
      old.separatorX != separatorX || old.focus != focus;
}

/// The content-area track: fill quinary, then the bordered fill on top.
class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.colors, required this.radius});
  final List<Color> colors;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final path = controlShape(Offset.zero & size, radius);
    for (final c in colors) {
      canvas.drawPath(path, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.radius != radius || old.colors.toString() != colors.toString();
}

/// Lays the segments out in a row; [spacing] −1 = neighbours share their edge pixel (kit auto-layout gap −1).
class _SegmentRow extends MultiChildRenderObjectWidget {
  const _SegmentRow({required this.spacing, required this.equal, required this.height, required super.children});
  final double spacing;
  final bool equal;
  final double height;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSegmentRow(spacing, equal, height);

  @override
  void updateRenderObject(BuildContext context, _RenderSegmentRow renderObject) {
    renderObject
      ..spacing = spacing
      ..equal = equal
      ..rowHeight = height;
  }
}

class _SegmentParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSegmentRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _SegmentParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _SegmentParentData> {
  _RenderSegmentRow(this._spacing, this._equal, this._height);

  double _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  bool _equal;
  set equal(bool v) {
    if (v == _equal) return;
    _equal = v;
    markNeedsLayout();
  }

  double _height;
  set rowHeight(double v) {
    if (v == _height) return;
    _height = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SegmentParentData) child.parentData = _SegmentParentData();
  }

  List<double> _naturalWidths() {
    final widths = <double>[];
    var child = firstChild;
    while (child != null) {
      widths.add(child.getMaxIntrinsicWidth(_height));
      child = childAfter(child);
    }
    if (_equal && widths.isNotEmpty) {
      final widest = widths.reduce(math.max);
      for (var i = 0; i < widths.length; i++) {
        widths[i] = widest;
      }
    }
    return widths;
  }

  double _total(List<double> widths) =>
      widths.isEmpty ? 0 : widths.reduce((a, b) => a + b) + _spacing * (widths.length - 1);

  @override
  double computeMinIntrinsicWidth(double height) => _total(_naturalWidths());
  @override
  double computeMaxIntrinsicWidth(double height) => _total(_naturalWidths());
  @override
  double computeMinIntrinsicHeight(double width) => _height;
  @override
  double computeMaxIntrinsicHeight(double width) => _height;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final widths = _naturalWidths();
    var total = _total(widths);
    if (_equal && constraints.minWidth > total) total = constraints.minWidth;
    return constraints.constrain(Size(total, _height));
  }

  @override
  void performLayout() {
    final widths = _naturalWidths();
    var total = _total(widths);
    if (_equal && widths.isNotEmpty && constraints.minWidth > total) {
      final extra = (constraints.minWidth - total) / widths.length;
      for (var i = 0; i < widths.length; i++) {
        widths[i] += extra;
      }
      total = constraints.minWidth;
    }
    var x = 0.0;
    var i = 0;
    var child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints.tightFor(width: widths[i], height: _height), parentUsesSize: true);
      (child.parentData! as _SegmentParentData).offset = Offset(x, 0);
      x += widths[i] + _spacing;
      i++;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(total, _height));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}
