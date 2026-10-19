import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/macos_tokens.dart';
import '../core/theme.dart';
import '_chrome.dart';
import 'scroll_views.dart';

// Page layout helpers (layout-and-sizing.md): MacContent > MacStack > MacSection > MacGrid > MacTile.
// Spacing comes from these widgets (20 / 8 / 16 / 12 · 4): never add your own padding around them.

/// The sections of a page, 20 px apart, stretched to the full width. Put exactly one in [MacContent].
///
///     MacContent(child: MacStack(children: [
///       MacSection(title: 'Usage', children: [MacGrid(children: tiles)]),
///       MacSection(title: 'Processes', children: [MacTile(flush: true, children: [table])]),
///     ]))
class MacStack extends StatelessWidget {
  const MacStack({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 20, children: children);
}

/// One titled group of a page: the title (13 px Bold), then the content, 8 px apart.
/// [actions] go at the right end of the title row (a small button, a search field).
///
///     MacSection(title: 'Network', actions: [MacButton(label: 'Details…', onPressed: open)], children: [
///       MacGrid(children: [downloadTile, uploadTile]),
///     ])
class MacSection extends StatelessWidget {
  const MacSection({super.key, this.title, this.actions = const [], required this.children});

  final String? title;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).mac;
    final heading = title == null
        ? null
        : Semantics(
            header: true,
            child: Text(title!, style: macChromeText(13, 16, c.labelPrimary, weight: FontWeight.w700)),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        if (actions.isEmpty)
          ?heading
        else
          Row(
            spacing: 8,
            children: [
              Expanded(child: heading ?? const SizedBox.shrink()),
              ...actions,
            ],
          ),
        ...children,
      ],
    );
  }
}

/// Tiles side by side, 16 px apart, filling the whole width. Balanced columns: 4 when four tiles of at least
/// [minTileWidth] fit, else 2, else 1 — never 3 + 1. Fewer tiles than columns stretch to fill the row.
/// The tiles of one row are equally tall. [columns] 3 = three columns, else one (for 3, 6 or 9 tiles).
///
///     MacGrid(children: [cpuTile, memoryTile, diskTile, networkTile])
///     MacGrid(minTileWidth: 280, children: tiles)          // wider tiles: 4 columns only in wide windows
///     MacGrid(columns: 3, children: sixTiles)
class MacGrid extends StatelessWidget {
  const MacGrid({super.key, required this.children, this.minTileWidth = 200, this.columns = 4})
    : assert(columns == 3 || columns == 4, 'MacGrid columns is 4 (4 → 2 → 1) or 3 (3 → 1)');

  final List<Widget> children;

  /// Smallest tile width (default 200).
  final double minTileWidth;
  final int columns;

  @override
  Widget build(BuildContext context) => _GridLayout(minTileWidth: minTileWidth, columns: columns, children: children);
}

class _GridLayout extends MultiChildRenderObjectWidget {
  const _GridLayout({required this.minTileWidth, required this.columns, required super.children});
  final double minTileWidth;
  final int columns;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGrid(minTileWidth, columns);

  @override
  void updateRenderObject(BuildContext context, _RenderGrid renderObject) {
    renderObject
      ..minTileWidth = minTileWidth
      ..columns = columns;
  }
}

class _GridParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderGrid extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _GridParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _GridParentData> {
  _RenderGrid(this._minTileWidth, this._columns);

  static const _gap = 16.0;

  double _minTileWidth;
  set minTileWidth(double v) {
    if (v == _minTileWidth) return;
    _minTileWidth = v;
    markNeedsLayout();
  }

  int _columns;
  set columns(int v) {
    if (v == _columns) return;
    _columns = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridParentData) child.parentData = _GridParentData();
  }

  int _columnCount(double width) {
    int n;
    if (_columns == 3) {
      n = width >= 3 * _minTileWidth + 2 * _gap ? 3 : 1;
    } else {
      n = width >= 4 * _minTileWidth + 3 * _gap ? 4 : (width >= 2 * _minTileWidth + _gap ? 2 : 1);
    }
    return math.max(1, math.min(n, childCount));
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : _minTileWidth;
    final n = _columnCount(width);
    final colW = (width - (n - 1) * _gap) / n;
    var y = 0.0;
    var child = firstChild;
    var rows = 0;
    while (child != null) {
      final row = <RenderBox>[];
      for (var i = 0; i < n && child != null; i++) {
        row.add(child);
        child = childAfter(child);
      }
      final loose = BoxConstraints(minWidth: colW, maxWidth: colW);
      var rowH = 0.0;
      for (final c in row) {
        rowH = math.max(rowH, dry ? c.getDryLayout(loose).height : (c..layout(loose, parentUsesSize: true)).size.height);
      }
      if (!dry) {
        for (var i = 0; i < row.length; i++) {
          row[i].layout(BoxConstraints.tightFor(width: colW, height: rowH));
          (row[i].parentData! as _GridParentData).offset = Offset(i * (colW + _gap), y);
        }
      }
      y += rowH + _gap;
      rows++;
    }
    final height = rows == 0 ? 0.0 : y - _gap;
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() => size = _layout(constraints, dry: false);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _layout(constraints, dry: true);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}

/// A box in a [MacGrid] (web `mac-tile`): radius 12, quaternary fill (black 3% · white 3%), 12 px padding,
/// parts 4 px apart: a label (11 px Semibold, grey), a big value (22 px Semibold, tabular digits), an optional
/// progress bar, a detail line (11 px, grey). Or any [children]; [flush] = no padding, for a table or list.
///
///     MacTile(label: 'CPU', icon: AppleIcons.bolt, value: '23%', progress: 0.23, detail: const Text('8 cores'))
///     MacTile(label: 'Downloads', value: '--')                            // no data yet
///     MacTile(label: 'Revenue', value: r'$12,400', detail: Text.rich(TextSpan(children: [
///       TextSpan(text: '↑ 12.5%', style: TextStyle(color: context.macColors.accentGreen)),
///       const TextSpan(text: ' vs yesterday'),
///     ])))
///     MacTile(flush: true, children: [table])
class MacTile extends StatelessWidget {
  const MacTile({super.key, this.label, this.icon, this.value, this.progress, this.detail, this.flush = false, this.children = const []});

  /// What the number is ("CPU").
  final String? label;

  /// Small symbol before the label.
  final IconData? icon;

  /// The number ("23%"). Pass '--' while there is no data yet.
  final String? value;

  /// 0.0–1.0: a progress bar under the value (8 px above and below).
  final double? progress;

  /// Line under it: units, totals, a change (11 px, grey, one line). Usually a `Text` or `Text.rich`.
  final Widget? detail;

  /// No padding (10 px at the bottom only): for a table or list that fills the tile.
  final bool flush;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final secondary = macChromeText(11, 14, c.labelSecondary, tabular: true);
    final items = <Widget>[
      if (label != null)
        Row(
          spacing: 4,
          children: [
            if (icon != null) Icon(icon, size: 12, color: c.labelSecondary),
            Flexible(
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: macChromeText(11, 14, c.labelSecondary, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      if (value != null)
        Text(
          value!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: macChromeText(22, 26, c.labelPrimary, weight: FontWeight.w600, tabular: true),
        ),
      if (progress != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Semantics(
            label: label,
            value: '${((progress!.clamp(0.0, 1.0)) * 100).round()}%',
            child: _TileBar(value: progress!.clamp(0.0, 1.0)),
          ),
        ),
      if (detail != null) DefaultTextStyle(style: secondary, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, child: detail!),
      ...children,
    ];
    final shape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(12));
    Widget box = DecoratedBox(
      decoration: ShapeDecoration(color: c.fillQuaternary, shape: shape),
      child: Padding(
        padding: flush ? const EdgeInsets.only(bottom: 10) : const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: flush ? 0 : 4,
          children: items,
        ),
      ),
    );
    if (flush) {
      box = ClipPath(clipper: ShapeBorderClipper(shape: shape), child: box);
    }
    return box;
  }
}

/// The linear progress bar of a tile (progress-indicators.css `mac-progress`): 10 px (6 px at small sizes),
/// accent capsule on a grey track with a 0.5 px inside stroke; grey fill in an inactive window.
class _TileBar extends StatelessWidget {
  const _TileBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final dark = theme.isDark;
    final inactive = MacWindowState.isInactive(context);
    final size = MacControlSizeScope.of(context);
    final h = size == MacControlSize.small || size == MacControlSize.mini ? 6.0 : 10.0;
    final track = inactive
        ? (dark ? const Color(0x0DFFFFFF) : const Color(0x0D000000))
        : (dark ? const Color(0x16FFFFFF) : const Color(0x16000000));
    final fill = inactive ? (dark ? const Color(0x25FFFFFF) : const Color(0x25000000)) : theme.accentColor;
    return SizedBox(
      height: h,
      child: CustomPaint(painter: _BarPainter(value, track, fill, theme.mac.progressTrackStroke)),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.value, this.track, this.fill, this.stroke);
  final double value;
  final Color track;
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final whole = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.save();
    canvas.clipRRect(whole);
    canvas.drawRRect(whole, Paint()..color = track);
    final w = math.max(size.height, size.width * value);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r), Paint()..color = fill);
    canvas.restore();
    canvas.drawRRect(
      whole.deflate(0.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = stroke,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.value != value || old.track != track || old.fill != fill || old.stroke != stroke;
}

/// Marks the inside of a [MacListColumn] (an empty state there is top-aligned).
class _ListColumnScope extends InheritedWidget {
  const _ListColumnScope({required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ListColumnScope>() != null;

  @override
  bool updateShouldNotify(_ListColumnScope old) => false;
}

/// The list column of a three-column window (Mail, Notes; SwiftUI `NavigationSplitView` content column):
/// 300 px wide (260–420), scrolls by itself, separator on the right. Put it in `MacWindow(listColumn: …)` with a
/// list in it (lists-and-tables.md) and the selected item in the content area.
///
///     MacWindow(
///       sidebar: sidebar,
///       titlebar: MacTitlebar(title: 'Notes'),
///       listColumn: MacListColumn(child: notesList),
///       child: MacContent(child: selected == null
///           ? const MacEmptyState(title: 'No Note Selected', message: 'Select a note, or create one with ⌘N.')
///           : MacEditor(titleController: titleCtl, controller: bodyCtl)),
///     )
class MacListColumn extends StatelessWidget {
  const MacListColumn({super.key, required this.child, this.width = 300, this.controller, this.scroll = true});

  final Widget child;

  /// Default 300 (usual range 260–420).
  final double width;
  final ScrollController? controller;

  /// False when the child scrolls by itself (a list that is already scrollable).
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).mac;
    const padding = EdgeInsets.symmetric(vertical: 8);
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: c.separator)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(right: 1),
          child: _ListColumnScope(
            child: scroll
                ? MacScrollView(controller: controller, padding: padding, fillViewport: false, child: child)
                : Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// "No Selection", "No Items", "No Results" centred in an empty pane (content, list column, inspector).
/// Never leave a pane blank. Title 17 px grey, optional message 11 px grey (max 280 wide).
///
///     const MacEmptyState(title: 'No Note Selected', message: 'Select a note, or create one with ⌘N.')
///     MacContent(child: MacEmptyState(title: 'No Results'))
class MacEmptyState extends StatelessWidget {
  const MacEmptyState({super.key, required this.title, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).mac;
    final inList = _ListColumnScope.of(context);
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Text(title, textAlign: TextAlign.center, style: macChromeText(17, 22, c.labelSecondary)),
        if (message != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(message!, textAlign: TextAlign.center, style: macChromeText(11, 14, c.labelSecondary)),
          ),
      ],
    );
    if (inList) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
        child: Align(alignment: Alignment.topCenter, child: column),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(child: column),
    );
  }
}

/// A document editor that fills the content pane (Notes, TextEdit): a borderless title (22 px Bold) and the
/// text (15 / 22) below it, 8 px apart. No border, no background, no focus ring: the pane is the editing area.
/// Put it in a [MacContent] (it fills the visible height and grows with the text).
///
///     MacContent(child: MacEditor(titleController: titleCtl, controller: bodyCtl, onChanged: save))
///     const MacEditor(showTitle: false, placeholder: 'Start typing…')      // text only
class MacEditor extends StatefulWidget {
  const MacEditor({
    super.key,
    this.titleController,
    this.controller,
    this.onTitleChanged,
    this.onChanged,
    this.titlePlaceholder = 'Title',
    this.placeholder = 'Start writing…',
    this.showTitle = true,
    this.readOnly = false,
    this.autofocus = false,
  });

  final TextEditingController? titleController;

  /// The body text.
  final TextEditingController? controller;
  final ValueChanged<String>? onTitleChanged;
  final ValueChanged<String>? onChanged;
  final String titlePlaceholder;
  final String placeholder;
  final bool showTitle;
  final bool readOnly;

  /// Put the cursor in the title (or the text, without a title) when shown.
  final bool autofocus;

  @override
  State<MacEditor> createState() => _MacEditorState();
}

class _MacEditorState extends State<MacEditor> {
  final _bodyFocus = FocusNode();
  TextEditingController? _ownTitle;
  TextEditingController? _ownBody;

  TextEditingController get _title => widget.titleController ?? (_ownTitle ??= TextEditingController());
  TextEditingController get _body => widget.controller ?? (_ownBody ??= TextEditingController());

  @override
  void dispose() {
    _bodyFocus.dispose();
    _ownTitle?.dispose();
    _ownBody?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final titleStyle = macChromeText(22, 26, c.labelPrimary, weight: FontWeight.w700);
    final bodyStyle = macChromeText(15, 22, c.labelPrimary);
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleBlock = widget.showTitle ? 26.0 + 8 : 0.0;
        final fill = constraints.minHeight.isFinite ? constraints.minHeight - titleBlock : 0.0;
        final bodyMin = math.max(240.0, fill);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            if (widget.showTitle)
              CupertinoTextField(
                controller: _title,
                onChanged: widget.onTitleChanged,
                readOnly: widget.readOnly,
                autofocus: widget.autofocus,
                placeholder: widget.titlePlaceholder,
                placeholderStyle: titleStyle.copyWith(color: c.labelTertiary),
                style: titleStyle,
                decoration: null,
                padding: EdgeInsets.zero,
                cursorColor: theme.accentColor,
                maxLines: 1,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _bodyFocus.requestFocus(),
              ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.readOnly ? null : () => _bodyFocus.requestFocus(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: bodyMin),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: CupertinoTextField(
                    controller: _body,
                    focusNode: _bodyFocus,
                    onChanged: widget.onChanged,
                    readOnly: widget.readOnly,
                    autofocus: widget.autofocus && !widget.showTitle,
                    placeholder: widget.placeholder,
                    placeholderStyle: bodyStyle.copyWith(color: c.labelTertiary),
                    style: bodyStyle,
                    decoration: null,
                    padding: EdgeInsets.zero,
                    cursorColor: theme.accentColor,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
