/// Export dialog (artboard 2i) — choose a format and a paper, then export.
///
/// The dialog only *collects the choice*; the caller owns the export itself,
/// because the editor has to flush its pending autosave before either exporter
/// reads the page back from Drive. So this returns an [ExportRequest] and
/// nothing more.
///
/// What it deliberately does not draw: the design's "Include canvas drawings"
/// and "Include the whole section" switches. Neither exporter can honour
/// either — see the note on [ExportRequest].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/note_page.dart';
import '../../ui/colors.dart';
import '../../ui/mac/mac_look.dart';
import '../../ui/theme.dart';
import '../shell/shell_state.dart' as shell;
import 'mac_export_sheet.dart';
import 'pdf_exporter.dart';

/// The two exporters the app has.
enum ExportFormat { pdf, markdown }

/// What the user asked for.
///
/// [paper] is meaningful for [ExportFormat.pdf] only — Markdown has no pages —
/// so the dialog hides the paper control unless PDF is selected rather than
/// leaving a live control that changes nothing.
///
/// There is no `includeDrawings` here on purpose. [PdfExporter] emits a
/// `[drawing]` text marker for a `drawing` block and never reads the page's
/// canvas `strokes` at all, so a switch would be promising artwork that no
/// code path can produce. Likewise no `includeSection`: both exporters take a
/// single [NotePage] and the app has no section-level export.
class ExportRequest {
  const ExportRequest({required this.format, required this.paper});

  final ExportFormat format;
  final PdfPaperSize paper;
}

/// Shows the dialog. Resolves to null when it is dismissed or cancelled.
///
/// The desktop builds ask the same question in a macOS sheet attached to the
/// window, and get the same [ExportRequest] back.
Future<ExportRequest?> showExportDialog(
  BuildContext context, {
  required NotePage page,
}) {
  if (useMacLook) return showMacExportSheet(context, page: page);
  return showDialog<ExportRequest>(
    context: context,
    builder: (_) => ExportDialog(page: page),
  );
}

/// The page's place in the tree: notebook, section, page — each name only
/// once it has arrived from the live index.
///
/// A notebook or section whose name has not arrived — or that has gone away —
/// drops its crumb instead of printing a stand-in, so the line is short
/// rather than wrong.
List<String> exportCrumbs(WidgetRef ref, NotePage page) {
  String? nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  String? notebookName;
  if (page.notebookId.isNotEmpty) {
    final notebooks = ref.watch(shell.notebooksStreamProvider).valueOrNull;
    for (final n in notebooks ?? const []) {
      if (n.id == page.notebookId) notebookName = nonEmpty(n.name);
    }
  }
  String? sectionName;
  if (page.notebookId.isNotEmpty && page.sectionId.isNotEmpty) {
    final sections =
        ref.watch(shell.sectionsStreamProvider(page.notebookId)).valueOrNull;
    for (final s in sections ?? const []) {
      if (s.id == page.sectionId) sectionName = nonEmpty(s.name);
    }
  }

  return <String>[
    if (notebookName != null) notebookName,
    if (sectionName != null) sectionName,
    if (nonEmpty(page.title) != null) page.title.trim(),
  ];
}

class ExportDialog extends ConsumerStatefulWidget {
  const ExportDialog({super.key, required this.page});

  final NotePage page;

  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<ExportDialog> {
  ExportFormat _format = ExportFormat.pdf;
  PdfPaperSize _paper = PdfPaperSize.a4;

  void _submit() =>
      Navigator.of(context).pop(ExportRequest(format: _format, paper: _paper));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isPdf = _format == ExportFormat.pdf;

    return Dialog(
      backgroundColor: scheme.surfaceContainerHighest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MarioRadius.card),
        side: BorderSide(color: scheme.outline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(MarioSpace.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Export this page',
                style: textTheme.headlineMedium?.copyWith(fontSize: 22),
              ),
              const SizedBox(height: MarioSpace.x2),
              _Breadcrumb(page: widget.page),
              const SizedBox(height: MarioSpace.x6),
              _FormatCard(
                icon: Icons.picture_as_pdf_outlined,
                title: 'PDF',
                // The design's blurb promised drawings and maths. Neither
                // renders: pdf_exporter emits the literal text '[drawing]'
                // and '[math] <formula>' for those blocks, and the full-page
                // canvas is stored under a top-level `strokes` key the
                // exporter never reads. Say what comes out, so nobody
                // discovers it from a printed page.
                blurb: 'Paginated, with your images. Drawings and equations '
                    'come out as placeholders.',
                selected: isPdf,
                onTap: () => setState(() => _format = ExportFormat.pdf),
              ),
              const SizedBox(height: MarioSpace.x2),
              _FormatCard(
                icon: Icons.notes_outlined,
                title: 'Markdown',
                // No folder is written. exportPageToFile does a single
                // writeAsString, and image links are rewritten to absolute
                // paths inside the app's private cache — so the .md works
                // here and breaks the moment it is moved or sent.
                blurb: 'Plain text. Images link to your local copies, so the '
                    'file will not travel on its own.',
                selected: !isPdf,
                onTap: () => setState(() => _format = ExportFormat.markdown),
              ),
              // Paper and the font note belong to the PDF only: Markdown has
              // no page box, and its text is whatever font opens the file.
              if (isPdf) ...[
                const SizedBox(height: MarioSpace.x6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Paper size',
                        style: textTheme.labelLarge
                            ?.copyWith(color: scheme.onSurface),
                      ),
                    ),
                    _Segmented<PdfPaperSize>(
                      value: _paper,
                      items: PdfPaperSize.values,
                      labelOf: (p) => p.label,
                      onChanged: (p) => setState(() => _paper = p),
                    ),
                  ],
                ),
                const SizedBox(height: MarioSpace.x4),
                const _InfoLine(
                  'Noto fonts are bundled, so non-Latin scripts and maths '
                  'symbols render in the PDF.',
                ),
              ],
              const SizedBox(height: MarioSpace.x6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    // The theme paints TextButton labels in the primary, and
                    // gold ink is 1.59:1 on the light grounds. Cancel is a
                    // quiet action anyway, so it takes the muted ink.
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: MarioSpace.x2),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.download_outlined, size: 17),
                    label: Text(isPdf ? 'Export PDF' : 'Export Markdown'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page's place in the tree, muted, under the title.
///
/// Names come from the same live index the page header reads, through
/// [exportCrumbs].
class _Breadcrumb extends ConsumerWidget {
  const _Breadcrumb({required this.page});

  final NotePage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final crumbs = exportCrumbs(ref, page);
    if (crumbs.isEmpty) return const SizedBox.shrink();

    final muted = textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < crumbs.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MarioSpace.x1),
              child: Icon(Icons.chevron_right,
                  size: 14, color: scheme.onSurfaceVariant),
            ),
          Text(
            crumbs[i],
            // The last crumb is the page itself — same muted tone, a little
            // more weight so the eye lands on it.
            style: i == crumbs.length - 1
                ? muted?.copyWith(fontWeight: FontWeight.w600)
                : muted,
          ),
        ],
      ],
    );
  }
}

/// One of the two format choices — a card at [MarioRadius.md], outlined in the
/// primary when it is the selected one.
class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String blurb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dark = marioMode(context).isDark;

    // Gold is a fill, not an ink: on the light grounds it is 1.59:1 against
    // the surface, so the "chosen" mark uses the deep step of the same ramp
    // and only goes gold where the ground is dark enough to carry it.
    final mark = dark ? scheme.primary : MarioColors.accent700;

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: dark ? 0.16 : 0.14)
          : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MarioRadius.md),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outline,
          width: selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MarioSpace.x4,
            vertical: MarioSpace.x3,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? mark : scheme.onSurface),
              const SizedBox(width: MarioSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleLarge?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      blurb,
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MarioSpace.x2),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? mark : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The info row under the paper control — an icon and one muted sentence.
class _InfoLine extends StatelessWidget {
  const _InfoLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: MarioSpace.x2),
        Expanded(
          child: Text(
            message,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// `.seg` — the design's segmented control: one pill, hairline-divided, the
/// chosen segment filled in the primary with the navy ink that reads on gold.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(MarioRadius.pill),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Container(width: 1, height: 30, color: scheme.outline),
            _SegOption(
              label: labelOf(items[i]),
              selected: items[i] == value,
              onTap: () => onChanged(items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegOption extends StatelessWidget {
  const _SegOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = selected ? scheme.onPrimary : scheme.onSurface;
    return Material(
      color: selected ? scheme.primary : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(label, style: TextStyle(fontSize: 13, color: ink)),
        ),
      ),
    );
  }
}
