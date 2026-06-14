/// PDF exporter — walks AppFlowy nodes and emits a styled multi-page PDF.
library;

import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/note_page.dart';
import '../../core/services/page_content_repository.dart';

class PdfExporter {
  const PdfExporter(this._content);
  final PageContentRepository _content;

  /// Parsed once and reused across exports — decoding the bundled TTFs on
  /// every call is wasteful and the resulting theme is immutable.
  static Future<pw.ThemeData>? _themeFuture;

  /// A theme whose default/heading/body styles all use Noto Sans, with a
  /// symbol + math fallback chain.
  ///
  /// Without an explicit font the `pdf` package falls back to the built-in
  /// Helvetica Type1 font, which only covers Latin-1. Any other character —
  /// curly quotes, em dashes, accented letters, arrows, math operators, … —
  /// then renders as a missing-glyph box (the "□" / boxed-cross tofu). Noto
  /// Sans covers Latin/Greek/Cyrillic and the fallback faces fill in symbols
  /// and math glyphs; the package picks a fallback per-glyph automatically.
  static Future<pw.ThemeData> _theme() {
    return _themeFuture ??= () async {
      Future<pw.Font> load(String file) async =>
          pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
      final base = await load('NotoSans-Regular.ttf');
      final bold = await load('NotoSans-Bold.ttf');
      final italic = await load('NotoSans-Italic.ttf');
      final boldItalic = await load('NotoSans-BoldItalic.ttf');
      final symbols = await load('NotoSansSymbols-Regular.ttf');
      final symbols2 = await load('NotoSansSymbols2-Regular.ttf');
      final math = await load('NotoSansMath-Regular.ttf');
      return pw.ThemeData.withFont(
        base: base,
        bold: bold,
        italic: italic,
        boldItalic: boldItalic,
        fontFallback: [symbols, symbols2, math],
      );
    }();
  }

  Future<List<int>> renderPage(NotePage page) async {
    final fileId = page.driveFileId;
    if (fileId == null) {
      throw StateError('Page "${page.title}" has no Drive content');
    }
    final raw = await _content.load(fileId);
    final docMap = raw.containsKey('document')
        ? raw
        : <String, dynamic>{'document': raw};
    final document =
        afe.Document.fromJson(Map<String, dynamic>.from(docMap));

    final pdf = pw.Document(theme: await _theme());
    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(48),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              page.title,
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          ..._nodesToWidgets(document.root.children),
        ],
      ),
    );
    return pdf.save();
  }

  List<pw.Widget> _nodesToWidgets(Iterable<afe.Node> nodes) {
    final widgets = <pw.Widget>[];
    for (final n in nodes) {
      widgets.addAll(_nodeToWidgets(n, 0));
    }
    return widgets;
  }

  List<pw.Widget> _nodeToWidgets(afe.Node node, int indent) {
    final text = node.delta?.toPlainText() ?? '';
    switch (node.type) {
      case 'heading':
        final level = (node.attributes['level'] as int?) ?? 1;
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
            child: pw.Text(
              text,
              style: pw.TextStyle(
                fontSize: switch (level) {
                  1 => 22.0,
                  2 => 18.0,
                  _ => 15.0,
                },
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ];
      case 'bulleted_list':
        return [_listItem('•', text, indent), ..._childWidgets(node, indent + 1)];
      case 'numbered_list':
        return [_listItem('1.', text, indent), ..._childWidgets(node, indent + 1)];
      case 'todo_list':
        final done = (node.attributes['checked'] as bool?) ?? false;
        return [
          _listItem(done ? '[x]' : '[ ]', text, indent),
          ..._childWidgets(node, indent + 1),
        ];
      case 'quote':
        return [
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 4),
            padding: const pw.EdgeInsets.only(left: 12),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                  left: pw.BorderSide(color: PdfColors.grey, width: 2)),
            ),
            child: pw.Text(text,
                style: const pw.TextStyle(color: PdfColors.grey700)),
          ),
        ];
      case 'code':
        return [
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 4),
            padding: const pw.EdgeInsets.all(6),
            color: PdfColors.grey100,
            child: pw.Text(text,
                style:
                    const pw.TextStyle(fontSize: 11, color: PdfColors.black)),
          ),
        ];
      case 'divider':
        return [
          pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Divider(thickness: 0.5)),
        ];
      case 'image':
        final url = node.attributes['url'] as String?;
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Text('[image: ${url ?? 'inline'}]',
                style: const pw.TextStyle(color: PdfColors.grey)),
          ),
        ];
      case 'math_equation':
        final f = (node.attributes['formula'] as String?) ?? '';
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Text('[math] $f',
                style: const pw.TextStyle(color: PdfColors.grey)),
          ),
        ];
      case 'drawing':
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Text('[drawing]',
                style: const pw.TextStyle(color: PdfColors.grey)),
          ),
        ];
      case 'spreadsheet':
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Text('[spreadsheet]',
                style: const pw.TextStyle(color: PdfColors.grey)),
          ),
        ];
      case 'audio_clip':
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Text('[audio clip]',
                style: const pw.TextStyle(color: PdfColors.grey)),
          ),
        ];
      case 'table':
        final table = _tableWidget(node);
        return table == null ? const [] : [table];
      default:
        if (text.isEmpty) return [pw.SizedBox(height: 6)];
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(text, style: const pw.TextStyle(fontSize: 12)),
          ),
        ];
    }
  }

  pw.Widget _listItem(String bullet, String text, int indent) {
    return pw.Padding(
      padding: pw.EdgeInsets.fromLTRB(12.0 * indent, 2, 0, 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
              width: 18,
              child: pw.Text(bullet,
                  style: const pw.TextStyle(fontSize: 12))),
          pw.Expanded(child: pw.Text(text)),
        ],
      ),
    );
  }

  List<pw.Widget> _childWidgets(afe.Node node, int indent) {
    final widgets = <pw.Widget>[];
    for (final c in node.children) {
      widgets.addAll(_nodeToWidgets(c, indent));
    }
    return widgets;
  }

  /// Renders an AppFlowy `table` node as a bordered grid. Cells are `table/cell`
  /// children carrying `rowPosition`/`colPosition`; their text lives in nested
  /// block children. Returns null for a malformed/empty table.
  pw.Widget? _tableWidget(afe.Node node) {
    final cols = (node.attributes['colsLen'] as int?) ?? 0;
    final rows = (node.attributes['rowsLen'] as int?) ?? 0;
    if (cols <= 0 || rows <= 0) return null;

    final grid =
        List.generate(rows, (_) => List<String>.filled(cols, ''), growable: false);
    for (final cell in node.children) {
      if (cell.type != 'table/cell') continue;
      final r = cell.attributes['rowPosition'] as int?;
      final c = cell.attributes['colPosition'] as int?;
      if (r == null || c == null || r < 0 || c < 0 || r >= rows || c >= cols) {
        continue;
      }
      grid[r][c] = _cellText(cell);
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
        // Equal-width columns that wrap, so wide content can't overflow the page.
        columnWidths: {
          for (var i = 0; i < cols; i++) i: const pw.FlexColumnWidth(),
        },
        children: [
          for (final row in grid)
            pw.TableRow(
              children: [
                for (final cellText in row)
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(cellText,
                        style: const pw.TextStyle(fontSize: 11)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Flattens all text in a table cell (cells hold block children, usually a
  /// single paragraph) into a newline-joined string.
  String _cellText(afe.Node cell) {
    final parts = <String>[];
    void walk(afe.Node n) {
      final t = n.delta?.toPlainText();
      if (t != null && t.isNotEmpty) parts.add(t);
      for (final c in n.children) {
        walk(c);
      }
    }

    for (final c in cell.children) {
      walk(c);
    }
    return parts.join('\n');
  }

  Future<void> exportPageToFile(BuildContext context, NotePage page) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('PDF export from web is not yet supported'),
      ));
      return;
    }
    try {
      final bytes = await renderPage(page);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export to PDF',
        fileName: '${_safe(page.title)}.pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exported to $path')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  String _safe(String s) =>
      s.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(' ', '-');
}
