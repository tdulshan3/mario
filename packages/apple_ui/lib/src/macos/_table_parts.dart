// The drawing parts of macOS tables, outlines and lists (lists-and-tables.css): 20 px rows with an inset (10 px),
// rounded (8 px) background, column headers with separators and the sort indicator, group titles, disclosure
// chevrons, the kit's folder icon. Private to apple_ui (not exported); MacTable / MacList put them together.

import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter/widgets.dart';

import '../core/mac_support.dart';
import '../core/theme.dart';
import '_glyphs.dart';
import '_text_input.dart' show macFieldTextStyle;

/// Kit metrics (lists-and-tables.css).
class MacTableMetrics {
  MacTableMetrics._();
  static const rowHeight = 20.0;
  static const inset = 10.0; // row background inset from the view edge
  static const radius = 8.0;
  static const indent = 15.0; // outline indent per level
  static const headerHeight = 31.0; // 4 + 19 + 5, then a 3 px gap before the first row
  static const groupHeight = 45.0; // 24 + 14 + 7
  static const chevronSlot = 13.0; // 9 px chevron + 4 px gap
  static const iconSlot = 18.0;

  /// Where header titles and group titles start, after the 10 px inset: 6 · 28 with icons · 40 in an outline.
  static double lead({required bool outline, required bool icons}) => outline ? 40 : (icons ? 28 : 6);
}

/// Fill and text colours of one row.
class MacRowLook {
  const MacRowLook(this.fill, this.primary, this.secondary);
  final Color fill;
  final Color primary;
  final Color secondary;

  static MacRowLook of(BuildContext context, {required bool selected, required bool alternate}) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    if (selected) {
      if (MacWindowState.isInactive(context)) return MacRowLook(c.selectionInactive, c.labelPrimary, c.labelSecondary);
      return MacRowLook(macSelectionColor(theme), c.labelWhite, c.labelWhite);
    }
    return MacRowLook(alternate ? c.tableRowAlternate : const Color(0x00000000), c.labelPrimary, c.labelSecondary);
  }
}

/// The selected-row colour: the kit's #0165E2 / #0158D2 with the default accent; another accent 85 % mixed with black.
Color macSelectionColor(AppleThemeData theme) {
  final accent = theme.accent;
  if (accent == null || accent == theme.mac.accentBlue) return theme.mac.selection;
  return Color.from(alpha: accent.a, red: accent.r * 0.85, green: accent.g * 0.85, blue: accent.b * 0.85);
}

/// Row text: 13 px Medium, 16 px line.
TextStyle macRowTextStyle(BuildContext context, Color color, {bool numeric = false}) {
  final s = macFieldTextStyle(context, fontSize: 13, color: color);
  return numeric ? s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]) : s;
}

/// One column of a row: its width (the first and last include the 10 px inset) and alignment.
class MacCellSpec {
  const MacCellSpec({required this.width, this.numeric = false});
  final double width;
  final bool numeric;
}

/// A table / outline row. [cells][0] is the first column's text widget (or any widget); the others are cells.
class MacTableRowView extends StatelessWidget {
  const MacTableRowView({
    super.key,
    required this.specs,
    required this.cells,
    this.selected = false,
    this.alternate = false,
    this.joinTop = false,
    this.joinBottom = false,
    this.outline = false,
    this.level = 0,
    this.expanded,
    this.onDisclosure,
    this.icon,
  });

  final List<MacCellSpec> specs;
  final List<Widget> cells;
  final bool selected;
  final bool alternate;

  /// Adjacent selected rows join into one block: no rounded corners on the joined side.
  final bool joinTop;
  final bool joinBottom;

  /// Outline: room for the chevron in every row, [level] × 15 px indent.
  final bool outline;
  final int level;

  /// Null = no chevron (a leaf). True / false = open / closed.
  final bool? expanded;
  final void Function(bool altPressed)? onDisclosure;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final look = MacRowLook.of(context, selected: selected, alternate: alternate);
    const r = Radius.circular(MacTableMetrics.radius);
    final fill = DecoratedBox(
      decoration: BoxDecoration(
        color: look.fill,
        borderRadius: BorderRadius.only(
          topLeft: joinTop ? Radius.zero : r,
          topRight: joinTop ? Radius.zero : r,
          bottomLeft: joinBottom ? Radius.zero : r,
          bottomRight: joinBottom ? Radius.zero : r,
        ),
      ),
    );
    final n = specs.length;
    final children = <Widget>[];
    for (var i = 0; i < n; i++) {
      final spec = specs[i];
      final first = i == 0;
      final last = i == n - 1;
      final color = first ? look.primary : look.secondary;
      // Paddings: first cell 10 inset + 6 (+ indent); others 8 / 8; last cell 6 + 10 inset; numbers 16 on the right.
      final left = first ? MacTableMetrics.inset + 6 + (outline ? level * MacTableMetrics.indent : 0) : 8.0;
      final right = last ? 6 + MacTableMetrics.inset : (spec.numeric ? 16.0 : 8.0);
      Widget content = cells[i];
      if (first && (outline || icon != null)) {
        content = Row(
          children: [
            if (outline)
              SizedBox(
                width: MacTableMetrics.chevronSlot,
                height: MacTableMetrics.rowHeight,
                child: expanded == null ? null : MacDisclosureChevron(expanded: expanded!, color: look.primary, onPressed: onDisclosure),
              ),
            if (icon != null) ...[
              SizedBox.square(
                dimension: MacTableMetrics.iconSlot,
                child: IconTheme(
                  data: IconThemeData(color: look.primary, size: 16),
                  child: Center(child: icon),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(child: content),
          ],
        );
      }
      children.add(
        SizedBox(
          width: spec.width,
          height: MacTableMetrics.rowHeight,
          child: Padding(
            padding: EdgeInsets.only(left: left, right: right),
            child: DefaultTextStyle(
              style: macRowTextStyle(context, color, numeric: spec.numeric),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: spec.numeric ? TextAlign.right : TextAlign.left,
              child: Align(alignment: spec.numeric ? Alignment.centerRight : Alignment.centerLeft, child: content),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: MacTableMetrics.rowHeight,
      child: Stack(
        children: [
          Positioned.fill(left: MacTableMetrics.inset, right: MacTableMetrics.inset, child: fill),
          Row(children: children),
        ],
      ),
    );
  }
}

/// An empty filler row under the last row: keeps the stripes going (kit "Table Rows - Blank").
class MacBlankRowView extends StatelessWidget {
  const MacBlankRowView({super.key, required this.alternate});
  final bool alternate;

  @override
  Widget build(BuildContext context) {
    final look = MacRowLook.of(context, selected: false, alternate: alternate);
    return SizedBox(
      height: MacTableMetrics.rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MacTableMetrics.inset),
        child: DecoratedBox(
          decoration: BoxDecoration(color: look.fill, borderRadius: BorderRadius.circular(MacTableMetrics.radius)),
        ),
      ),
    );
  }
}

/// The disclosure chevron of an outline row (kit "_Disclosure": › Bold 9, turns to ⌄ when open).
class MacDisclosureChevron extends StatelessWidget {
  const MacDisclosureChevron({super.key, required this.expanded, required this.color, this.onPressed});
  final bool expanded;
  final Color color;
  final void Function(bool altPressed)? onPressed;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // A 16 px glyph box centred on x = 6.5, 2 px from the top of the 20 px row.
    final glyph = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -1.5,
          top: 2,
          width: 16,
          height: 16,
          child: AnimatedRotation(
            turns: expanded ? 0.25 : 0,
            duration: reduce ? Duration.zero : const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: MacGlyph(MacGlyphKind.chevronRightBold, size: 16, color: color),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      expanded: expanded,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed == null ? null : () => onPressed!(HardwareKeyboard.instance.isAltPressed),
        child: glyph,
      ),
    );
  }
}

/// One column header title.
class MacHeaderCellSpec {
  const MacHeaderCellSpec({required this.title, required this.width, this.sorted, this.sortable = true});
  final String title;
  final double width;

  /// Null = not the sorted column; true = ascending (⌃); false = descending (⌄).
  final bool? sorted;
  final bool sortable;
}

/// The column header row (kit "Column Header": 28 tall = 4 + 19 + 5, then 3 px to the first row): 11 px Medium
/// titles in label secondary, 1 px separators, the sorted column bold and primary with ⌄ / ⌃.
class MacTableHeaderView extends StatelessWidget {
  const MacTableHeaderView({super.key, required this.cells, required this.lead, this.onTap, this.showLine = false});
  final List<MacHeaderCellSpec> cells;

  /// Text start of the first title after the 10 px inset (6 · 28 · 40).
  final double lead;
  final ValueChanged<int>? onTap;

  /// The hairline 6 px above the first row, while rows scroll under the header.
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final out = <Widget>[];
    for (var i = 0; i < cells.length; i++) {
      out.add(
        MacHeaderCell(spec: cells[i], first: i == 0, lead: lead, onTap: onTap == null || !cells[i].sortable ? null : () => onTap!(i)),
      );
    }
    return SizedBox(
      height: MacTableMetrics.headerHeight,
      child: Stack(
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: out),
          if (showLine)
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              height: 1,
              child: ColoredBox(color: theme.isDark ? const Color(0x1AFFFFFF) : const Color(0x0D000000)),
            ),
        ],
      ),
    );
  }
}

/// One header cell (kit "_Column Headers"): 19 px tall title area 4 px from the top.
class MacHeaderCell extends StatefulWidget {
  const MacHeaderCell({super.key, required this.spec, required this.first, required this.lead, this.onTap});
  final MacHeaderCellSpec spec;
  final bool first;
  final double lead;
  final VoidCallback? onTap;

  @override
  State<MacHeaderCell> createState() => _MacHeaderCellState();
}

class _MacHeaderCellState extends State<MacHeaderCell> {
  bool _focusVisible = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final c = theme.mac;
    final spec = widget.spec;
    final sorted = spec.sorted != null;
    final style = macFieldTextStyle(
      context,
      fontSize: 11,
      color: sorted ? c.labelPrimary : c.labelSecondary,
      weight: sorted ? FontWeight.w700 : FontWeight.w500,
    ).copyWith(height: 19 / 11);
    final left = widget.first ? MacTableMetrics.inset + widget.lead : 8.0;
    final right = sorted ? 19.0 : 6.0;
    Widget cell = SizedBox(
      width: spec.width,
      height: MacTableMetrics.headerHeight,
      child: Stack(
        children: [
          Positioned(
            left: left,
            right: right,
            top: 4,
            height: 19,
            child: Text(spec.title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style),
          ),
          if (!widget.first) Positioned(left: 0, top: 4, width: 1, height: 19, child: ColoredBox(color: c.separator)),
          if (sorted)
            Positioned(
              right: 6,
              top: 4,
              width: 13,
              height: 19,
              child: Center(
                child: MacGlyph(spec.sorted! ? MacGlyphKind.chevronUp : MacGlyphKind.chevronDown, size: 14, color: c.labelSecondary),
              ),
            ),
          if (_focusVisible)
            Positioned(
              left: 2,
              right: 2,
              top: 4,
              height: 19,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: theme.accentColor.withValues(alpha: 0.55), width: 2),
                ),
              ),
            ),
        ],
      ),
    );
    if (widget.onTap == null) {
      return Semantics(header: true, label: spec.title, child: ExcludeSemantics(child: cell));
    }
    return Semantics(
      header: true,
      button: true,
      label: spec.title,
      value: sorted ? (spec.sorted! ? 'ascending' : 'descending') : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focusVisible = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap!())},
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: cell),
      ),
    );
  }
}

/// A group title row (kit "Group Title": 45 tall = 24 + 14 + 7; 11 px Semibold, label secondary).
class MacGroupTitleView extends StatelessWidget {
  const MacGroupTitleView({super.key, required this.title, required this.left, this.top = 24});
  final String title;

  /// Text start from the view edge: 10 inset + the table's lead (lines up with the first column's text).
  final double left;
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = AppleTheme.of(context).mac;
    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(left, top, 8, 7),
        child: Text(
          title,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: macFieldTextStyle(context, fontSize: 11, color: c.labelSecondary, weight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// The kit's blue folder icon ("_Icon / Folder"), drawn in an 18 × 18 box.
class MacFolderGlyph extends StatelessWidget {
  const MacFolderGlyph({super.key});
  @override
  Widget build(BuildContext context) => const CustomPaint(size: Size.square(18), painter: _FolderPainter());
}

class _FolderPainter extends CustomPainter {
  const _FolderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Back panel with the tab (#52B6EA).
    final back = Path()
      ..moveTo(2.5, 3.5)
      ..lineTo(2.5 + 4.6, 3.5)
      ..lineTo(2.5 + 5.8, 3.5 + 1.2)
      ..lineTo(15.5, 3.5 + 1.2)
      ..lineTo(15.5, 14)
      ..lineTo(2.5, 14)
      ..close();
    canvas.save();
    canvas.clipRRect(RRect.fromLTRBR(2.5, 3.5, 15.5, 14, const Radius.circular(1.5)));
    canvas.drawPath(back, Paint()..color = const Color(0xFF52B6EA));
    canvas.restore();
    // Front panel: #6CCAF4 → #47B0E3 with a white top highlight.
    final front = RRect.fromLTRBAndCorners(
      2.5,
      5.5,
      15.5,
      14,
      topLeft: const Radius.circular(1),
      topRight: const Radius.circular(1),
      bottomLeft: const Radius.circular(1.5),
      bottomRight: const Radius.circular(1.5),
    );
    canvas.drawRRect(
      front,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6CCAF4), Color(0xFF47B0E3)],
        ).createShader(front.outerRect),
    );
    canvas.save();
    canvas.clipRRect(front);
    canvas.drawRect(const Rect.fromLTWH(2.5, 5.5, 13, 0.75), Paint()..color = const Color(0x8CFFFFFF));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FolderPainter old) => false;
}

/// A 14 × 14 image thumbnail, radius 2, with a 1 px shadow below and a white 25 % inner edge (kit "_Icon / Thumbnail").
class MacThumbnailGlyph extends StatelessWidget {
  const MacThumbnailGlyph({super.key, this.image, this.color});
  final ImageProvider? image;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 18,
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: color,
            image: image == null ? null : DecorationImage(image: image!, fit: BoxFit.cover),
            boxShadow: const [BoxShadow(color: Color(0x40000000), offset: Offset(0, 1))],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: const Color(0x40FFFFFF), width: 1),
          ),
        ),
      ),
    );
  }
}
