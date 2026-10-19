/// The export choice as a macOS sheet — the desktop builds' counterpart of
/// `ExportDialog`.
///
/// Laid out like a Mac app's own Export sheet: a classic form with the page
/// it exports, a Format pop-up and, for a PDF, a Paper Size pop-up; Cancel
/// and the prominent Export button at the bottom right. Return exports,
/// Escape cancels. It collects the same choice and returns the same
/// [ExportRequest]; the editor still does the export itself (see
/// `export_dialog.dart` for why).
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/note_page.dart';
import 'export_dialog.dart';
import 'pdf_exporter.dart';

/// Shows the sheet over the window. Null when it is cancelled.
Future<ExportRequest?> showMacExportSheet(
  BuildContext context, {
  required NotePage page,
}) =>
    showMacSheet<ExportRequest>(
      context: context,
      builder: (_) => MacExportSheet(page: page),
    );

class MacExportSheet extends ConsumerStatefulWidget {
  const MacExportSheet({super.key, required this.page});

  final NotePage page;

  @override
  ConsumerState<MacExportSheet> createState() => _MacExportSheetState();
}

class _MacExportSheetState extends ConsumerState<MacExportSheet> {
  ExportFormat _format = ExportFormat.pdf;
  PdfPaperSize _paper = PdfPaperSize.a4;

  void _submit() =>
      Navigator.of(context).pop(ExportRequest(format: _format, paper: _paper));

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final c = context.macColors;
    final type = MacTypography.of(context);
    final isPdf = _format == ExportFormat.pdf;
    final crumbs = exportCrumbs(ref, widget.page);

    return MacSheet(
      title: 'Export This Page',
      width: 440,
      onSubmit: _submit,
      onCancel: _cancel,
      actions: [
        MacButton(label: 'Cancel', onPressed: _cancel),
        MacButton(
          label: isPdf ? 'Export PDF' : 'Export Markdown',
          style: MacButtonStyle.prominent,
          onPressed: _submit,
        ),
      ],
      child: MacForm(
        columns: true,
        children: [
          if (crumbs.isNotEmpty)
            MacFormRow(
              label: 'Page:',
              child: Text(
                crumbs.join(' › '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: type.body.copyWith(color: c.labelPrimary),
              ),
            ),
          MacFormRow(
            label: 'Format:',
            // What each format really produces — the same caveats the
            // Material dialog's cards carry, for the same reasons.
            note: isPdf
                ? 'Paginated, with your images. Drawings and equations '
                    'come out as placeholders.'
                : 'Plain text. Images link to your local copies, so the '
                    'file will not travel on its own.',
            child: MacPopUpButton<ExportFormat>(
              options: const [ExportFormat.pdf, ExportFormat.markdown],
              value: _format,
              labelOf: (f) => switch (f) {
                ExportFormat.pdf => 'PDF',
                ExportFormat.markdown => 'Markdown',
              },
              onChanged: (f) => setState(() => _format = f),
              semanticLabel: 'Format',
            ),
          ),
          // Paper and the font note belong to the PDF only: Markdown has no
          // page box, and its text is whatever font opens the file.
          if (isPdf)
            MacFormRow(
              label: 'Paper Size:',
              note: 'Noto fonts are bundled, so non-Latin scripts and maths '
                  'symbols render in the PDF.',
              child: MacPopUpButton<PdfPaperSize>(
                options: PdfPaperSize.values,
                value: _paper,
                labelOf: (p) => p.label,
                onChanged: (p) => setState(() => _paper = p),
                semanticLabel: 'Paper size',
              ),
            ),
        ],
      ),
    );
  }
}
