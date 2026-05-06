/// SheetData / WorkbookData — flat-map cell model, row/col counts, JSON round-trip.
library;

class SheetData {
  /// Map keyed by "A1"/"B2" style addresses → user's raw text (formula or literal).
  final Map<String, String> cells;
  final String name;
  final int rows;
  final int cols;

  const SheetData({
    required this.name,
    required this.rows,
    required this.cols,
    this.cells = const {},
  });

  String? raw(int row, int col) => cells[cellId(row, col)];

  SheetData withCell(int row, int col, String value) {
    final next = Map<String, String>.from(cells);
    final id = cellId(row, col);
    if (value.isEmpty) {
      next.remove(id);
    } else {
      next[id] = value;
    }
    return copyWith(cells: next);
  }

  SheetData copyWith({
    String? name,
    int? rows,
    int? cols,
    Map<String, String>? cells,
  }) =>
      SheetData(
        name: name ?? this.name,
        rows: rows ?? this.rows,
        cols: cols ?? this.cols,
        cells: cells ?? this.cells,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'rows': rows,
        'cols': cols,
        'cells': cells,
      };

  factory SheetData.fromMap(Map<String, dynamic> m) => SheetData(
        name: m['name'] as String? ?? 'Sheet',
        rows: m['rows'] as int? ?? 10,
        cols: m['cols'] as int? ?? 10,
        cells: Map<String, String>.from(m['cells'] as Map? ?? const {}),
      );

  factory SheetData.blank({String name = 'Sheet1', int rows = 10, int cols = 10}) =>
      SheetData(name: name, rows: rows, cols: cols);
}

class WorkbookData {
  final List<SheetData> sheets;
  final int activeIndex;

  const WorkbookData({required this.sheets, this.activeIndex = 0});

  WorkbookData copyWith({List<SheetData>? sheets, int? activeIndex}) =>
      WorkbookData(
        sheets: sheets ?? this.sheets,
        activeIndex: activeIndex ?? this.activeIndex,
      );

  WorkbookData withActiveSheet(SheetData updated) {
    final next = [...sheets];
    next[activeIndex] = updated;
    return copyWith(sheets: next);
  }

  Map<String, dynamic> toMap() => {
        'sheets': sheets.map((s) => s.toMap()).toList(),
        'activeIndex': activeIndex,
      };

  factory WorkbookData.fromMap(Map<String, dynamic> m) {
    final list = (m['sheets'] as List?)
            ?.map((s) => SheetData.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList() ??
        [SheetData.blank()];
    return WorkbookData(
      sheets: list.isEmpty ? [SheetData.blank()] : list,
      activeIndex: (m['activeIndex'] as int? ?? 0).clamp(0, list.length - 1),
    );
  }

  factory WorkbookData.blank() =>
      WorkbookData(sheets: [SheetData.blank()]);
}

/// Convert a 0-indexed column to its letter form (0→A, 25→Z, 26→AA).
String columnLetters(int col) {
  if (col < 0) throw ArgumentError('col must be >= 0');
  var n = col;
  final buf = StringBuffer();
  do {
    buf.write(String.fromCharCode(0x41 + (n % 26)));
    n = (n ~/ 26) - 1;
  } while (n >= 0);
  return buf.toString().split('').reversed.join();
}

/// Build an "A1"-style id from 0-indexed (row, col).
String cellId(int row, int col) => '${columnLetters(col)}${row + 1}';

/// Parse an "A1"-style id to (row, col). Returns null on bad input.
({int row, int col})? parseCellId(String s) {
  final m = RegExp(r'^([A-Za-z]+)(\d+)$').firstMatch(s.trim());
  if (m == null) return null;
  final letters = m.group(1)!.toUpperCase();
  final number = int.tryParse(m.group(2)!);
  if (number == null || number < 1) return null;
  var col = 0;
  for (final c in letters.codeUnits) {
    col = col * 26 + (c - 0x41 + 1);
  }
  return (row: number - 1, col: col - 1);
}
