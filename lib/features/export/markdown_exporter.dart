/// Markdown exporter — AppFlowy Document → .md via the package's encoder.
library;

import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/note_page.dart';
import '../../core/services/asset_sync_service.dart';
import '../../core/services/page_content_repository.dart';
import '../editor/image_asset_resolver.dart';

class MarkdownExporter {
  const MarkdownExporter(this._content, this._assets);
  final PageContentRepository _content;
  final AssetSyncService _assets;

  /// Render the page's Drive document to Markdown and return the string.
  Future<String> renderPage(NotePage page) async {
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
    // Point the image links at files that exist here. The encoder writes each
    // node's `url`, which is the path on whichever device inserted the picture
    // — fetch anything this machine is missing so the export is complete
    // rather than full of dead links.
    final substitutions = await resolveImageSources(document, _assets,
        fetchMissing: true);
    final body = rewriteMarkdownImageSources(
        afe.documentToMarkdown(document), substitutions);
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
