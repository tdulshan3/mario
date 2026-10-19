import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, setEquals;
import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/theme.dart';
import '_table_parts.dart';
import '_text_input.dart' show macFieldTextStyle;

/// How rows can be selected (like the Finder).
enum MacSelectionMode {
  /// Rows can't be selected.
  none,

  /// One row: click, ↑ ↓, Home, End.
  single,

  /// Also ⌘-click (Ctrl-click on Windows/Linux) to add or remove, ⇧-click and ⇧↑ ⇧↓ for a range, ⌘A for all.
  multiple,
}

/// The sorted column of a [MacTable] and its direction.
@immutable
class MacTableSort {
  const MacTableSort(this.column, {this.ascending = true});

  /// The [MacTableColumn.id] (its title unless set).
  final String column;
  final bool ascending;

  MacTableSort get reversed => MacTableSort(column, ascending: !ascending);

  @override
  bool operator ==(Object other) => other is MacTableSort && other.column == column && other.ascending == ascending;

  @override
  int get hashCode => Object.hash(column, ascending);
}

/// One column of a [MacTable].
///
///     MacTableColumn<FileItem>(title: 'Name', value: (f) => f.name)
///     MacTableColumn<FileItem>(title: 'Date Modified', value: (f) => f.modified, text: (f) => formatDate(f.modified), width: 160)
///     MacTableColumn<FileItem>(title: 'Size', value: (f) => f.bytes, text: (f) => f.sizeLabel, numeric: true, width: 90)
///     MacTableColumn<FileItem>(title: 'Kind', value: (f) => f.kind, width: 120)
class MacTableColumn<T> {
  const MacTableColumn({
    required this.title,
    required this.value,
    this.id,
    this.text,
    this.cellBuilder,
    this.width,
    this.flex = 1,
    this.numeric = false,
    this.sortable = true,
  });

  /// Short noun in Title Case: "Name", "Date Modified", "Size".
  final String title;

  /// The value of this column for a row: sorted by, and shown as text unless [text] or [cellBuilder] is set.
  /// Numbers and DateTimes sort by value; text sorts naturally ("File 2" before "File 10"), ignoring case.
  final Object? Function(T row) value;

  /// Id for [MacTableSort]. Default: [title].
  final String? id;

  /// The text shown (default: `value` as text, "--" when null).
  final String Function(T row)? text;

  /// A custom cell (a progress circle, a coloured label…). Keep it 20 px tall.
  final Widget Function(BuildContext context, T row)? cellBuilder;

  /// Fixed width in px. The first and last columns include the 10 px row inset (so kit widths work as they are).
  /// Null = share the rest with the other columns without a width ([flex]).
  final double? width;
  final int flex;

  /// Right-aligned tabular numbers (sizes, amounts). The header title stays left-aligned, like the kit.
  final bool numeric;

  /// Click the header to sort (default true).
  final bool sortable;

  String get key => id ?? title;
}

/// A titled group of rows in a [MacTable] (kit "Group Title": 11 px semibold grey title above the rows).
class MacTableGroup<T> {
  const MacTableGroup({this.title, required this.rows});

  /// Null = no title row (for example the first group).
  final String? title;
  final List<T> rows;
}

/// The 18 × 18 icon at the start of a table row's first cell.
///
///     MacTableIcon(AppleIcons.docText)              // a 16 px glyph in the row's text colour (white when selected)
///     MacTableIcon.folder()                         // the kit's blue folder
///     MacTableIcon.thumbnail(FileImage(file))       // a 14 × 14 image thumbnail
///     MacTableIcon.image(AssetImage('icons/app.png'))   // any 18 × 18 image
class MacTableIcon extends StatelessWidget {
  const MacTableIcon(IconData this.icon, {super.key}) : image = null, _kind = 0;
  const MacTableIcon.folder({super.key}) : icon = null, image = null, _kind = 1;
  const MacTableIcon.thumbnail(ImageProvider this.image, {super.key}) : icon = null, _kind = 2;
  const MacTableIcon.image(ImageProvider this.image, {super.key}) : icon = null, _kind = 3;

  final IconData? icon;
  final ImageProvider? image;
  final int _kind;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: switch (_kind) {
      0 => Icon(icon, size: 16),
      1 => const MacFolderGlyph(),
      2 => MacThumbnailGlyph(image: image),
      _ => Image(image: image!, width: 18, height: 18, fit: BoxFit.contain),
    },
  );
}

/// Shared Finder-style selection: click, ⌘-click, ⇧-click, ↑ ↓ Home End (⇧ extends), ⌘A.
mixin _Selection<W extends StatefulWidget> on State<W> {
  Set<Object> selected = <Object>{};
  Object? _anchor;
  Object? _lead;

  MacSelectionMode get selectionMode;
  List<Object> get selectableIds;
  void selectionChanged(Set<Object> ids);

  bool get _apple => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
  bool get _toggleKey => _apple ? HardwareKeyboard.instance.isMetaPressed : HardwareKeyboard.instance.isControlPressed;

  void _commit(Set<Object> ids) {
    if (setEquals(ids, selected)) return;
    setState(() => selected = ids);
    selectionChanged(Set.unmodifiable(ids));
  }

  List<Object> _range(Object a, Object b) {
    final ids = selectableIds;
    final i = ids.indexOf(a), j = ids.indexOf(b);
    if (i < 0 || j < 0) return [b];
    return ids.sublist(math.min(i, j), math.max(i, j) + 1);
  }

  void clickItem(Object id, {bool secondary = false}) {
    final mode = selectionMode;
    if (mode == MacSelectionMode.none) return;
    if (secondary) {
      // Right-click: act on the clicked row (keep a selection that contains it).
      if (!selected.contains(id)) {
        _anchor = _lead = id;
        _commit({id});
      }
      return;
    }
    if (mode == MacSelectionMode.multiple && _toggleKey) {
      final next = {...selected};
      if (!next.remove(id)) next.add(id);
      _anchor = id;
      _commit(next);
    } else if (mode == MacSelectionMode.multiple && HardwareKeyboard.instance.isShiftPressed && _anchor != null) {
      _commit(_range(_anchor!, id).toSet());
    } else {
      _anchor = id;
      _commit({id});
    }
    _lead = id;
  }

  void clearSelection() {
    if (selectionMode == MacSelectionMode.none) return;
    _commit(<Object>{});
  }

  /// Handles ↑ ↓ Home End ⌘A. Returns the row to scroll into view, or null; [handled] tells whether the key was used.
  ({bool handled, Object? reveal}) selectionKey(KeyEvent e) {
    final ids = selectableIds;
    if (selectionMode == MacSelectionMode.none || ids.isEmpty) return (handled: false, reveal: null);
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.keyA && _toggleKey && selectionMode == MacSelectionMode.multiple) {
      _commit(ids.toSet());
      return (handled: true, reveal: null);
    }
    final cur = _lead != null && ids.contains(_lead) ? ids.indexOf(_lead!) : ids.indexWhere(selected.contains);
    int next;
    if (key == LogicalKeyboardKey.arrowDown) {
      next = cur < 0 ? 0 : math.min(cur + 1, ids.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = cur < 0 ? ids.length - 1 : math.max(cur - 1, 0);
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = ids.length - 1;
    } else {
      return (handled: false, reveal: null);
    }
    final id = ids[next];
    if (selectionMode == MacSelectionMode.multiple && HardwareKeyboard.instance.isShiftPressed && _anchor != null) {
      _commit(_range(_anchor!, id).toSet());
    } else {
      _anchor = id;
      _commit({id});
    }
    _lead = id;
    return (handled: true, reveal: id);
  }

  /// The row Return / double-click acts on: the last clicked or moved-to row, else the first selected.
  Object? get leadId => _lead != null && selected.contains(_lead)
      ? _lead
      : (selected.isEmpty ? null : selectableIds.firstWhere(selected.contains, orElse: () => selected.first));
  set leadId(Object? id) => _lead = id;
}

// Display items of a table: group titles, rows, blank filler rows.
sealed class _Item {
  double get height;
}

class _GroupItem extends _Item {
  _GroupItem(this.title);
  final String title;
  @override
  double get height => MacTableMetrics.groupHeight;
}

class _RowItem<T> extends _Item {
  _RowItem(this.row, this.id, this.level, this.children, this.expanded, this.stripe, this.parent);
  final T row;
  final Object id;
  final int level;
  final List<T>? children;
  final bool expanded;
  final int stripe;
  final Object? parent;
  @override
  double get height => MacTableMetrics.rowHeight;
}

class _BlankItem extends _Item {
  _BlankItem(this.stripe);
  final int stripe;
  @override
  double get height => MacTableMetrics.rowHeight;
}

/// A macOS table (kit page "Lists and Tables"): column headers you click to sort, 20 px rows with the rounded inset
/// selection, alternating row colours, an icon in the first cell, outline (tree) rows with disclosure chevrons,
/// group titles. Sorting, selection and keyboard navigation are done for you.
///
///     MacTable<FileItem>(
///       semanticLabel: 'Documents',
///       columns: [
///         MacTableColumn(title: 'Name', value: (f) => f.name),
///         MacTableColumn(title: 'Date Modified', value: (f) => f.modified, text: (f) => f.modifiedLabel, width: 150),
///         MacTableColumn(title: 'Size', value: (f) => f.bytes, text: (f) => f.sizeLabel, numeric: true, width: 90),
///         MacTableColumn(title: 'Kind', value: (f) => f.kind, width: 120),
///       ],
///       rows: files,
///       rowId: (f) => f.id,
///       selectionMode: MacSelectionMode.multiple,
///       selection: selected,                                  // Set of row ids
///       onSelectionChanged: (ids) => setState(() => selected = ids),
///       sort: const MacTableSort('Name'),                    // initial sort; clicking a header re-sorts
///       icon: (f) => f.isFolder ? const MacTableIcon.folder() : const MacTableIcon(AppleIcons.docText),
///       onRowAction: open,                                    // double-click or Return
///     )
///     // Outline (tree): children: (f) => f.isFolder ? f.items : null   (null = a leaf, no chevron)
///     // Groups: MacTable(groups: [MacTableGroup(title: 'Today', rows: today), MacTableGroup(title: 'Earlier', rows: older)], …)
///
/// In a box with a bounded height (a pane, an Expanded) the rows scroll under a fixed header and the stripes go on to
/// the bottom; with an unbounded height (inside your own scroll view) the table is as tall as its rows.
/// Keyboard: ↑ ↓ Home End move, ⇧ extends, ⌘A all, → opens and ← closes an outline row (⌥ for all levels),
/// Return = [onRowAction]. Click on empty space clears the selection. No hover effect.
class MacTable<T> extends StatefulWidget {
  const MacTable({
    super.key,
    required this.columns,
    this.rows = const [],
    this.groups,
    this.rowId,
    this.selectionMode = MacSelectionMode.single,
    this.selection,
    this.onSelectionChanged,
    this.sort,
    this.onSortChanged,
    this.alternating = true,
    this.showHeader = true,
    this.icon,
    this.children,
    this.expanded,
    this.onExpandedChanged,
    this.onRowAction,
    this.emptyText,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  }) : assert(groups == null || rows.length == 0, 'Give rows OR groups');

  final List<MacTableColumn<T>> columns;
  final List<T> rows;

  /// Rows in titled groups (instead of [rows]). Sorting happens inside each group.
  final List<MacTableGroup<T>>? groups;

  /// A unique, stable id per row (default: the row object itself).
  final Object Function(T row)? rowId;
  final MacSelectionMode selectionMode;

  /// The selected row ids. Null = the table keeps its own selection.
  final Set<Object>? selection;
  final ValueChanged<Set<Object>>? onSelectionChanged;

  /// The sorted column (bold title + ⌄ / ⌃). Null = unsorted until a header is clicked.
  final MacTableSort? sort;
  final ValueChanged<MacTableSort>? onSortChanged;

  /// Stripes on every other row (default true). Use them in wide tables, not in single-column lists.
  final bool alternating;
  final bool showHeader;

  /// An 18 × 18 icon at the start of the first cell ([MacTableIcon]); null for a row = no icon.
  final Widget? Function(T row)? icon;

  /// Outline: the child rows of a row. Null for a row = a leaf (no chevron).
  final List<T>? Function(T row)? children;

  /// Ids of the open outline rows. Null = the table keeps its own (all closed at first).
  final Set<Object>? expanded;
  final ValueChanged<Set<Object>>? onExpandedChanged;

  /// Double-click or Return on a row: open it.
  final ValueChanged<T>? onRowAction;

  /// Shown in one grey row when there are no rows ("No Documents").
  final String? emptyText;

  /// Accessible name ("Documents").
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<MacTable<T>> createState() => _MacTableState<T>();
}

class _MacTableState<T> extends State<MacTable<T>> with _Selection<MacTable<T>> {
  MacTableSort? _sort;
  Set<Object> _expanded = <Object>{};
  final _scroll = ScrollController();
  List<_Item> _items = const [];
  bool _hitRow = false;
  bool _pointerFocus = false;
  bool _ring = false;
  bool _scrolled = false;
  DateTime? _lastClick;
  Object? _lastClickId;
  final Map<Object, GlobalKey> _keys = {};
  bool _bounded = false;

  Object _id(T row) => widget.rowId?.call(row) ?? row as Object;

  @override
  MacSelectionMode get selectionMode => widget.selectionMode;
  @override
  List<Object> get selectableIds => [
    for (final i in _items)
      if (i is _RowItem<T>) i.id,
  ];
  @override
  void selectionChanged(Set<Object> ids) => widget.onSelectionChanged?.call(ids);

  @override
  void initState() {
    super.initState();
    _sort = widget.sort;
    selected = {...?widget.selection};
    _expanded = {...?widget.expanded};
    _scroll.addListener(() {
      final s = _scroll.hasClients && _scroll.offset > 0;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
  }

  @override
  void didUpdateWidget(MacTable<T> old) {
    super.didUpdateWidget(old);
    if (widget.sort != old.sort) _sort = widget.sort;
    if (widget.selection != null && !setEquals(widget.selection, old.selection)) selected = {...widget.selection!};
    if (widget.expanded != null && !setEquals(widget.expanded, old.expanded)) _expanded = {...widget.expanded!};
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // --- data -------------------------------------------------------------------------------------------------

  List<T> _sorted(List<T> rows) {
    final s = _sort;
    if (s == null) return rows;
    final col = widget.columns.where((c) => c.key == s.column).firstOrNull;
    if (col == null) return rows;
    final dir = s.ascending ? 1 : -1;
    final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
    indexed.sort((a, b) {
      final r = _compare(col.value(a.$2), col.value(b.$2)) * dir;
      return r != 0 ? r : a.$1 - b.$1; // stable
    });
    return [for (final e in indexed) e.$2];
  }

  List<_Item> _flatten() {
    final out = <_Item>[];
    var stripe = 0;
    void addRows(List<T> rows, int level, Object? parent) {
      for (final row in _sorted(rows)) {
        final id = _id(row);
        final kids = widget.children?.call(row);
        final open = kids != null && _expanded.contains(id);
        out.add(_RowItem<T>(row, id, level, kids, open, stripe++, parent));
        if (open) addRows(kids, level + 1, id);
      }
    }

    final groups = widget.groups;
    if (groups == null) {
      addRows(widget.rows, 0, null);
    } else {
      for (final g in groups) {
        if (g.title != null) out.add(_GroupItem(g.title!));
        addRows(g.rows, 0, null);
      }
    }
    return out;
  }

  int get _rowCount => _items.whereType<_RowItem<T>>().length;

  // --- actions ----------------------------------------------------------------------------------------------

  void _clickHeader(int i) {
    final col = widget.columns[i];
    if (!col.sortable) return;
    final next = _sort?.column == col.key && _sort!.ascending ? MacTableSort(col.key, ascending: false) : MacTableSort(col.key);
    setState(() => _sort = next);
    widget.onSortChanged?.call(next);
  }

  void _setExpanded(_RowItem<T> item, bool open, {bool all = false}) {
    final next = {..._expanded};
    void walk(T row) {
      final id = _id(row);
      final kids = widget.children?.call(row);
      if (kids == null) return;
      open ? next.add(id) : next.remove(id);
      if (all) kids.forEach(walk);
    }

    walk(item.row);
    if (!open) {
      // A closed row can't keep hidden selected children: select the row instead (Finder).
      final hidden = selected.where((s) => !_visibleAfter(next).contains(s)).toSet();
      if (hidden.isNotEmpty) {
        selected = {...selected.difference(hidden), item.id};
        selectionChanged(Set.unmodifiable(selected));
      }
    }
    setState(() => _expanded = next);
    widget.onExpandedChanged?.call(Set.unmodifiable(next));
  }

  Set<Object> _visibleAfter(Set<Object> expanded) {
    final saved = _expanded;
    _expanded = expanded;
    final ids = {
      for (final i in _flatten())
        if (i is _RowItem<T>) i.id,
    };
    _expanded = saved;
    return ids;
  }

  void _onRowPointer(_RowItem<T> item, PointerDownEvent e) {
    _hitRow = true;
    _pointerFocus = true;
    _focus.requestFocus();
    // A click on the disclosure chevron only opens or closes the row (Finder): no selection change.
    final chevronLeft = MacTableMetrics.inset + 6 + item.level * MacTableMetrics.indent;
    if (item.children != null && e.localPosition.dx >= chevronLeft && e.localPosition.dx < chevronLeft + MacTableMetrics.chevronSlot) {
      return;
    }
    if (e.buttons == kSecondaryButton) {
      clickItem(item.id, secondary: true);
      return;
    }
    if (e.buttons != kPrimaryButton) return;
    final now = DateTime.now();
    final double = _lastClickId == item.id && _lastClick != null && now.difference(_lastClick!) < const Duration(milliseconds: 400);
    _lastClick = now;
    _lastClickId = item.id;
    if (double) {
      _lastClick = null;
      widget.onRowAction?.call(item.row);
      return;
    }
    clickItem(item.id);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;
    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) && widget.onRowAction != null) {
      final id = leadId;
      final item = _items.whereType<_RowItem<T>>().where((i) => i.id == id).firstOrNull;
      if (item != null) widget.onRowAction!(item.row);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowLeft) && widget.children != null) {
      final id = leadId;
      final item = _items.whereType<_RowItem<T>>().where((i) => i.id == id).firstOrNull;
      if (item == null) return KeyEventResult.ignored;
      final all = HardwareKeyboard.instance.isAltPressed;
      if (key == LogicalKeyboardKey.arrowRight) {
        if (item.children != null && (!item.expanded || all)) _setExpanded(item, true, all: all);
      } else if (item.expanded) {
        _setExpanded(item, false, all: all);
      } else if (item.parent != null) {
        leadId = item.parent;
        _commit({item.parent!});
        _reveal(item.parent!);
      }
      return KeyEventResult.handled;
    }
    final r = selectionKey(e);
    if (r.reveal != null) _reveal(r.reveal!);
    return r.handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _reveal(Object id) {
    if (_bounded && _scroll.hasClients) {
      var top = 0.0;
      for (final i in _items) {
        if (i is _RowItem<T> && i.id == id) break;
        top += i.height;
      }
      final view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + MacTableMetrics.rowHeight > _scroll.offset + view) {
        _scroll.jumpTo(top + MacTableMetrics.rowHeight - view);
      }
    } else {
      final ctx = _keys[id]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    }
  }

  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'MacTable'));

  // --- layout -----------------------------------------------------------------------------------------------

  List<double> _widths(double total) {
    final cols = widget.columns;
    final fixed = cols.fold<double>(0, (s, c) => s + (c.width ?? 0));
    final flexSum = cols.fold<int>(0, (s, c) => s + (c.width == null ? c.flex : 0));
    if (!total.isFinite) return [for (final c in cols) c.width ?? 120.0 * c.flex];
    if (flexSum == 0) {
      // All fixed: scale to the width, like an HTML table with table-layout: fixed.
      final k = fixed > 0 ? total / fixed : 1.0;
      return [for (final c in cols) c.width! * k];
    }
    final rest = math.max(0.0, total - fixed);
    return [for (final c in cols) c.width ?? rest * c.flex / flexSum];
  }

  Widget _cell(MacTableColumn<T> col, T row) {
    if (col.cellBuilder != null) return Builder(builder: (context) => col.cellBuilder!(context, row));
    final v = col.value(row);
    return Text(col.text?.call(row) ?? (v == null ? '--' : '$v'));
  }

  Widget _buildItem(BuildContext context, _Item item, List<MacCellSpec> specs, double lead, int index) {
    if (item is _GroupItem) return MacGroupTitleView(title: item.title, left: MacTableMetrics.inset + lead);
    if (item is _BlankItem) {
      return Semantics(excludeSemantics: true, child: MacBlankRowView(alternate: widget.alternating && item.stripe.isEven));
    }
    final row = item as _RowItem<T>;
    final sel = selected.contains(row.id);
    bool selAt(int i) => i >= 0 && i < _items.length && _items[i] is _RowItem<T> && selected.contains((_items[i] as _RowItem<T>).id);
    final rowView = MacTableRowView(
      specs: specs,
      cells: [for (final c in widget.columns) _cell(c, row.row)],
      selected: sel,
      alternate: widget.alternating && row.stripe.isEven,
      joinTop: sel && selAt(index - 1),
      joinBottom: sel && selAt(index + 1),
      outline: widget.children != null,
      level: row.level,
      expanded: row.children == null ? null : row.expanded,
      onDisclosure: (alt) => _setExpanded(row, !row.expanded, all: alt),
      icon: widget.icon?.call(row.row),
    );
    final firstCol = widget.columns.isEmpty ? null : widget.columns.first;
    final label = firstCol == null ? '' : (firstCol.text?.call(row.row) ?? '${firstCol.value(row.row) ?? ''}');
    return Semantics(
      key: _bounded ? null : (_keys[row.id] ??= GlobalKey()),
      selected: sel,
      expanded: row.children == null ? null : row.expanded,
      label: label,
      child: Listener(onPointerDown: (e) => _onRowPointer(row, e), child: rowView),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    final outline = widget.children != null;
    final lead = MacTableMetrics.lead(outline: outline, icons: widget.icon != null);
    _items = _flatten();
    final ids = {
      for (final i in _items)
        if (i is _RowItem<T>) i.id,
    };
    _keys.removeWhere((id, _) => !ids.contains(id));

    return LayoutBuilder(
      builder: (context, constraints) {
        _bounded = constraints.hasBoundedHeight;
        final widths = _widths(constraints.maxWidth);
        final specs = [for (var i = 0; i < widget.columns.length; i++) MacCellSpec(width: widths[i], numeric: widget.columns[i].numeric)];
        final header = widget.showHeader
            ? Listener(
                onPointerDown: (_) => _hitRow = true, // header clicks sort; they don't clear the selection
                child: MacTableHeaderView(
                  lead: lead,
                  showLine: _bounded && _scrolled,
                  onTap: _clickHeader,
                  cells: [
                    for (var i = 0; i < widget.columns.length; i++)
                      MacHeaderCellSpec(
                        title: widget.columns[i].title,
                        width: widths[i],
                        sortable: widget.columns[i].sortable,
                        sorted: _sort?.column == widget.columns[i].key ? _sort!.ascending : null,
                      ),
                  ],
                ),
              )
            : null;

        final empty = _rowCount == 0 && widget.emptyText != null
            ? SizedBox(
                height: MacTableMetrics.rowHeight,
                child: Center(
                  child: Text(widget.emptyText!, style: macFieldTextStyle(context, fontSize: 13, color: theme.mac.labelSecondary)),
                ),
              )
            : null;

        Widget body;
        if (_bounded) {
          body = LayoutBuilder(
            builder: (context, box) {
              var items = _items;
              if (widget.alternating) {
                // Blank rows keep the stripes going to the bottom of the view (kit "Table Rows - Blank").
                final used = items.fold<double>(0, (s, i) => s + i.height) + (empty != null ? MacTableMetrics.rowHeight : 0);
                final n = ((box.maxHeight - used) / MacTableMetrics.rowHeight).ceil();
                if (n > 0) items = [...items, for (var k = 0; k < n; k++) _BlankItem(_rowCount + k)];
              }
              return ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.zero,
                itemCount: items.length + (empty != null ? 1 : 0),
                itemExtentBuilder: (i, _) => i < items.length ? items[i].height : MacTableMetrics.rowHeight,
                itemBuilder: (context, i) => i < items.length ? _buildItem(context, items[i], specs, lead, i) : empty!,
              );
            },
          );
          body = Expanded(child: body);
        } else {
          body = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (var i = 0; i < _items.length; i++) _buildItem(context, _items[i], specs, lead, i), ?empty],
          );
        }

        Widget table = Column(
          mainAxisSize: _bounded ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [?header, body],
        );
        // Pointer down outside every row (blank rows, empty space): clear the selection.
        table = Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (!_hitRow) {
              _pointerFocus = true;
              _focus.requestFocus();
              clearSelection();
            }
            _hitRow = false;
          },
          child: table,
        );
        final accent = theme.accentColor;
        return Semantics(
          container: true,
          label: widget.semanticLabel,
          child: Focus(
            focusNode: _focus,
            autofocus: widget.autofocus,
            canRequestFocus: widget.selectionMode != MacSelectionMode.none,
            onKeyEvent: _onKey,
            onFocusChange: (f) {
              setState(() => _ring = f && !_pointerFocus);
              _pointerFocus = false;
            },
            child: CustomPaint(
              foregroundPainter: _ring ? _ViewRingPainter(accent.withValues(alpha: accent.a * 0.55)) : null,
              child: table,
            ),
          ),
        );
      },
    );
  }
}

/// 3.5 px keyboard focus ring around a table or list (CSS outline, offset 0).
class _ViewRingPainter extends CustomPainter {
  _ViewRingPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas.drawDRRect(r.inflate(3.5), r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ViewRingPainter old) => old.color != color;
}

int _compare(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is DateTime && b is DateTime) return a.compareTo(b);
  if (a is bool && b is bool) return a == b ? 0 : (a ? 1 : -1);
  if (a is String && b is String) return _natural(a, b);
  if (a is Comparable && a.runtimeType == b.runtimeType) return a.compareTo(b);
  return _natural('$a', '$b');
}

/// Natural, case-insensitive order: "File 2" before "File 10" (like the Finder and Intl.Collator numeric).
int _natural(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a.toLowerCase()).toList();
  final y = re.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < math.min(x.length, y.length); i++) {
    final p = x[i].group(0)!, q = y[i].group(0)!;
    final pn = int.tryParse(p), qn = int.tryParse(q);
    final c = pn != null && qn != null ? pn.compareTo(qn) : p.compareTo(q);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

/// One item of a [MacList].
class MacListItem {
  const MacListItem({required this.id, required this.title, this.subtitle, this.detail, this.icon});

  /// Unique, stable id (reported in the selection).
  final Object id;
  final String title;

  /// Small grey second line (11 px).
  final String? subtitle;

  /// Trailing count or value, grey ("12").
  final String? detail;

  /// A 16 px glyph before the title (`AppleIcons.tray`).
  final IconData? icon;
}

/// A one-column macOS list (mailboxes, people, recent documents): 20 px rows, rounded inset selection, optional
/// group title. For several attributes per item use [MacTable]; for app navigation use the sidebar.
///
///     MacList(
///       semanticLabel: 'Mailboxes',
///       header: 'Mailboxes',                                  // optional small grey title
///       items: const [
///         MacListItem(id: 'inbox', title: 'Inbox', icon: AppleIcons.tray, detail: '12'),
///         MacListItem(id: 'flagged', title: 'Flagged', icon: AppleIcons.flag, subtitle: '3 unread messages'),
///       ],
///       selection: {mailbox},
///       onSelectionChanged: (ids) => setState(() => mailbox = ids.first as String),
///       onItemAction: (id) => open(id),                       // double-click or Return
///     )
///
/// Selection and keyboard like [MacTable] ([selectionMode] multiple: ⌘-click, ⇧-click, ⌘A). No stripes by default
/// (don't stripe single-column lists). Bounded height = scrolls; unbounded = as tall as its items.
class MacList extends StatefulWidget {
  const MacList({
    super.key,
    required this.items,
    this.header,
    this.selectionMode = MacSelectionMode.single,
    this.selection,
    this.onSelectionChanged,
    this.alternating = false,
    this.onItemAction,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  });

  final List<MacListItem> items;

  /// Small grey title above the items (kit "Group Title").
  final String? header;
  final MacSelectionMode selectionMode;

  /// The selected item ids. Null = the list keeps its own selection.
  final Set<Object>? selection;
  final ValueChanged<Set<Object>>? onSelectionChanged;
  final bool alternating;

  /// Double-click or Return on an item.
  final ValueChanged<Object>? onItemAction;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<MacList> createState() => _MacListState();
}

class _MacListState extends State<MacList> with _Selection<MacList> {
  final _scroll = ScrollController();
  bool _hitItem = false;
  bool _pointerFocus = false;
  bool _ring = false;
  DateTime? _lastClick;
  Object? _lastClickId;
  FocusNode? _ownFocus;
  bool _bounded = false;
  final Map<Object, GlobalKey> _keys = {};

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'MacList'));

  @override
  MacSelectionMode get selectionMode => widget.selectionMode;
  @override
  List<Object> get selectableIds => [for (final i in widget.items) i.id];
  @override
  void selectionChanged(Set<Object> ids) => widget.onSelectionChanged?.call(ids);

  @override
  void initState() {
    super.initState();
    selected = {...?widget.selection};
  }

  @override
  void didUpdateWidget(MacList old) {
    super.didUpdateWidget(old);
    if (widget.selection != null && !setEquals(widget.selection, old.selection)) selected = {...widget.selection!};
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  double get _headerHeight => widget.header == null ? 0 : 8 + 14 + 7; // the first title: 8 px above it, not 24
  double _itemHeight(MacListItem i) => i.subtitle == null ? 20 : 38;

  void _reveal(Object id) {
    if (_bounded && _scroll.hasClients) {
      var top = _headerHeight;
      for (final i in widget.items) {
        if (i.id == id) {
          final h = _itemHeight(i);
          final view = _scroll.position.viewportDimension;
          if (top < _scroll.offset) {
            _scroll.jumpTo(top);
          } else if (top + h > _scroll.offset + view) {
            _scroll.jumpTo(top + h - view);
          }
          return;
        }
        top += _itemHeight(i);
      }
    } else {
      final ctx = _keys[id]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if ((e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) && widget.onItemAction != null) {
      final id = leadId;
      if (id != null) widget.onItemAction!(id);
      return KeyEventResult.handled;
    }
    final r = selectionKey(e);
    if (r.reveal != null) _reveal(r.reveal!);
    return r.handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _onPointer(MacListItem item, PointerDownEvent e) {
    _hitItem = true;
    _pointerFocus = true;
    _focus.requestFocus();
    if (e.buttons == kSecondaryButton) {
      clickItem(item.id, secondary: true);
      return;
    }
    if (e.buttons != kPrimaryButton) return;
    final now = DateTime.now();
    final dbl = _lastClickId == item.id && _lastClick != null && now.difference(_lastClick!) < const Duration(milliseconds: 400);
    _lastClick = now;
    _lastClickId = item.id;
    if (dbl) {
      _lastClick = null;
      widget.onItemAction?.call(item.id);
      return;
    }
    clickItem(item.id);
  }

  Widget _item(BuildContext context, int index) {
    final item = widget.items[index];
    final sel = selected.contains(item.id);
    bool selAt(int i) => i >= 0 && i < widget.items.length && selected.contains(widget.items[i].id);
    final look = MacRowLook.of(context, selected: sel, alternate: widget.alternating && index.isEven);
    const r = Radius.circular(MacTableMetrics.radius);
    final joinTop = sel && selAt(index - 1);
    final joinBottom = sel && selAt(index + 1);
    final title = macRowTextStyle(context, look.primary);
    final row = Container(
      height: _itemHeight(item),
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: item.subtitle == null ? 0 : 4),
      decoration: BoxDecoration(
        color: look.fill,
        borderRadius: BorderRadius.only(
          topLeft: joinTop ? Radius.zero : r,
          topRight: joinTop ? Radius.zero : r,
          bottomLeft: joinBottom ? Radius.zero : r,
          bottomRight: joinBottom ? Radius.zero : r,
        ),
      ),
      child: Row(
        children: [
          if (item.icon != null) ...[Icon(item.icon, size: 16, color: look.primary), const SizedBox(width: 4)],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: title),
                if (item.subtitle != null)
                  Text(
                    item.subtitle!,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: macFieldTextStyle(context, fontSize: 11, color: look.secondary),
                  ),
              ],
            ),
          ),
          if (item.detail != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(item.detail!, style: macRowTextStyle(context, look.secondary, numeric: true)),
            ),
        ],
      ),
    );
    return Semantics(
      key: _bounded ? null : (_keys[item.id] ??= GlobalKey()),
      selected: sel,
      label: item.title,
      child: Listener(onPointerDown: (e) => _onPointer(item, e), child: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppleTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _bounded = constraints.hasBoundedHeight;
        final header = widget.header == null ? null : MacGroupTitleView(title: widget.header!, left: 6, top: 8);
        Widget body;
        if (_bounded) {
          body = ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: MacTableMetrics.inset),
            itemCount: widget.items.length + (header == null ? 0 : 1),
            itemBuilder: (context, i) => header != null ? (i == 0 ? header : _item(context, i - 1)) : _item(context, i),
          );
        } else {
          body = Padding(
            padding: const EdgeInsets.symmetric(horizontal: MacTableMetrics.inset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [?header, for (var i = 0; i < widget.items.length; i++) _item(context, i)],
            ),
          );
        }
        body = Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (!_hitItem) {
              _pointerFocus = true;
              _focus.requestFocus();
              clearSelection();
            }
            _hitItem = false;
          },
          child: body,
        );
        final accent = theme.accentColor;
        return Semantics(
          container: true,
          label: widget.semanticLabel,
          child: Focus(
            focusNode: _focus,
            autofocus: widget.autofocus,
            canRequestFocus: widget.selectionMode != MacSelectionMode.none,
            onKeyEvent: _onKey,
            onFocusChange: (f) {
              setState(() => _ring = f && !_pointerFocus);
              _pointerFocus = false;
            },
            child: CustomPaint(
              foregroundPainter: _ring ? _ViewRingPainter(accent.withValues(alpha: accent.a * 0.55)) : null,
              child: body,
            ),
          ),
        );
      },
    );
  }
}
