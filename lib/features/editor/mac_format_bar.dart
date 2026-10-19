/// The macOS format bar — the desktop builds' counterpart of the Material
/// ribbon in `canvas_toolbar.dart`.
///
/// Laid out like the format bar of TextEdit and Pages: one band under the
/// window toolbar, on the window background with a separator below, every
/// control at the small size. Left to right:
///
///   Style · Font · Size      pop-up buttons showing what the caret is in
///   B I U S <>               one multiple-selection segmented control
///   text · highlight colour  "A" and brush buttons over a colour bar, each
///                            opening the palette
///   left · centre · right    one single-choice segmented control
///   lists and quote          toggles: they show the block the caret is in
///   inserts                  push-button segments (image, table, auto-fit;
///                            drawing, spreadsheet, maths, divider)
///   − 100% +                 zoom
///
/// and the page actions (save state, Export…, dictation, Draw, More) pinned
/// to the end of the first row. It wraps at narrow widths like the ribbon
/// does, but the actions float at the end of the FIRST row and later rows get
/// the full width, so the 800 px minimum window takes three short rows rather
/// than a tall column beside the actions.
///
/// The commands themselves are not here: they are `CanvasToolbar`'s, through
/// [CanvasFormatting], so both looks format the page with the same code and
/// the same remembered selection.
library;

import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'blocks/drawing_block.dart';
import 'blocks/math_block.dart';
import 'blocks/spreadsheet_block.dart';
import 'mac_segment_tooltips.dart';

/// What a format bar can do to the page.
///
/// Implemented by `CanvasToolbar`'s state, which owns the commands and the
/// selection they act on — including the range it remembers when a pop-up or
/// a popover takes focus and the editor's own selection collapses.
abstract interface class CanvasFormatting {
  afe.EditorState get editorState;

  /// The live selection, or the last range there was: what the block-level
  /// commands (style, alignment, lists) act on, so also what the bar shows.
  afe.Selection? get blockSelection;

  /// Whether there is a range to format — the live one or a remembered one.
  bool get hasRange;

  List<double> get fontSizes;
  List<String> get fontFamilies;

  /// The document colours the text and highlight wells offer.
  List<Color> get palette;

  bool isAttributeOn(String key);
  Future<void> toggleAttribute(String key);
  Future<void> formatColor(String key, Color? color);
  Future<void> setFontSize(double size);
  Future<void> setFontFamily(String family);
  Future<void> setHeading(int? level);
  Future<void> setListType(String type);
  Future<void> setAlign(String align);
  Future<void> insertNode(afe.Node node);
  Future<void> pickAndInsertImage();
  Future<void> insertTable();
  Future<void> autoFitTableColumns();
  Future<void> insertDivider();
}

/// One icon segment: its value, glyph, accessible name and tooltip.
class _Seg<T> {
  const _Seg(this.value, this.icon, this.name, this.tooltip);
  final T value;
  final IconData icon;
  final String name;
  final String tooltip;
}

enum _Insert { image, table, autoFit, drawing, spreadsheet, math, divider }

/// The block types the list segments switch between. Choosing the one the
/// block already is turns it back into a paragraph (`setListType` toggles).
const _listTypes = ['bulleted_list', 'numbered_list', 'todo_list', 'quote'];

/// Paragraph styles by heading level; 0 is a plain paragraph.
const _styleNames = ['Normal', 'Heading 1', 'Heading 2', 'Heading 3'];

/// The pop-up value for "the caret is in something that has no style here"
/// (a list item, a quote, a heading below level 3): the pop-up then shows the
/// word Style, as the Material ribbon's hint does, rather than a wrong name.
const _noStyle = -1;

class MacFormatBar extends StatelessWidget {
  const MacFormatBar({
    super.key,
    required this.formatting,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    this.trailing,
  });

  final CanvasFormatting formatting;
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;

  /// The page actions, pinned to the end of the first row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final f = formatting;
    final editor = f.editorState;
    final block = f.blockSelection;
    final node = block == null ? null : editor.getNodeAtPath(block.start.path);

    // ── Paragraph style, font, size ────────────────────────────────────────
    var level = _noStyle;
    if (node?.type == afe.ParagraphBlockKeys.type) level = 0;
    if (node?.type == afe.HeadingBlockKeys.type) {
      final l = node!.attributes[afe.HeadingBlockKeys.level];
      if (l is int && l >= 1 && l <= 3) level = l;
    }
    final style = MacPopUpButton<int>(
      options: const [0, 1, 2, 3],
      value: level,
      labelOf: (l) => l == _noStyle ? 'Style' : _styleNames[l],
      onChanged: (l) => f.setHeading(l == 0 ? null : l),
      semanticLabel: 'Paragraph style',
    );

    final family = editor.getDeltaAttributeValueInSelection<String>(
        afe.AppFlowyRichTextKeys.fontFamily, block);
    final font = MacPopUpButton<String>(
      options: f.fontFamilies,
      // '' stands for "no family set here", shown as the ribbon's hint.
      value: family ?? '',
      labelOf: (s) => s.isEmpty ? 'Font' : s,
      onChanged: (s) {
        if (s.isNotEmpty) f.setFontFamily(s);
      },
      semanticLabel: 'Font',
    );

    final size = editor
        .getDeltaAttributeValueInSelection<num>(
            afe.AppFlowyRichTextKeys.fontSize, block)
        ?.toDouble();
    final fontSize = MacPopUpButton<double>(
      options: f.fontSizes,
      value: size ?? 0,
      labelOf: (s) => s <= 0
          ? 'Size'
          : s == s.roundToDouble()
              ? s.toStringAsFixed(0)
              : s.toStringAsFixed(1),
      // Size applies to a range only, as on the ribbon.
      onChanged: f.hasRange
          ? (s) {
              if (s > 0) f.setFontSize(s);
            }
          : null,
      semanticLabel: 'Font size',
    );

    // ── Character marks ────────────────────────────────────────────────────
    final marks = [
      _Seg(afe.AppFlowyRichTextKeys.bold, CupertinoIcons.bold, 'Bold',
          'Bold (Ctrl+B)'),
      _Seg(afe.AppFlowyRichTextKeys.italic, CupertinoIcons.italic, 'Italic',
          'Italic (Ctrl+I)'),
      _Seg(afe.AppFlowyRichTextKeys.underline, CupertinoIcons.underline,
          'Underline', 'Underline (Ctrl+U)'),
      _Seg(afe.AppFlowyRichTextKeys.strikethrough, CupertinoIcons.strikethrough,
          'Strikethrough', 'Strikethrough'),
      _Seg(
          afe.AppFlowyRichTextKeys.code,
          CupertinoIcons.chevron_left_slash_chevron_right,
          'Inline Code',
          'Inline code'),
    ];
    final marksOn = {
      for (final m in marks)
        if (f.isAttributeOn(m.value)) m.value,
    };
    final markControl = _segmented(
      marks,
      (segments) => MacSegmentedControl<String>.multiple(
        segments: segments,
        values: marksOn,
        equal: true,
        semanticLabel: 'Text style',
        // A click flips exactly one segment; toggle that mark.
        onChanged: (next) {
          for (final key in _flipped(marksOn, next)) {
            f.toggleAttribute(key);
          }
        },
      ),
    );

    // ── Colours ────────────────────────────────────────────────────────────
    Color? colorAt(String key) => editor
        .getDeltaAttributeValueInSelection<String>(key, block)
        ?.tryToColor();
    final colors = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        _ColorWellPicker(
          tooltip: 'Text color',
          label: 'A',
          // Unset text is drawn in the label colour; say so.
          color: colorAt(afe.AppFlowyRichTextKeys.textColor) ?? c.labelPrimary,
          palette: f.palette,
          onPicked: f.hasRange
              ? (color) =>
                  f.formatColor(afe.AppFlowyRichTextKeys.textColor, color)
              : null,
        ),
        _ColorWellPicker(
          tooltip: 'Highlight',
          icon: CupertinoIcons.paintbrush,
          // No bar colour = no highlight.
          color: colorAt(afe.AppFlowyRichTextKeys.backgroundColor),
          palette: f.palette,
          onPicked: f.hasRange
              ? (color) =>
                  f.formatColor(afe.AppFlowyRichTextKeys.backgroundColor, color)
              : null,
        ),
      ],
    );

    // ── Alignment ──────────────────────────────────────────────────────────
    final aligns = [
      const _Seg(
          'left', CupertinoIcons.text_alignleft, 'Align Left', 'Align left'),
      const _Seg('center', CupertinoIcons.text_aligncenter, 'Align Center',
          'Align center'),
      const _Seg('right', CupertinoIcons.text_alignright, 'Align Right',
          'Align right'),
    ];
    final align = _segmented(
      aligns,
      (segments) => MacSegmentedControl<String>(
        segments: segments,
        value: node == null
            ? null
            : (node.attributes[afe.blockComponentAlign] as String? ?? 'left'),
        equal: true,
        semanticLabel: 'Alignment',
        onChanged: (a) => f.setAlign(a),
      ),
    );

    // ── Lists and quote ────────────────────────────────────────────────────
    final lists = [
      const _Seg('bulleted_list', CupertinoIcons.list_bullet, 'Bullet List',
          'Bullet list'),
      const _Seg('numbered_list', CupertinoIcons.list_number, 'Numbered List',
          'Numbered list'),
      const _Seg('todo_list', CupertinoIcons.checkmark_square, 'Todo List',
          'Todo list'),
      const _Seg('quote', CupertinoIcons.text_quote, 'Quote', 'Quote'),
    ];
    final listOn = {
      if (node != null && _listTypes.contains(node.type)) node.type,
    };
    final listControl = _segmented(
      lists,
      (segments) => MacSegmentedControl<String>.multiple(
        segments: segments,
        values: listOn,
        equal: true,
        semanticLabel: 'Lists',
        onChanged: (next) {
          for (final type in _flipped(listOn, next)) {
            f.setListType(type);
          }
        },
      ),
    );

    // ── Inserts ────────────────────────────────────────────────────────────
    void insert(_Insert what) => switch (what) {
          _Insert.image => f.pickAndInsertImage(),
          _Insert.table => f.insertTable(),
          _Insert.autoFit => f.autoFitTableColumns(),
          _Insert.drawing => f.insertNode(drawingNode()),
          _Insert.spreadsheet => f.insertNode(spreadsheetNode()),
          _Insert.math => f.insertNode(mathEquationNode()),
          _Insert.divider => f.insertDivider(),
        };
    Widget inserts(List<_Seg<_Insert>> items) => _segmented(
          items,
          (segments) => MacSegmentedControl<_Insert>.momentary(
            segments: segments,
            equal: true,
            semanticLabel: 'Insert',
            onPressed: insert,
          ),
        );
    final tableInserts = inserts(const [
      _Seg(_Insert.image, CupertinoIcons.photo, 'Insert Image', 'Insert image'),
      _Seg(_Insert.table, CupertinoIcons.table, 'Insert Table', 'Insert table'),
      _Seg(_Insert.autoFit, CupertinoIcons.arrow_left_right_square,
          'Auto-fit Table Columns', 'Auto-fit table columns to content'),
    ]);
    final blockInserts = inserts(const [
      _Seg(_Insert.drawing, CupertinoIcons.scribble, 'Insert Drawing',
          'Insert drawing block'),
      _Seg(_Insert.spreadsheet, CupertinoIcons.square_grid_3x2,
          'Insert Spreadsheet', 'Insert spreadsheet'),
      _Seg(_Insert.math, CupertinoIcons.function, 'Insert Equation',
          'Insert math equation'),
      _Seg(_Insert.divider, CupertinoIcons.minus, 'Insert Divider',
          'Insert divider'),
    ]);

    // ── Zoom ───────────────────────────────────────────────────────────────
    final zoomControls = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        MacTooltip(
          message: 'Zoom out (Ctrl+-)',
          child: MacButton(
            icon: AppleIcons.minus,
            semanticLabel: 'Zoom Out',
            onPressed: onZoomOut,
          ),
        ),
        MacTooltip(
          message: 'Actual size (Ctrl+0)',
          child: MacButton(
            label: '${(zoom * 100).round()}%',
            semanticLabel: 'Zoom ${(zoom * 100).round()}%, reset',
            onPressed: onZoomReset,
          ),
        ),
        MacTooltip(
          message: 'Zoom in (Ctrl+=)',
          child: MacButton(
            icon: AppleIcons.plus,
            semanticLabel: 'Zoom In',
            onPressed: onZoomIn,
          ),
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.windowBg,
        border: Border(bottom: BorderSide(color: c.separator)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: MacControlSizeScope(
          size: MacControlSize.small,
          child: _FloatEndWrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              style,
              font,
              fontSize,
              markControl,
              colors,
              align,
              listControl,
              tableInserts,
              blockInserts,
              zoomControls,
              trailing ?? const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }

  /// An equal-width icon segmented control with a tooltip per segment.
  static Widget _segmented<T>(
    List<_Seg<T>> items,
    Widget Function(List<MacSegment<T>> segments) control,
  ) =>
      MacSegmentTooltips(
        messages: [for (final i in items) i.tooltip],
        child: control([
          for (final i in items)
            MacSegment<T>(value: i.value, icon: i.icon, semanticLabel: i.name),
        ]),
      );

  /// The values a multiple-selection click changed: in one set, not both.
  static Iterable<T> _flipped<T>(Set<T> before, Set<T> after) =>
      after.difference(before).followedBy(before.difference(after));
}

/// A text- or highlight-colour button that opens the document palette, with
/// None to clear.
///
/// The trigger is a push button carrying its glyph ("A", a brush) over a bar
/// of the colour in use, as Pages and Word draw them. A bare colour well read
/// as a blank placeholder: two pills with no glyph, and — with no text
/// selected — no response either. The disabled button says what it is for,
/// and its tooltip what it is waiting for.
///
/// apple_ui's own well offers the system accent colours and no way back to
/// "no colour", which a highlight needs most of all — so the button opens its
/// own popover: the same palette the web ribbon offers (the document must
/// look the same wherever it is opened), as small wells, and a None button.
class _ColorWellPicker extends StatefulWidget {
  const _ColorWellPicker({
    required this.tooltip,
    required this.color,
    required this.palette,
    required this.onPicked,
    this.label,
    this.icon,
  }) : assert(label != null || icon != null);

  final String tooltip;

  /// The glyph: a letter or a symbol.
  final String? label;
  final IconData? icon;

  /// The colour bar under the glyph; null for none (no highlight).
  final Color? color;
  final List<Color> palette;

  /// Null disables the well (there is no range to colour).
  final ValueChanged<Color?>? onPicked;

  @override
  State<_ColorWellPicker> createState() => _ColorWellPickerState();
}

class _ColorWellPickerState extends State<_ColorWellPicker> {
  bool _open = false;

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  void _pick(Color? color) {
    setState(() => _open = false);
    widget.onPicked?.call(color);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final enabled = widget.onPicked != null;
    const perRow = 5;
    const swatchGap = 8.0;
    final swatchWidth = MacSizes.of(MacControlSize.mini).colorWellWidth;
    return MacPopover(
      isOpen: _open && enabled,
      onDismiss: () => setState(() => _open = false),
      semanticLabel: widget.tooltip,
      content: SizedBox(
        width: perRow * swatchWidth + (perRow - 1) * swatchGap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Wrap(
              spacing: swatchGap,
              runSpacing: swatchGap,
              children: [
                for (final color in widget.palette)
                  MacColorWell(
                    color: color,
                    size: MacControlSize.mini,
                    onPressed: () => _pick(color),
                    semanticLabel: _hex(color),
                  ),
              ],
            ),
            MacButton(label: 'None', onPressed: () => _pick(null)),
          ],
        ),
      ),
      child: MacTooltip(
        message: enabled
            ? widget.tooltip
            : '${widget.tooltip} — select some text first',
        child: Stack(
          children: [
            MacButton(
              label: widget.label,
              icon: widget.icon,
              isOn: _open && enabled,
              semanticLabel: widget.tooltip,
              onPressed: enabled ? () => setState(() => _open = !_open) : null,
            ),
            Positioned(
              left: 7,
              right: 7,
              bottom: 2,
              height: 3,
              child: IgnorePointer(
                child: Opacity(
                  opacity: enabled ? 1 : 0.4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.color,
                      // No colour: an outline, so "none" still reads as a
                      // swatch rather than as nothing at all.
                      border: widget.color == null
                          ? Border.all(color: c.labelTertiary, width: 0.5)
                          : null,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A wrap whose last child floats at the end of the first run.
///
/// The other children flow from the start, run after run, as in a [Wrap];
/// the first run stops short of the floated child, and every later run gets
/// the full width. That is what keeps the page actions at the right end of
/// the format bar without giving the controls only the width left beside
/// them on every row.
class _FloatEndWrap extends MultiChildRenderObjectWidget {
  const _FloatEndWrap({
    required this.spacing,
    required this.runSpacing,
    required super.children,
  });

  final double spacing;
  final double runSpacing;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFloatEndWrap(
        spacing: spacing,
        runSpacing: runSpacing,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
      BuildContext context, _RenderFloatEndWrap renderObject) {
    renderObject
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..textDirection = Directionality.of(context);
  }
}

class _FloatEndParentData extends ContainerBoxParentData<RenderBox> {}

class _Run {
  _Run(this.limit);
  final double limit;
  double extent = 0;
  double height = 0;
  int count = 0;
}

/// Room the floated child always gets: the page actions' four buttons and
/// a short save line.
const double _floatMinWidth = 280;

class _RenderFloatEndWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FloatEndParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FloatEndParentData> {
  _RenderFloatEndWrap({
    required double spacing,
    required double runSpacing,
    required TextDirection textDirection,
  })  : _spacing = spacing,
        _runSpacing = runSpacing,
        _textDirection = textDirection;

  double _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  double _runSpacing;
  set runSpacing(double v) {
    if (v == _runSpacing) return;
    _runSpacing = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FloatEndParentData) {
      child.parentData = _FloatEndParentData();
    }
  }

  @override
  void performLayout() {
    final trailing = lastChild;
    if (trailing == null) {
      size = constraints.smallest;
      return;
    }
    final maxWidth = constraints.maxWidth;
    final childConstraints = maxWidth.isFinite
        ? BoxConstraints(maxWidth: maxWidth)
        : const BoxConstraints();

    // The floated child may take half the width — never less than
    // [_floatMinWidth], unless the whole bar is narrower — so a long save
    // line ellipsises instead of pushing every control off the first run.
    final floatMax = maxWidth.isFinite
        ? math.max(maxWidth / 2, math.min(maxWidth, _floatMinWidth))
        : double.infinity;
    trailing.layout(BoxConstraints(maxWidth: floatMax), parentUsesSize: true);
    final trailingSize = trailing.size;
    final trailingGap = trailingSize.width > 0 ? _spacing : 0.0;

    // Greedy runs. The first stops short of the floated child; a child that
    // would not fit there even alone starts the next run instead.
    final runs = [_Run(maxWidth - trailingSize.width - trailingGap)];
    final placed = <(RenderBox, int, double)>[];
    var child = firstChild;
    while (child != null && child != trailing) {
      child.layout(childConstraints, parentUsesSize: true);
      final w = child.size.width;
      var run = runs.last;
      final overflows = run.count == 0
          ? runs.length == 1 && w > run.limit
          : run.extent + _spacing + w > run.limit;
      if (overflows) {
        run = _Run(maxWidth);
        runs.add(run);
      }
      final x = run.count == 0 ? 0.0 : run.extent + _spacing;
      run
        ..extent = x + w
        ..height = math.max(run.height, child.size.height)
        ..count += 1;
      placed.add((child, runs.length - 1, x));
      child = childAfter(child);
    }
    runs.first.height = math.max(runs.first.height, trailingSize.height);

    final tops = <double>[];
    var y = 0.0;
    for (var i = 0; i < runs.length; i++) {
      if (i > 0) y += _runSpacing;
      tops.add(y);
      y += runs[i].height;
    }

    final width = maxWidth.isFinite
        ? maxWidth
        : runs.first.extent + trailingGap + trailingSize.width;
    final rtl = _textDirection == TextDirection.rtl;
    for (final (box, runIndex, x) in placed) {
      final run = runs[runIndex];
      final dx = rtl ? width - x - box.size.width : x;
      final dy = tops[runIndex] + (run.height - box.size.height) / 2;
      (box.parentData! as _FloatEndParentData).offset = Offset(dx, dy);
    }
    (trailing.parentData! as _FloatEndParentData).offset = Offset(
      rtl ? 0 : width - trailingSize.width,
      (runs.first.height - trailingSize.height) / 2,
    );
    size = constraints.constrain(Size(width, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
