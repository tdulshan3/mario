import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../core/icons.dart';
import '../core/theme.dart';
import '../core/typography.dart';

// Lists — kit page "Lists" (Row, Row - Button, _Trailing, _Images, _Edit Buttons, _Grabber, Row with Swipe Actions,
// Header, Grouped Table Footer, Section Title, Index Bar). IosList > IosListSection > IosListRow.

/// inset grouped (Settings, forms: white cards on the grouped background) or plain (full-width rows).
enum IosListStyle { insetGrouped, plain }

/// Section header styles (kit "Header"): nested (Semibold 17, secondary) · prominent (Semibold 20) · extra prominent (Bold 22).
enum IosListHeaderStyle { nested, prominent, extraProminent }

/// Leading image styles (kit "_Images"): fill (square, full row height) · circle · rounded (r 7/11) · symbol (28 × 20).
enum IosListImageStyle { fill, circle, rounded, symbol }

/// Which side of a row the swipe actions are on: leading (swipe right) or trailing (swipe left).
enum IosSwipeSide { leading, trailing }

// ---- Shared metrics (kit) -----------------------------------------------------------------------------------------
const double _kRowPadX = 16; // Row padding 0/16
const double _kRowMin = 52; // Height = Regular
const double _kRowMinTall = 68; // Height = Tall (with a subtitle)
const double _kRowPadY = 5; // the kit's 50 pt content area keeps controls up to 42 tall inside a 52 row
const double _kGap = 16; // _Trailing gap
const double _kCardRadius = 26; // Grouped Table View r=26
const double _kMaxCardWidth = 648; // iPad: readable width
const double _kEditWidth = 37; // _Edit Buttons: 2 + 22 + 13

TextStyle _text(TextStyle base, Color color, {FontWeight? weight}) => base.copyWith(color: color, fontWeight: weight);

/// Draws the kit's row separator (Separators/Vibrant: #E6E6E6 plus-darker in Light, #1A1A1A plus-lighter in Dark).
class _Separator extends StatelessWidget {
  const _Separator();
  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _SeparatorPainter(theme.ios.separatorVibrant, theme.isDark ? BlendMode.plus : BlendMode.multiply),
    );
  }
}

class _SeparatorPainter extends CustomPainter {
  _SeparatorPainter(this.color, this.mode);
  final Color color;
  final BlendMode mode;
  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    Offset.zero & Size(size.width, 1),
    Paint()
      ..color = color
      ..blendMode = mode,
  );
  @override
  bool shouldRepaint(_SeparatorPainter old) => old.color != color || old.mode != mode;
}

/// Lets a 22 pt glyph button take taps in a 44 × 44 area without changing its layout size.
class _TapArea extends SingleChildRenderObjectWidget {
  const _TapArea({super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTapArea();
}

class _RenderTapArea extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final dx = math.max(0.0, (44 - size.width) / 2);
    final dy = math.max(0.0, (44 - size.height) / 2);
    if (!Rect.fromLTRB(-dx, -dy, size.width + dx, size.height + dy).contains(position)) return false;
    final inside = Offset(position.dx.clamp(0.0, size.width), position.dy.clamp(0.0, size.height));
    if (hitTestChildren(result, position: inside)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

/// A glyph [size] pt drawn like an SF Symbol: [icon] at 1.2 × size, centred in a [box].
Widget _glyph(IconData icon, double size, Color color, {Size? box, Offset offset = Offset.zero}) {
  final b = box ?? Size.square(size);
  return SizedBox(
    width: b.width,
    height: b.height,
    child: OverflowBox(
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Transform.translate(
        offset: offset,
        child: Icon(icon, size: size * 1.2, color: color),
      ),
    ),
  );
}

/// The kit's Semibold 17 chevron.right (7 × 12) and checkmark (15 × 14.5), drawn as strokes so they match the kit
/// (the icon font's versions are thinner). [scale] 1 = the 17 pt size.
enum _Stroke { chevron, checkmark }

Widget _strokeGlyph(_Stroke kind, Color color, {required Size box, double scale = 1, double dx = 0}) =>
    SizedBox.fromSize(
      size: box,
      child: CustomPaint(painter: _StrokePainter(kind, color, scale, dx)),
    );

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.kind, this.color, this.scale, this.dx);
  final _Stroke kind;
  final Color color;
  final double scale;
  final double dx;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset(dx, 0));
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    if (kind == _Stroke.chevron) {
      path
        ..moveTo(c.dx - 2.4 * scale, c.dy - 5 * scale)
        ..lineTo(c.dx + 2.4 * scale, c.dy)
        ..lineTo(c.dx - 2.4 * scale, c.dy + 5 * scale);
    } else {
      path
        ..moveTo(c.dx - 6.2 * scale, c.dy + 0.4 * scale)
        ..lineTo(c.dx - 2.1 * scale, c.dy + 5.2 * scale)
        ..lineTo(c.dx + 6.2 * scale, c.dy - 6.2 * scale);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.kind != kind || old.color != color || old.scale != scale || old.dx != dx;
}

// ---- List ---------------------------------------------------------------------------------------------------------

class _ListScope extends InheritedWidget {
  const _ListScope({required this.style, required this.editing, required this.openRow, required super.child});
  final IosListStyle style;
  final bool editing;
  final ValueNotifier<Object?> openRow;

  static _ListScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ListScope>();

  @override
  bool updateShouldNotify(_ListScope old) => old.style != style || old.editing != editing || old.openRow != openRow;
}

/// An iOS list (kit page "Lists"). Settings screens and forms are inset grouped lists of [IosListSection]s.
///
///     IosList(children: [
///       IosListSection(header: 'Network', footer: 'Applies to all networks.', children: [
///         IosListRow(title: 'Wi-Fi', detail: 'Home', icon: AppleIcons.wifi, onTap: openWifi),
///         IosListRow(title: 'Airplane Mode', icon: AppleIcons.bolt, iconColor: c.orange,
///             trailing: IosToggle(value: on, onChanged: setOn)),
///       ]),
///     ])
///
/// Plain list with a section index: `IosList(style: IosListStyle.plain, showIndex: true, children: [...])`
/// (the index letters come from each section's [IosListSection.indexTitle] or header).
/// [scrollable] null (default) = a scroll view on its own, a Column inside another vertical scroll view (an
/// [IosBarScaffold]'s children, a ListView); true / false force it.
class IosList extends StatefulWidget {
  const IosList({
    super.key,
    required this.children,
    this.style = IosListStyle.insetGrouped,
    this.editing = false,
    this.showIndex = false,
    this.scrollable,
    this.controller,
    this.padding,
  });

  /// [IosListSection]s.
  final List<Widget> children;
  final IosListStyle style;

  /// Edit mode: rows with onDelete show the red minus, rows with onSelectedChanged the selection circle, sections with
  /// onReorder the grabbers.
  final bool editing;

  /// Section index at the trailing edge (plain lists with many sections, like Contacts).
  final bool showIndex;
  final bool? scrollable;
  final ScrollController? controller;

  /// Extra padding around the sections (add the safe area / bars here).
  final EdgeInsets? padding;

  @override
  State<IosList> createState() => _IosListState();
}

class _IosListState extends State<IosList> {
  final ValueNotifier<Object?> _openRow = ValueNotifier<Object?>(null);
  final Map<int, GlobalKey> _sectionKeys = {};

  @override
  void didUpdateWidget(IosList old) {
    super.didUpdateWidget(old);
    if (widget.editing != old.editing) _openRow.value = null;
  }

  @override
  void dispose() {
    _openRow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    final inset = widget.style == IosListStyle.insetGrouped;
    final titles = <String>[];
    final children = <Widget>[];
    for (var i = 0; i < widget.children.length; i++) {
      Widget child = widget.children[i];
      final w = widget.children[i];
      if (widget.showIndex && w is IosListSection) {
        final t = w.indexTitle ?? w.header;
        if (t != null) {
          titles.add(t);
          child = KeyedSubtree(key: _sectionKeys.putIfAbsent(i, () => GlobalKey()), child: child);
        }
      }
      if (inset && i > 0) children.add(const SizedBox(height: 20));
      children.add(child);
    }
    final padding = (widget.padding ?? EdgeInsets.zero) + EdgeInsets.symmetric(vertical: inset ? 10 : 0);
    final outer = Scrollable.maybeOf(context);
    final scroll = widget.scrollable ?? !(outer != null && axisDirectionToAxis(outer.axisDirection) == Axis.vertical);
    Widget body = scroll
        ? ListView(controller: widget.controller, padding: padding, children: children)
        : Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          );
    if (widget.showIndex && titles.isNotEmpty) {
      final keys = [
        for (var i = 0; i < widget.children.length; i++)
          if (_sectionKeys.containsKey(i)) _sectionKeys[i]!,
      ];
      body = Stack(
        children: [
          body,
          PositionedDirectional(
            end: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: IosListIndex(
                titles: titles,
                onSelected: (i) {
                  final ctx = keys[i].currentContext;
                  if (ctx != null) Scrollable.ensureVisible(ctx);
                },
              ),
            ),
          ),
        ],
      );
    }
    return _ListScope(
      style: widget.style,
      editing: widget.editing,
      openRow: _openRow,
      child: ColoredBox(color: inset ? c.groupedBgPrimary : c.bgPrimary, child: body),
    );
  }
}

/// The section index (kit "Index Bar"): Medium 12 accent letters; iPhone 16 wide, 14 apart; iPad 30 wide, 25 apart.
/// Tap or drag along it to jump. [IosList] adds it for you with `showIndex: true`.
class IosListIndex extends StatelessWidget {
  const IosListIndex({super.key, required this.titles, required this.onSelected});
  final List<String> titles;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final regular = MediaQuery.sizeOf(context).width >= 744 && MediaQuery.sizeOf(context).height >= 600;
    final accent = AppleTheme.of(context).accentColor;
    final pitch = regular ? 25.0 : 14.0;
    final style = appleFont(size: 12).copyWith(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w500,
      color: accent,
      decoration: TextDecoration.none,
      leadingDistribution: TextLeadingDistribution.even,
    );
    void pick(double dy) => onSelected(((dy - 1) / pitch).floor().clamp(0, titles.length - 1));
    return Semantics(
      container: true,
      label: 'Section index',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => pick(d.localPosition.dy),
        onVerticalDragUpdate: (d) => pick(d.localPosition.dy),
        child: SizedBox(
          width: regular ? 30 : 16,
          height: titles.length * pitch + (16 - pitch),
          child: Stack(
            children: [
              for (var i = 0; i < titles.length; i++)
                Positioned(
                  left: 0,
                  right: 0,
                  top: i * pitch,
                  height: 16,
                  child: Text(titles[i], style: style, textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Section --------------------------------------------------------------------------------------------------------

/// Horizontal inset of an inset grouped card: --ios-margin (16 iPhone / 20 iPad), centred at most 648 wide (iPad).
double _cardInset(BuildContext context, double width) {
  final regular = MediaQuery.sizeOf(context).width >= 744 && MediaQuery.sizeOf(context).height >= 600;
  final margin = regular ? 20.0 : 16.0;
  return math.max(margin, (width - _kMaxCardWidth) / 2);
}

/// A section header (kit "Header"; Section Title in plain lists). [IosListSection] builds it from its header fields.
class IosListHeader extends StatelessWidget {
  const IosListHeader({
    super.key,
    required this.title,
    this.style = IosListHeaderStyle.nested,
    this.supertitle,
    this.subtitle,
    this.trailing,
    this.plain = false,
  });
  final String title;
  final IosListHeaderStyle style;
  final String? supertitle;
  final String? subtitle;

  /// Trailing accessory: [IosListHeaderAction], an image, a round icon button.
  final Widget? trailing;

  /// Plain-list metrics (kit "Section Title": padding 8/16/9).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    final t = IosTypography.of(context);
    final titleStyle = switch (style) {
      IosListHeaderStyle.nested => _text(t.headline, c.labelSecondary),
      IosListHeaderStyle.prominent => _text(t.title3Emphasized, c.labelPrimary, weight: FontWeight.w600),
      IosListHeaderStyle.extraProminent => _text(t.title2Emphasized, c.labelPrimary, weight: FontWeight.w700),
    };
    final small = _text(t.subheadline, c.labelSecondary);
    return Semantics(
      header: true,
      child: Padding(
        padding: plain ? const EdgeInsets.fromLTRB(16, 8, 16, 9) : const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (supertitle != null) Text(supertitle!, style: small),
                  Text(title, style: titleStyle),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: small),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 16),
              Padding(
                padding: EdgeInsets.only(bottom: style == IosListHeaderStyle.extraProminent ? 1 : 0),
                child: trailing!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A header accessory (kit "_Header Trailing Accessories"): an accent text button ("See All", "Edit", Regular 15),
/// or with [icon] a 44 pt round button (accent 5% fill).
class IosListHeaderAction extends StatefulWidget {
  const IosListHeaderAction({super.key, this.label, this.icon, this.semanticLabel, required this.onPressed})
    : assert(label != null || icon != null);
  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  @override
  State<IosListHeaderAction> createState() => _IosListHeaderActionState();
}

class _IosListHeaderActionState extends State<IosListHeaderAction> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final t = IosTypography.of(context);
    final enabled = widget.onPressed != null;
    final color = enabled ? theme.accentColor : theme.ios.labelTertiary;
    final Widget child = widget.icon != null && widget.label == null
        ? Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: theme.accentColor.withValues(alpha: 0.05)),
            child: Center(child: _glyph(widget.icon!, 17, color)),
          )
        : Text(widget.label!, style: _text(t.subheadline, color));
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      child: _TapArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: Opacity(opacity: _pressed ? 0.35 : 1, child: child),
        ),
      ),
    );
  }
}

class _RowSlot extends InheritedWidget {
  const _RowSlot({
    required this.index,
    required this.count,
    required this.showSeparator,
    required this.reorder,
    required super.child,
  });
  final int index;
  final int count;
  final bool showSeparator;
  final bool reorder;
  static _RowSlot? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_RowSlot>();
  @override
  bool updateShouldNotify(_RowSlot old) =>
      old.index != index || old.count != count || old.showSeparator != showSeparator || old.reorder != reorder;
}

/// One section of an [IosList]: optional header, the rows ([IosListRow]), optional footer.
///
///     IosListSection(header: 'Sort By', footer: 'Applies to all folders.', children: [ … rows … ])
///     IosListSection(header: 'Inbox', headerStyle: IosListHeaderStyle.prominent,
///         headerTrailing: IosListHeaderAction(label: 'Edit', onPressed: edit), children: [ … ])
///
/// Reorder in edit mode: give every row a key and pass [onReorder] (from, to are final indexes).
class IosListSection extends StatefulWidget {
  const IosListSection({
    super.key,
    this.header,
    this.headerStyle = IosListHeaderStyle.nested,
    this.supertitle,
    this.subtitle,
    this.headerTrailing,
    this.footer,
    this.collapsible = false,
    this.initiallyExpanded = true,
    this.indexTitle,
    this.onReorder,
    this.margin,
    this.children = const [],
  });
  final String? header;
  final IosListHeaderStyle headerStyle;
  final String? supertitle;
  final String? subtitle;
  final Widget? headerTrailing;

  /// Explains the settings above it (Regular 13, secondary).
  final String? footer;

  /// A "Show Less / Show More" toggle with a chevron in the header (kit "Disclosure Open").
  final bool collapsible;
  final bool initiallyExpanded;

  /// Letter for the list's section index. Defaults to [header].
  final String? indexTitle;
  final void Function(int from, int to)? onReorder;

  /// Inset grouped only: the card's side margin. Null = automatic (16 iPhone / 20 iPad, centred at most 648 wide on
  /// iPad). 0 = flush: for cards in your own grid (Summary dashboards), where the grid's padding and gaps do the spacing.
  final double? margin;
  final List<Widget> children;

  @override
  State<IosListSection> createState() => _IosListSectionState();
}

class _IosListSectionState extends State<IosListSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final scope = _ListScope.maybeOf(context);
    final style = scope?.style ?? IosListStyle.insetGrouped;
    final inset = style == IosListStyle.insetGrouped;
    final c = AppleTheme.of(context).ios;
    final t = IosTypography.of(context);
    final reorder = (scope?.editing ?? false) && widget.onReorder != null;
    final hasHeader = widget.header != null || widget.headerTrailing != null || widget.collapsible;
    final count = widget.children.length;

    Widget slot(int i, Widget row) =>
        _RowSlot(index: i, count: count, showSeparator: i > 0 || (!inset && hasHeader), reorder: reorder, child: row);

    Widget rows;
    if (reorder) {
      rows = ReorderableList(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        proxyDecorator: (child, i, anim) => child,
        onReorderItem: (from, to) => widget.onReorder!(from, to),
        itemBuilder: (context, i) {
          final row = widget.children[i];
          return KeyedSubtree(key: row.key ?? ValueKey(i), child: slot(i, row));
        },
      );
    } else {
      rows = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < count; i++) slot(i, widget.children[i])],
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        final dx = inset ? (widget.margin ?? _cardInset(context, box.maxWidth)) : 0.0;
        final toggle = widget.collapsible
            ? _SectionToggle(expanded: _expanded, onPressed: () => setState(() => _expanded = !_expanded))
            : null;
        final trailing = toggle == null
            ? widget.headerTrailing
            : widget.headerTrailing == null
            ? toggle
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [toggle, const SizedBox(width: 16), widget.headerTrailing!],
              );
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: dx),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasHeader)
                Padding(
                  padding: EdgeInsets.only(bottom: inset ? 10 : 0),
                  child: ColoredBox(
                    color: inset ? const Color(0x00000000) : c.bgPrimary,
                    child: IosListHeader(
                      title: widget.header ?? '',
                      style: widget.headerStyle,
                      supertitle: widget.supertitle,
                      subtitle: widget.subtitle,
                      trailing: trailing,
                      plain: !inset,
                    ),
                  ),
                ),
              if (_expanded && count > 0)
                inset
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(_kCardRadius),
                        child: ColoredBox(color: c.groupedBgSecondary, child: rows),
                      )
                    : rows,
              if (_expanded && widget.footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Text(widget.footer!, style: _text(t.footnote, c.labelSecondary)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionToggle extends StatelessWidget {
  const _SectionToggle({required this.expanded, required this.onPressed});
  final bool expanded;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final t = IosTypography.of(context);
    return Semantics(
      container: true,
      button: true,
      expanded: expanded,
      child: _TapArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(expanded ? 'Show Less' : 'Show More', style: _text(t.body, theme.ios.labelSecondary)),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: _strokeGlyph(_Stroke.chevron, theme.accentColor, box: const Size(12, 22), scale: 19 / 17),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Row ------------------------------------------------------------------------------------------------------------

/// One list row (kit "Row"): 52 tall, 68 with a subtitle. Put it in an [IosListSection].
///
///     IosListRow(title: 'Wi-Fi', detail: 'Home', icon: AppleIcons.wifi, onTap: openWifi)            navigation (chevron)
///     IosListRow(title: 'Name', checked: sort == 'name', onTap: () => setSort('name'))             checkmark choice
///     IosListRow(title: 'Notifications', trailing: IosToggle(value: n, onChanged: setN))          a control
///     IosListRow.action(label: 'Sign Out', destructive: true, onTap: signOut)                       action row
///     IosListRow(title: 'Anna', subtitle: 'Lunch?', onDelete: remove,
///         trailingActions: [IosSwipeAction(label: 'Flag', icon: AppleIcons.flag, color: c.orange, onPressed: flag)])
class IosListRow extends StatefulWidget {
  const IosListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.titleMaxLines,
    this.subtitleMaxLines,
    this.detail,
    this.icon,
    this.iconColor,
    this.image,
    this.imageStyle = IosListImageStyle.rounded,
    this.symbol,
    this.chevron,
    this.onTap,
    this.onInfo,
    this.checked,
    this.expanded,
    this.trailing,
    this.buttonLabel,
    this.onButtonPressed,
    this.popupValue,
    this.onPopupPressed,
    this.leadingActions = const [],
    this.trailingActions = const [],
    this.onDelete,
    this.deleteLabel = 'Delete',
    this.selected,
    this.onSelectedChanged,
    this.enabled = true,
    this.highlighted = false,
    this.semanticLabel,
  }) : action = false,
       destructive = false,
       center = false;

  /// An action row (kit "Row - Button"): the label in accent (red when [destructive]), leading or [center]ed.
  const IosListRow.action({
    super.key,
    required String label,
    required this.onTap,
    this.destructive = false,
    this.center = false,
    this.enabled = true,
    this.leadingActions = const [],
    this.trailingActions = const [],
    this.semanticLabel,
  }) : title = label,
       action = true,
       highlighted = false,
       subtitle = null,
       titleMaxLines = null,
       subtitleMaxLines = null,
       detail = null,
       icon = null,
       iconColor = null,
       image = null,
       imageStyle = IosListImageStyle.rounded,
       symbol = null,
       chevron = false,
       onInfo = null,
       checked = null,
       expanded = null,
       trailing = null,
       buttonLabel = null,
       onButtonPressed = null,
       popupValue = null,
       onPopupPressed = null,
       onDelete = null,
       deleteLabel = 'Delete',
       selected = null,
       onSelectedChanged = null;

  /// Main text (Regular 17).
  final String title;

  /// Second line (Regular 15, secondary): makes the row 68 tall.
  final String? subtitle;

  /// Null = wrap (iOS default, needed for large Dynamic Type sizes). 1 = one line ending in "…" (note previews,
  /// message subjects).
  final int? titleMaxLines;
  final int? subtitleMaxLines;

  /// Trailing value (Regular 17, secondary): the current setting ("Home", "On").
  final String? detail;

  /// Settings-style icon tile: a white symbol on a 30 pt rounded square in [iconColor] (default accent).
  /// With [imageStyle] symbol: an accent symbol without a tile.
  final IconData? icon;
  final Color? iconColor;

  /// A leading picture ([imageStyle] fill, circle or rounded).
  final ImageProvider? image;
  final IosListImageStyle imageStyle;

  /// Trailing accent symbol (kit "Symbol").
  final IconData? symbol;

  /// Drill-in chevron. Default: shown when the row has [onTap] (navigation) and no checkmark, control or action.
  final bool? chevron;
  final VoidCallback? onTap;

  /// Info button (info.circle, accent) before the chevron.
  final VoidCallback? onInfo;

  /// Checkmark row: non-null makes it a choice; true shows the checkmark.
  final bool? checked;

  /// Expandable row: the accent chevron turns down when true (show the expanded content in the next row).
  final bool? expanded;

  /// A control on the trailing side: IosToggle, IosStepper, IosDatePicker, a pop-up button…
  final Widget? trailing;

  /// Trailing text button (kit "Button").
  final String? buttonLabel;
  final VoidCallback? onButtonPressed;

  /// Pop-up menu value (kit "Pop-up"): secondary text + chevron.up.chevron.down. Open your menu in [onPopupPressed].
  final String? popupValue;
  final VoidCallback? onPopupPressed;

  /// Swipe actions. Trailing = swipe left (the last one runs on a long swipe).
  final List<IosSwipeAction> leadingActions;
  final List<IosSwipeAction> trailingActions;

  /// Delete: adds a red Delete swipe action and the red minus in edit mode.
  final VoidCallback? onDelete;
  final String deleteLabel;

  /// Edit-mode selection circle.
  final bool? selected;
  final ValueChanged<bool>? onSelectedChanged;

  final bool action;
  final bool destructive;
  final bool center;
  final bool enabled;

  /// The row is the one shown in the detail column (iPad split view: the open note / message). Draws the grey
  /// selection fill (the same as a selected sidebar row); its text keeps its colours. Not the edit-mode [selected].
  final bool highlighted;
  final String? semanticLabel;

  @override
  State<IosListRow> createState() => _IosListRowState();
}

class _IosListRowState extends State<IosListRow> {
  bool _pressed = false;

  List<IosSwipeAction> get _trailingActions => widget.trailingActions.isNotEmpty || widget.onDelete == null
      ? widget.trailingActions
      : [
          IosSwipeAction(
            label: widget.deleteLabel,
            icon: AppleIcons.trash,
            destructive: true,
            onPressed: widget.onDelete,
          ),
        ];

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final t = IosTypography.of(context);
    final scope = _ListScope.maybeOf(context);
    final slot = _RowSlot.maybeOf(context);
    final editing = scope?.editing ?? false;
    final tall = widget.subtitle != null;
    final enabled = widget.enabled;
    final accent = theme.accentColor;

    // Leading parts --------------------------------------------------------------------------
    final showRemove = editing && widget.onDelete != null;
    final showSelect = editing && widget.onSelectedChanged != null;
    double imageW = 0;
    Widget? image;
    if (widget.icon != null && widget.imageStyle != IosListImageStyle.symbol) {
      imageW = tall ? 44 : 30;
      image = Container(
        width: imageW,
        height: imageW,
        decoration: ShapeDecoration(
          color: widget.iconColor ?? accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tall ? 11 : 7)),
        ),
        child: Center(child: _glyph(widget.icon!, 17, const Color(0xFFFFFFFF))),
      );
    } else if (widget.icon != null) {
      imageW = 28;
      image = _glyph(widget.icon!, 20, widget.iconColor ?? accent, box: const Size(28, 20));
    } else if (widget.image != null) {
      final (w, shape) = switch (widget.imageStyle) {
        IosListImageStyle.fill => (tall ? 68.0 : 52.0, const RoundedRectangleBorder()),
        IosListImageStyle.circle => (tall ? 60.0 : 42.0, const CircleBorder()),
        _ => (tall ? 44.0 : 30.0, RoundedRectangleBorder(borderRadius: BorderRadius.circular(tall ? 11 : 7))),
      };
      imageW = w;
      image = Container(
        width: w,
        height: w,
        decoration: ShapeDecoration(
          image: DecorationImage(image: widget.image!, fit: BoxFit.cover),
          shape: shape,
        ),
      );
    }

    // Text ------------------------------------------------------------------------------------
    final Color titleColor = widget.action
        ? (!enabled
              ? c.gray2
              : widget.destructive
              ? c.red
              : accent)
        : (enabled ? c.labelPrimary : c.labelTertiary);
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: _text(t.body, titleColor),
          textAlign: widget.center ? TextAlign.center : TextAlign.start,
          maxLines: widget.titleMaxLines,
          overflow: widget.titleMaxLines == null ? null : TextOverflow.ellipsis,
        ),
        if (widget.subtitle != null)
          Text(
            widget.subtitle!,
            style: _text(t.subheadline, c.labelSecondary),
            maxLines: widget.subtitleMaxLines,
            overflow: widget.subtitleMaxLines == null ? null : TextOverflow.ellipsis,
          ),
      ],
    );

    // Trailing parts ----------------------------------------------------------------------------
    final reorder = slot?.reorder ?? false;
    final isChoice = widget.checked != null;
    final showChevron =
        widget.chevron ??
        (widget.onTap != null && !isChoice && !widget.action && widget.expanded == null && widget.trailing == null);
    final trailing = <Widget>[
      if (widget.detail != null)
        _MaxFraction(
          fraction: 0.6, // a long detail truncates; the title keeps at least 40 %
          child: Text(
            widget.detail!,
            style: _text(t.body, c.labelSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      if (widget.symbol != null) _glyph(widget.symbol!, 18.5, accent, box: const Size(22, 22)),
      if (widget.popupValue != null) _Popup(value: widget.popupValue!, onPressed: widget.onPopupPressed),
      if (widget.buttonLabel != null)
        _TextButton(label: widget.buttonLabel!, color: accent, onPressed: widget.onButtonPressed),
      if (widget.trailing != null) widget.trailing!,
      if (widget.onInfo != null) _InfoButton(onPressed: widget.onInfo!),
      if (widget.checked == true) _strokeGlyph(_Stroke.checkmark, c.labelPrimary, box: const Size(22, 22)),
      if (widget.expanded != null)
        AnimatedRotation(
          turns: widget.expanded! ? 0.25 : 0,
          duration: const Duration(milliseconds: 200),
          child: _strokeGlyph(_Stroke.chevron, accent, box: const Size(8, 22)),
        ),
      if (showChevron && !editing) _strokeGlyph(_Stroke.chevron, c.labelTertiary, box: const Size(8, 22), dx: 2),
    ];
    final children = <Widget>[];
    for (var i = 0; i < trailing.length; i++) {
      // Kit gaps: 16 between accessories; 12 between the detail and the accent disclosure chevron.
      if (children.isNotEmpty || i > 0) {
        children.add(SizedBox(width: widget.expanded != null && i == trailing.length - 1 ? 12 : _kGap));
      }
      children.add(trailing[i]);
    }
    if (reorder && slot != null) {
      children.add(const SizedBox(width: 12));
      children.add(
        ReorderableDragStartListener(
          index: slot.index,
          child: Semantics(
            container: true,
            label: 'Reorder ${widget.title}',
            child: _glyph(AppleIcons.line3Horizontal, 17, c.labelTertiary, box: const Size(22, 25)),
          ),
        ),
      );
    }

    final body = LayoutBuilder(
      builder: (context, box) => _BodyWidth(
        width: box.maxWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: _kRowPadY),
          child: Row(
            children: [
              widget.center ? Expanded(child: Center(child: text)) : Expanded(child: text),
              if (children.isNotEmpty) const SizedBox(width: _kGap),
              ...children,
            ],
          ),
        ),
      ),
    );

    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: tall ? _kRowMinTall : _kRowMin),
      child: Row(
        children: [
          const SizedBox(width: _kRowPadX),
          if (showRemove || showSelect)
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 13),
              child: showRemove
                  ? _EditCircle(
                      color: c.red,
                      icon: AppleIcons.minus,
                      semanticLabel: '${widget.deleteLabel} ${widget.title}',
                    )
                  : _SelectCircle(
                      selected: widget.selected ?? false,
                      onChanged: widget.onSelectedChanged!,
                      label: widget.title,
                    ),
            ),
          if (image != null) ...[image, const SizedBox(width: 8)],
          Expanded(child: body),
          const SizedBox(width: _kRowPadX),
        ],
      ),
    );

    final separatorStart = _kRowPadX + (showRemove || showSelect ? _kEditWidth : 0) + (image != null ? imageW + 8 : 0);
    final showSeparator = slot?.showSeparator ?? true;
    final bg = _pressed
        ? c.gray5
        : widget.highlighted
        ? (theme.isDark ? const Color(0x21FFFFFF) : const Color(0x12000000)) // the sidebar selection fill
        : const Color(0x00000000);
    Widget cell = ColoredBox(
      color: bg,
      child: Stack(
        children: [
          row,
          if (showSeparator)
            PositionedDirectional(start: separatorStart, end: _kRowPadX, top: 0, height: 1, child: const _Separator()),
        ],
      ),
    );

    final tappable = widget.onTap != null && enabled && !(editing && !widget.action);
    if (tappable) {
      cell = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: cell,
      );
    }
    cell = Semantics(
      container: true,
      button: tappable,
      enabled: enabled,
      selected: widget.checked,
      checked: isChoice ? widget.checked : null,
      expanded: widget.expanded,
      label: widget.semanticLabel,
      child: cell,
    );

    final trailingActions = _trailingActions;
    if (enabled && (widget.leadingActions.isNotEmpty || trailingActions.isNotEmpty)) {
      return IosSwipeActions(
        leading: widget.leadingActions,
        trailing: trailingActions,
        stacked: tall,
        enabled: !editing,
        child: cell,
      );
    }
    return cell;
  }
}

/// The red minus of edit mode: opens the row's trailing swipe actions (its Delete action).
/// Limits its child to [fraction] of the row width (passed down by the row body's LayoutBuilder).
class _MaxFraction extends StatelessWidget {
  const _MaxFraction({required this.fraction, required this.child});
  final double fraction;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final width = _BodyWidth.maybeOf(context) ?? double.infinity;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width * fraction),
      child: child,
    );
  }
}

class _BodyWidth extends InheritedWidget {
  const _BodyWidth({required this.width, required super.child});
  final double width;
  static double? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_BodyWidth>()?.width;
  @override
  bool updateShouldNotify(_BodyWidth old) => old.width != width;
}

class _EditCircle extends StatelessWidget {
  const _EditCircle({required this.color, required this.icon, required this.semanticLabel});
  final Color color;
  final IconData icon;
  final String semanticLabel;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: semanticLabel,
    excludeSemantics: true,
    child: _TapArea(
      child: GestureDetector(
        onTap: () => _SwipeScope.maybeOf(context)?.toggle(IosSwipeSide.trailing),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Center(child: _glyph(icon, 12.5, const Color(0xFFFFFFFF))),
        ),
      ),
    ),
  );
}

class _SelectCircle extends StatelessWidget {
  const _SelectCircle({required this.selected, required this.onChanged, required this.label});
  final bool selected;
  final ValueChanged<bool> onChanged;
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    return Semantics(
      container: true,
      checked: selected,
      label: 'Select $label',
      excludeSemantics: true,
      child: _TapArea(
        child: GestureDetector(
          onTap: () => onChanged(!selected),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? theme.accentColor : null,
              border: selected ? null : Border.all(color: theme.ios.gray3, width: 1.5),
            ),
            child: selected
                ? _strokeGlyph(_Stroke.checkmark, const Color(0xFFFFFFFF), box: const Size(22, 22), scale: 0.82)
                : null,
          ),
        ),
      ),
    );
  }
}

class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: 'More Info',
    excludeSemantics: true,
    child: _TapArea(
      child: GestureDetector(
        onTap: onPressed,
        child: _glyph(AppleIcons.infoCircle, 18.5, AppleTheme.of(context).accentColor, box: const Size(22, 22)),
      ),
    ),
  );
}

class _TextButton extends StatefulWidget {
  const _TextButton({required this.label, required this.color, required this.onPressed});
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  @override
  State<_TextButton> createState() => _TextButtonState();
}

class _TextButtonState extends State<_TextButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    child: _TapArea(
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: Opacity(
          opacity: _pressed ? 0.35 : 1,
          child: Text(widget.label, style: _text(IosTypography.of(context).body, widget.color)),
        ),
      ),
    ),
  );
}

class _Popup extends StatelessWidget {
  const _Popup({required this.value, required this.onPressed});
  final String value;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final color = AppleTheme.of(context).ios.labelSecondary;
    return Semantics(
      container: true,
      button: true,
      value: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: _text(IosTypography.of(context).body, color)),
              const SizedBox(width: 10),
              _glyph(AppleIcons.chevronUpDown, 13, color, box: const Size(13, 22)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Swipe actions ----------------------------------------------------------------------------------------------------

/// One swipe action of a row (kit "_Swipe Actions"): a coloured capsule with a symbol and/or a label.
class IosSwipeAction {
  const IosSwipeAction({
    required this.label,
    this.icon,
    this.color,
    this.destructive = false,
    this.iconOnly = false,
    required this.onPressed,
  });

  /// Accessible name; shown next to (or, in tall rows, under) the symbol unless [iconOnly].
  final String label;
  final IconData? icon;

  /// Capsule colour. Default Gray 2; red when [destructive]. Use system colours: c.orange, c.blue, c.green, accent.
  final Color? color;
  final bool destructive;
  final bool iconOnly;
  final VoidCallback? onPressed;
}

class _SwipeScope extends InheritedWidget {
  const _SwipeScope({required this.toggle, required super.child});
  final void Function(IosSwipeSide side) toggle;
  static _SwipeScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<_SwipeScope>();
  @override
  bool updateShouldNotify(_SwipeScope old) => false;
}

/// Swipe actions around a row (kit "Row with Swipe Actions"). [IosListRow] adds it for you when it has actions;
/// use it directly to wrap your own row widget.
///
///     IosSwipeActions(
///       trailing: [IosSwipeAction(label: 'Delete', icon: AppleIcons.trash, destructive: true, onPressed: remove)],
///       child: myRow,
///     )
/// Swipe left/right to reveal; past half of the actions it stays open; past 60 % of the row it runs the edge action.
/// Tapping the row, an action, or another row closes it. [initialOpen] shows it open (screenshots, onboarding).
class IosSwipeActions extends StatefulWidget {
  const IosSwipeActions({
    super.key,
    required this.child,
    this.leading = const [],
    this.trailing = const [],
    this.stacked = false,
    this.enabled = true,
    this.initialOpen,
  });
  final Widget child;
  final List<IosSwipeAction> leading;
  final List<IosSwipeAction> trailing;

  /// Label under the symbol (kit "Symbol and Label Stacked", for 68 pt rows with a subtitle).
  final bool stacked;
  final bool enabled;
  final IosSwipeSide? initialOpen;

  @override
  State<IosSwipeActions> createState() => _IosSwipeActionsState();
}

class _IosSwipeActionsState extends State<IosSwipeActions> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController.unbounded(vsync: this, value: 0);
  ValueNotifier<Object?>? _openRow;
  bool _initialApplied = false;
  double _width = 400;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final n = _ListScope.maybeOf(context)?.openRow;
    if (n != _openRow) {
      _openRow?.removeListener(_onOtherOpened);
      _openRow = n?..addListener(_onOtherOpened);
    }
  }

  @override
  void dispose() {
    _openRow?.removeListener(_onOtherOpened);
    _anim.dispose();
    super.dispose();
  }

  void _onOtherOpened() {
    if (_openRow?.value != this && _anim.value != 0) _settle(0);
  }

  double _actionWidth(IosSwipeAction a, TextStyle labelStyle) {
    if (widget.stacked || a.iconOnly || a.icon != null && a.label.isEmpty) return 60;
    final tp = TextPainter(
      text: TextSpan(text: a.label, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final content = (a.icon != null ? 16 + 8 : 0) + tp.width;
    return math.max(84.0, content + 24);
  }

  double _openOffset(IosSwipeSide side, TextStyle labelStyle) {
    final actions = side == IosSwipeSide.trailing ? widget.trailing : widget.leading;
    if (actions.isEmpty) return 0;
    final w = actions.map((a) => _actionWidth(a, labelStyle)).reduce((a, b) => a + b) + 10 * (actions.length - 1) + 26;
    return side == IosSwipeSide.trailing ? -w : w;
  }

  void _settle(double target) {
    _anim.animateTo(target, duration: const Duration(milliseconds: 300), curve: const Cubic(0.2, 0.9, 0.3, 1));
    if (target != 0) _openRow?.value = this;
  }

  void _toggle(IosSwipeSide side, TextStyle labelStyle) {
    if (_anim.value != 0) {
      _settle(0);
    } else {
      _settle(_openOffset(side, labelStyle));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.ios;
    final t = IosTypography.of(context);
    final style = _ListScope.maybeOf(context)?.style;
    final labelStyle = _text(t.footnote, const Color(0xFFFFFFFF)).copyWith(height: 15 / 13);
    final trailingOpen = _openOffset(IosSwipeSide.trailing, labelStyle);
    final leadingOpen = _openOffset(IosSwipeSide.leading, labelStyle);
    if (widget.initialOpen != null && !_initialApplied) {
      _initialApplied = true;
      _anim.value = widget.initialOpen == IosSwipeSide.trailing ? trailingOpen : leadingOpen;
    }
    final x = _anim.value;
    final open = x != 0;
    // Track (behind) and row (capsule) colours while open: kit component / inset grouped / plain list.
    final (track, cellBg) = switch (style) {
      IosListStyle.plain => (c.bgPrimary, c.gray5),
      IosListStyle.insetGrouped => (c.groupedBgPrimary, c.groupedBgSecondary),
      null => (c.bgSecondary, c.bgPrimary),
    };

    Widget actionsRow(List<IosSwipeAction> actions) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          _ActionCapsule(
            action: actions[i],
            stacked: widget.stacked,
            width: _actionWidth(actions[i], labelStyle),
            onDone: () => _settle(0),
          ),
        ],
      ],
    );

    return _SwipeScope(
      toggle: (side) => _toggle(side, labelStyle),
      child: LayoutBuilder(
        builder: (context, box) {
          _width = box.maxWidth.isFinite ? box.maxWidth : 400;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: widget.enabled
                ? (d) {
                    _anim.stop();
                    _openRow?.value = this;
                  }
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (d) {
                    var v = _anim.value + d.delta.dx;
                    if ((v < 0 && widget.trailing.isEmpty) || (v > 0 && widget.leading.isEmpty)) v = 0;
                    _anim.value = v;
                  }
                : null,
            onHorizontalDragEnd: widget.enabled
                ? (d) {
                    final v = _anim.value;
                    final side = v < 0 ? IosSwipeSide.trailing : IosSwipeSide.leading;
                    final openAt = side == IosSwipeSide.trailing ? trailingOpen : leadingOpen;
                    if (v.abs() > _width * 0.6) {
                      final actions = side == IosSwipeSide.trailing ? widget.trailing : widget.leading;
                      final edge = side == IosSwipeSide.trailing ? actions.last : actions.first;
                      _settle(0);
                      edge.onPressed?.call();
                    } else if (v != 0 && v.abs() > openAt.abs() / 2) {
                      _settle(openAt);
                    } else {
                      _settle(0);
                    }
                  }
                : null,
            onTap: open ? () => _settle(0) : null,
            child: ClipRect(
              child: Stack(
                children: [
                  if (open) Positioned.fill(child: ColoredBox(color: track)),
                  if (x < 0)
                    PositionedDirectional(
                      end: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(child: actionsRow(widget.trailing)),
                    ),
                  if (x > 0)
                    PositionedDirectional(
                      start: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(child: actionsRow(widget.leading)),
                    ),
                  Transform.translate(
                    offset: Offset(x, 0),
                    child: open
                        ? IgnorePointer(
                            child: DecoratedBox(
                              decoration: ShapeDecoration(color: cellBg, shape: const StadiumBorder()),
                              child: ClipPath(
                                clipper: const ShapeBorderClipper(shape: StadiumBorder()),
                                child: widget.child,
                              ),
                            ),
                          )
                        : widget.child,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActionCapsule extends StatefulWidget {
  const _ActionCapsule({required this.action, required this.stacked, required this.width, required this.onDone});
  final IosSwipeAction action;
  final bool stacked;
  final double width;
  final VoidCallback onDone;
  @override
  State<_ActionCapsule> createState() => _ActionCapsuleState();
}

class _ActionCapsuleState extends State<_ActionCapsule> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).ios;
    final t = IosTypography.of(context);
    final a = widget.action;
    final color = a.destructive ? c.red : (a.color ?? c.gray2);
    const white = Color(0xFFFFFFFF);
    final showLabel = !a.iconOnly || a.icon == null;
    Widget content;
    if (widget.stacked) {
      content = SizedBox(
        width: 60,
        height: 68,
        child: Column(
          children: [
            const SizedBox(height: 6),
            Container(
              width: 60,
              height: 38,
              decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
              child: Center(child: a.icon != null ? _glyph(a.icon!, 17, white) : null),
            ),
            const SizedBox(height: 5),
            if (showLabel)
              Text(
                a.label,
                style: _text(t.footnote, c.labelSecondary, weight: FontWeight.w500).copyWith(height: 15 / 13),
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
              ),
          ],
        ),
      );
    } else {
      content = Container(
        width: widget.width,
        height: 44,
        decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (a.icon != null) _glyph(a.icon!, showLabel ? 16 : 17, white, box: Size(showLabel ? 15 : 20, 20)),
            if (a.icon != null && showLabel) const SizedBox(width: 8),
            if (showLabel)
              Text(a.label, style: _text(t.footnote, white).copyWith(height: 15 / 13), maxLines: 1, softWrap: false),
          ],
        ),
      );
    }
    if (_pressed) {
      content = ColorFiltered(
        colorFilter: const ColorFilter.mode(Color(0x1F000000), BlendMode.srcATop),
        child: content,
      );
    }
    return Semantics(
      container: true,
      button: true,
      label: a.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          a.onPressed?.call();
          widget.onDone();
        },
        child: content,
      ),
    );
  }
}
