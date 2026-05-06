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
  String? _draft;

  SheetData get _active => widget.workbook.sheets[widget.workbook.activeIndex];

  void _commit() {
    final cell = _editing;
    final draft = _draft;
    if (cell == null) return;
    final updated = _active.withCell(cell.row, cell.col, draft ?? '');
    widget.onChanged(widget.workbook.withActiveSheet(updated));
    setState(() {
      _editing = null;
      _draft = null;
    });
  }

  void _startEdit(int row, int col) {
    setState(() {
      _editing = (row: row, col: col);
      _draft = _active.raw(row, col) ?? '';
    });
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
                                draft: _draft,
                                borderColor: border,
                                headerBg: headerBg,
                                onTap: _startEdit,
                                onCommit: _commit,
                                onDraftChanged: (v) =>
                                    setState(() => _draft = v),
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
          SizedBox(
              width: _headerWidth,
              child: const SizedBox.shrink()),
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
    required this.draft,
    required this.borderColor,
    required this.headerBg,
    required this.onTap,
    required this.onCommit,
    required this.onDraftChanged,
  });

  final int row;
  final int cols;
  final SheetData sheet;
  final ({int row, int col})? editing;
  final String? draft;
  final Color borderColor;
  final Color headerBg;
  final void Function(int row, int col) onTap;
  final VoidCallback onCommit;
  final ValueChanged<String> onDraftChanged;

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
                  right: BorderSide(color: borderColor)),
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
              row: row,
              col: c,
              raw: sheet.raw(row, c) ?? '',
              displayed: FormulaEvaluator.evaluate(
                  sheet.raw(row, c) ?? '', sheet),
              isEditing:
                  editing != null && editing!.row == row && editing!.col == c,
              draft: draft,
              borderColor: borderColor,
              onTap: () => onTap(row, c),
              onCommit: onCommit,
              onDraftChanged: onDraftChanged,
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.row,
    required this.col,
    required this.raw,
    required this.displayed,
    required this.isEditing,
    required this.draft,
    required this.borderColor,
    required this.onTap,
    required this.onCommit,
    required this.onDraftChanged,
  });

  final int row;
  final int col;
  final String raw;
  final String displayed;
  final bool isEditing;
  final String? draft;
  final Color borderColor;
  final VoidCallback onTap;
  final VoidCallback onCommit;
  final ValueChanged<String> onDraftChanged;

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
          ? Focus(
              autofocus: true,
              onFocusChange: (has) {
                if (!has) onCommit();
              },
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (e) {
                  if (e is KeyDownEvent &&
                      (e.logicalKey == LogicalKeyboardKey.enter ||
                          e.logicalKey == LogicalKeyboardKey.tab ||
                          e.logicalKey == LogicalKeyboardKey.escape)) {
                    onCommit();
                  }
                },
                child: TextField(
                  autofocus: true,
                  controller: TextEditingController(text: draft ?? raw)
                    ..selection = TextSelection.collapsed(
                        offset: (draft ?? raw).length),
                  onChanged: onDraftChanged,
                  onSubmitted: (_) => onCommit(),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 6),
                    isDense: true,
                  ),
                  style: GoogleFonts.inter(fontSize: 12),
                ),
              ),
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
