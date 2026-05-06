/// Markdown exporter — AppFlowy Document → .md via the package's encoder.
library;

import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/note_page.dart';
import '../../core/services/drive_service.dart';

class MarkdownExporter {
  const MarkdownExporter(this._drive);
  final DriveService _drive;

  /// Render the page's Drive document to Markdown and return the string.
  Future<String> renderPage(NotePage page) async {
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
    final body = afe.documentToMarkdown(document);
    return '# ${page.title}\n\n$body';
  }

  /// Run the full flow: prompt for save location, write the .md.
  Future<void> exportPageToFile(BuildContext context, NotePage page) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Export to .md from web is not yet supported'),
      ));
      return;
    }
    try {
      final markdown = await renderPage(page);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export to Markdown',
        fileName: '${_safeFilename(page.title)}.md',
        type: FileType.custom,
        allowedExtensions: const ['md'],
      );
      if (path == null) return;
      await File(path).writeAsString(markdown);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exported to $path')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  String _safeFilename(String title) =>
      title.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(' ', '-');
}
