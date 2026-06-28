/// PDF exporter — walks AppFlowy nodes and emits a styled multi-page PDF.
library;

import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/note_page.dart';
import '../../core/services/page_content_repository.dart';

class PdfExporter {
  PdfExporter(this._content);
  final PageContentRepository _content;

  /// Image bytes pre-loaded for the page currently being rendered, keyed by the
  /// node's `url` attribute. Populated by [_preloadImages] before the synchronous
  /// node-walk runs, since loading from disk/network is async and widget builders
  /// are not. Cleared at the start of every [renderPage].
  final Map<String, pw.MemoryImage> _images = {};

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

    _images.clear();
    await _preloadImages(document.root.children);

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

  /// Usable width inside the page margins (`EdgeInsets.all(48)`). The default
  /// MultiPage format is A4 (595.28pt wide); 48pt margins leave ~499pt. Kept a
  /// touch under that so images never quite touch the edge.
  static const double _contentWidth = 495;

  /// Walks every node (including children and table cells) collecting `image`
  /// URLs, then loads each one concurrently into [_images]. Failures are left
  /// out of the map — the render path shows an "unavailable" marker for those.
  Future<void> _preloadImages(Iterable<afe.Node> nodes) async {
    final urls = <String>{};
    void collect(afe.Node n) {
      if (n.type == 'image') {
        final u = n.attributes['url'];
        if (u is String && u.isNotEmpty) urls.add(u);
      }
      for (final c in n.children) {
        collect(c);
      }
    }

    for (final n in nodes) {
      collect(n);
    }

    await Future.wait(urls.map((u) async {
      final img = await _loadImage(u);
      if (img != null) _images[u] = img;
    }));
  }

  /// Loads image bytes from an http(s) URL or a local path (`file://` or a bare
  /// filesystem path) and wraps them in a [pw.MemoryImage]. Returns null on any
  /// failure (missing file, network error, undecodable bytes).
  Future<pw.MemoryImage?> _loadImage(String src) async {
    try {
      final Uint8List bytes;
      if (src.startsWith('http://') || src.startsWith('https://')) {
        final resp = await http.get(Uri.parse(src));
        if (resp.statusCode != 200) return null;
        bytes = resp.bodyBytes;
      } else {
        final path = src.startsWith('file://') ? Uri.parse(src).toFilePath() : src;
        final file = File(path);
        if (!await file.exists()) return null;
        bytes = await file.readAsBytes();
      }
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
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
            child: _deltaWidget(
              node.delta,
              base: pw.TextStyle(
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
        return [_listItem('•', node, indent), ..._childWidgets(node, indent + 1)];
      case 'numbered_list':
        return [_listItem('1.', node, indent), ..._childWidgets(node, indent + 1)];
      case 'todo_list':
        final done = (node.attributes['checked'] as bool?) ?? false;
        return [
          _listItem(done ? '[x]' : '[ ]', node, indent),
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
            child: _deltaWidget(node.delta,
                base: const pw.TextStyle(color: PdfColors.grey700)),
          ),
        ];
      case 'code':
        // Code blocks store their source in the `code` attribute (see
        // CodeBlock); fall back to delta text for markdown/html-pasted blocks.
        final codeText = (node.attributes['code'] as String?) ?? text;
        // Emit one full-width banded row per line instead of a single Container.
        // A decorated Container can't split across pages, so a tall code block
        // throws "Widget won't fit into the page"; a flat list of short rows
        // lets MultiPage break between lines while keeping a continuous
        // background.
        const codeStyle = pw.TextStyle(fontSize: 10.5, color: PdfColors.black);
        return [
          pw.SizedBox(height: 4),
          for (final line in codeText.split('\n'))
            pw.Container(
              width: double.infinity,
              color: PdfColors.grey100,
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
              child: pw.Text(line.isEmpty ? ' ' : line, style: codeStyle),
            ),
          pw.SizedBox(height: 4),
        ];
      case 'divider':
        return [
          pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Divider(thickness: 0.5)),
        ];
      case 'image':
        final url = node.attributes['url'] as String?;
        final image = url == null ? null : _images[url];
        if (image == null) {
          // Couldn't load it (missing file, unreachable URL, bad bytes) — show
          // a marker rather than silently dropping the block.
          return [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Text('[image unavailable: ${url ?? 'inline'}]',
                  style: const pw.TextStyle(color: PdfColors.grey)),
            ),
          ];
        }
        // Use the editor's display width when set, else the image's natural
        // width, capped to the page content area so wide photos don't overflow.
        // `BoxFit.contain` keeps the aspect ratio and never upscales past this.
        final stored = (node.attributes['width'] as num?)?.toDouble();
        final natural = image.width?.toDouble();
        var width = stored ?? natural ?? _contentWidth;
        if (width > _contentWidth) width = _contentWidth;
        return [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Image(image, width: width),
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
            child: _deltaWidget(node.delta,
                base: const pw.TextStyle(fontSize: 12)),
          ),
        ];
    }
  }

  pw.Widget _listItem(String bullet, afe.Node node, int indent) {
    return pw.Padding(
      padding: pw.EdgeInsets.fromLTRB(12.0 * indent, 2, 0, 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
              width: 18,
              child: pw.Text(bullet,
                  style: const pw.TextStyle(fontSize: 12))),
          pw.Expanded(
              child: _deltaWidget(node.delta,
                  base: const pw.TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  /// Builds a rich-text widget from an AppFlowy [delta], honouring inline marks
  /// (bold, italic, underline, strikethrough, code, text colour). Falls back to
  /// a plain empty [pw.Text] when the delta is null or carries no insertions —
  /// `toPlainText()` alone would drop every one of those marks.
  pw.Widget _deltaWidget(afe.Delta? delta, {required pw.TextStyle base}) {
    final spans = delta == null ? const <pw.TextSpan>[] : _deltaSpans(delta, base);
    if (spans.isEmpty) return pw.Text('', style: base);
    return pw.RichText(text: pw.TextSpan(style: base, children: spans));
  }

  List<pw.TextSpan> _deltaSpans(afe.Delta delta, pw.TextStyle base) {
    final spans = <pw.TextSpan>[];
    for (final op in delta) {
      if (op is! afe.TextInsert || op.text.isEmpty) continue;
      final attrs = op.attributes ?? const {};
      var style = base;

      final bold = attrs[afe.AppFlowyRichTextKeys.bold] == true;
      final italic = attrs[afe.AppFlowyRichTextKeys.italic] == true;
      if (bold) style = style.copyWith(fontWeight: pw.FontWeight.bold);
      if (italic) style = style.copyWith(fontStyle: pw.FontStyle.italic);

      final decorations = <pw.TextDecoration>[];
      if (attrs[afe.AppFlowyRichTextKeys.underline] == true) {
        decorations.add(pw.TextDecoration.underline);
      }
      if (attrs[afe.AppFlowyRichTextKeys.strikethrough] == true) {
        decorations.add(pw.TextDecoration.lineThrough);
      }
      if (decorations.isNotEmpty) {
        style = style.copyWith(
          decoration: pw.TextDecoration.combine(decorations),
        );
      }

      if (attrs[afe.AppFlowyRichTextKeys.code] == true) {
        style = style.copyWith(
          background: const pw.BoxDecoration(color: PdfColors.grey200),
          color: PdfColors.red800,
        );
      }

      final color = _parseColor(attrs[afe.AppFlowyRichTextKeys.textColor]);
      if (color != null) style = style.copyWith(color: color);

      spans.add(pw.TextSpan(text: op.text, style: style));
    }
    return spans;
  }

  /// AppFlowy stores inline colours as ARGB hex strings such as `0xFF1A1A1A`.
  PdfColor? _parseColor(Object? raw) {
    if (raw is! String) return null;
    final v = int.tryParse(raw);
    return v == null ? null : PdfColor.fromInt(v);
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

    final grid = List.generate(
        rows, (_) => List<afe.Node?>.filled(cols, null),
        growable: false);
    for (final cell in node.children) {
      if (cell.type != 'table/cell') continue;
      final r = cell.attributes['rowPosition'] as int?;
      final c = cell.attributes['colPosition'] as int?;
      if (r == null || c == null || r < 0 || c < 0 || r >= rows || c >= cols) {
        continue;
      }
      grid[r][c] = cell;
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
                for (final cell in row)
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: _cellWidget(cell),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Renders a table cell's block children as a column of rich-text lines,
  /// keeping inline marks. Cells usually hold a single paragraph.
  pw.Widget _cellWidget(afe.Node? cell) {
    const base = pw.TextStyle(fontSize: 11);
    if (cell == null) return pw.Text('', style: base);
    final lines = <pw.Widget>[];
    void walk(afe.Node n) {
      if (n.delta != null) {
        lines.add(_deltaWidget(n.delta, base: base));
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    for (final c in cell.children) {
      walk(c);
    }
    if (lines.isEmpty) return pw.Text('', style: base);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: lines,
    );
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
