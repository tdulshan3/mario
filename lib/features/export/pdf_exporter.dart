/// PDF exporter — walks AppFlowy nodes and emits a styled multi-page PDF.
library;

import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/note_page.dart';
import '../../core/services/drive_service.dart';

class PdfExporter {
  const PdfExporter(this._drive);
  final DriveService _drive;

  Future<List<int>> renderPage(NotePage page) async {
    final fileId = page.driveFileId;
    if (fileId == null) {
      throw StateError('Page "${page.title}" has no Drive content');
    }
    final raw = await _drive.readPageFile(fileId);
    final docMap = raw.containsKey('document')
        ? raw
        : <String, dynamic>{'document': raw};
    final document =
        afe.Document.fromJson(Map<String, dynamic>.from(docMap));

    final pdf = pw.Document();
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
