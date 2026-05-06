/// XlsxParser — bidirectional bridge between WorkbookData and the `excel` package.
library;

import 'package:excel/excel.dart';

import 'sheet_data.dart';

class XlsxParser {
  const XlsxParser._();

  /// Decode .xlsx bytes into a [WorkbookData].
  static WorkbookData decode(List<int> bytes) {
    final book = Excel.decodeBytes(bytes);
    final sheets = <SheetData>[];
    for (final entry in book.tables.entries) {
      final t = entry.value;
      final cells = <String, String>{};
      var rows = 0;
      var cols = 0;
      for (final row in t.rows) {
        for (final data in row) {
          if (data == null) continue;
          final value = data.value;
          if (value == null) continue;
          final raw = _cellValueToString(value);
          if (raw.isEmpty) continue;
          cells[cellId(data.rowIndex, data.columnIndex)] = raw;
          if (data.rowIndex + 1 > rows) rows = data.rowIndex + 1;
          if (data.columnIndex + 1 > cols) cols = data.columnIndex + 1;
        }
      }
      sheets.add(SheetData(
        name: entry.key,
        rows: rows < 10 ? 10 : rows,
        cols: cols < 10 ? 10 : cols,
        cells: cells,
      ));
    }
    if (sheets.isEmpty) sheets.add(SheetData.blank());
    return WorkbookData(sheets: sheets);
  }

  /// Serialise a [WorkbookData] back to .xlsx bytes.
  static List<int> encode(WorkbookData workbook) {
    final book = Excel.createExcel();
    // Excel.createExcel seeds a Sheet1; rename / fill it with our first sheet,
    // then append the rest.
    final defaultName = book.tables.keys.first;
    for (var i = 0; i < workbook.sheets.length; i++) {
      final src = workbook.sheets[i];
      String targetName;
      if (i == 0) {
        targetName = src.name;
        if (targetName != defaultName) {
          book.rename(defaultName, targetName);
        }
      } else {
        targetName = src.name;
        // copy creates a new sheet with the given name.
        book.copy(defaultName, targetName);
      }
      final t = book.tables[targetName]!;
      src.cells.forEach((id, raw) {
        final idx = parseCellId(id);
        if (idx == null) return;
        t.updateCell(
          CellIndex.indexByColumnRow(
              columnIndex: idx.col, rowIndex: idx.row),
          _stringToCellValue(raw),
        );
      });
    }
    return book.encode() ?? const [];
  }

  static String _cellValueToString(CellValue v) {
    if (v is TextCellValue) return v.value.toString();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return v.value.toString();
    if (v is BoolCellValue) return v.value.toString();
    if (v is FormulaCellValue) {
      final f = v.formula;
      return f.startsWith('=') ? f : '=$f';
    }
    if (v is DateCellValue) return v.toString();
    return v.toString();
  }

  static CellValue _stringToCellValue(String raw) {
    if (raw.startsWith('=')) return FormulaCellValue(raw.substring(1));
    final asInt = int.tryParse(raw);
    if (asInt != null) return IntCellValue(asInt);
    final asDouble = double.tryParse(raw);
    if (asDouble != null) return DoubleCellValue(asDouble);
    return TextCellValue(raw);
  }
}
