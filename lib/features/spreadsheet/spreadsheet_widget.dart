/// SpreadsheetWidget — scrollable grid with editable cells, sheet tabs at the bottom.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../ui/colors.dart';
import 'formula_evaluator.dart';
import 'sheet_data.dart';

const _rowHeight = 28.0;
const _colWidth = 96.0;
const _headerWidth = 40.0;

class SpreadsheetWidget extends StatefulWidget {
  const SpreadsheetWidget({
    super.key,
    required this.workbook,
    required this.onChanged,
  });

  final WorkbookData workbook;
  final ValueChanged<WorkbookData> onChanged;

  @override
  State<SpreadsheetWidget> createState() => _SpreadsheetWidgetState();
}

class _SpreadsheetWidgetState extends State<SpreadsheetWidget> {
  ({int row, int col})? _editing;

  SheetData get _active => widget.workbook.sheets[widget.workbook.activeIndex];

  void _commit(int row, int col, String value) {
    if (!mounted) return;
    final updated = _active.withCell(row, col, value);
    widget.onChanged(widget.workbook.withActiveSheet(updated));
    setState(() => _editing = null);
  }

  void _cancelEdit() {
    if (!mounted) return;
    setState(() => _editing = null);
  }

  void _startEdit(int row, int col) {
    setState(() => _editing = (row: row, col: col));
  }

  void _addRow() => widget.onChanged(
        widget.workbook.withActiveSheet(
          _active.copyWith(rows: _active.rows + 1),
        ),
      );

  void _addCol() => widget.onChanged(
        widget.workbook.withActiveSheet(
          _active.copyWith(cols: _active.cols + 1),
        ),
      );

  void _selectSheet(int idx) =>
      widget.onChanged(widget.workbook.copyWith(activeIndex: idx));

  void _addSheet() {
    final next = [...widget.workbook.sheets];
    next.add(SheetData.blank(name: 'Sheet${next.length + 1}'));
    widget.onChanged(WorkbookData(sheets: next, activeIndex: next.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? MarioColors.borderDark : MarioColors.border;
    final headerBg =
        isDark ? MarioColors.surfaceVariantDark : MarioColors.surfaceVariant;

    return SizedBox(
      height: 400,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _headerWidth + _colWidth * _active.cols,
                child: Column(
                  children: [
                    _ColumnHeaderRow(
                      cols: _active.cols,
                      borderColor: border,
                      bg: headerBg,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (var r = 0; r < _active.rows; r++)
                              _GridRow(
                                row: r,
                                cols: _active.cols,
                                sheet: _active,
                                editing: _editing,
                                borderColor: border,
                                headerBg: headerBg,
                                onTap: _startEdit,
                                onCommit: _commit,
                                onCancel: _cancelEdit,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(top: BorderSide(color: border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Add row',
                  icon: const Icon(Icons.add_box_outlined, size: 16),
                  onPressed: _addRow,
                ),
                IconButton(
                  tooltip: 'Add column',
                  icon: const Icon(Icons.view_column_outlined, size: 16),
                  onPressed: _addCol,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < widget.workbook.sheets.length; i++)
                          _SheetTab(
                            name: widget.workbook.sheets[i].name,
                            selected: i == widget.workbook.activeIndex,
                            onTap: () => _selectSheet(i),
                          ),
                        IconButton(
                          tooltip: 'New sheet',
                          icon: const Icon(Icons.add, size: 16),
                          onPressed: _addSheet,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnHeaderRow extends StatelessWidget {
  const _ColumnHeaderRow({
    required this.cols,
    required this.borderColor,
    required this.bg,
  });

  final int cols;
  final Color borderColor;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _headerWidth),
          for (var c = 0; c < cols; c++)
            Container(
              width: _colWidth,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: borderColor)),
              ),
              child: Text(
                columnLetters(c),
                style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridRow extends StatelessWidget {
  const _GridRow({
    required this.row,
    required this.cols,
    required this.sheet,
    required this.editing,
    required this.borderColor,
    required this.headerBg,
    required this.onTap,
    required this.onCommit,
    required this.onCancel,
  });

  final int row;
  final int cols;
  final SheetData sheet;
  final ({int row, int col})? editing;
  final Color borderColor;
  final Color headerBg;
  final void Function(int row, int col) onTap;
  final void Function(int row, int col, String value) onCommit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight,
      child: Row(
        children: [
          Container(
            width: _headerWidth,
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(
                bottom: BorderSide(color: borderColor),
                right: BorderSide(color: borderColor),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '${row + 1}',
              style: GoogleFonts.inter(
                  fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
          for (var c = 0; c < cols; c++)
            _Cell(
              key: ValueKey('cell-$row-$c'),
              row: row,
              col: c,
              raw: sheet.raw(row, c) ?? '',
              displayed: FormulaEvaluator.evaluate(
                  sheet.raw(row, c) ?? '', sheet),
              isEditing:
                  editing != null && editing!.row == row && editing!.col == c,
              borderColor: borderColor,
              onTap: () => onTap(row, c),
              onCommit: (value) => onCommit(row, c, value),
              onCancel: onCancel,
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.row,
    required this.col,
    required this.raw,
    required this.displayed,
    required this.isEditing,
    required this.borderColor,
    required this.onTap,
    required this.onCommit,
    required this.onCancel,
  });

  final int row;
  final int col;
  final String raw;
  final String displayed;
  final bool isEditing;
  final Color borderColor;
  final VoidCallback onTap;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _colWidth,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor),
        ),
      ),
      child: isEditing
          ? _CellEditor(
              initialValue: raw,
              onCommit: onCommit,
              onCancel: onCancel,
            )
          : InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    displayed,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Owns the FocusNode + controller so they're disposed when editing ends.
/// (The previous implementation built them fresh on every Cell rebuild,
/// which left dangling listeners and fired "used after dispose" exceptions.)
class _CellEditor extends StatefulWidget {
  const _CellEditor({
    required this.initialValue,
    required this.onCommit,
    required this.onCancel,
  });

  final String initialValue;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;

  @override
  State<_CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<_CellEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue)
      ..selection = TextSelection.collapsed(offset: widget.initialValue.length);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit() {
    if (_committed) return;
    _committed = true;
    widget.onCommit(_controller.text);
  }

  void _cancel() {
    if (_committed) return;
    _committed = true;
    widget.onCancel();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _commit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      onFocusChange: (has) {
        if (!has) _commit();
      },
      child: TextField(
        controller: _controller,
        onSubmitted: (_) => _commit(),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 6),
          isDense: true,
        ),
        style: GoogleFonts.inter(fontSize: 12),
      ),
    );
  }
}

class _SheetTab extends StatelessWidget {
  const _SheetTab({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? MarioColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          name,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
