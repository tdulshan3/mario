/// Rendering a model's answer as what it actually is.
///
/// Models reply in Markdown — headings, bullets, `code`, **emphasis**, tables —
/// and showing that as plain text means the user reads the punctuation instead
/// of the structure. A list of five points arrives as five lines each beginning
/// with a stray hyphen; a formula in backticks reads as a formula in backticks.
///
/// Uses `flutter_markdown`, which was already a declared dependency and until
/// now unused. Two things it needs on top of the defaults: the app's own
/// typography, so an answer does not look pasted in from another program, and
/// tappable links, since a cited source is only a citation if you can follow it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/colors.dart';

/// A model answer, rendered.
///
/// [selectable] is on by default — an answer people want to quote from is an
/// answer they need to select.
class AiMarkdown extends StatelessWidget {
  const AiMarkdown(
    this.data, {
    super.key,
    this.selectable = true,
    this.fontSize = 13,
  });

  final String data;
  final bool selectable;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = GoogleFonts.inter(
      fontSize: fontSize,
      height: 1.5,
      color: scheme.onSurface,
    );

    return MarkdownBody(
      data: data,
      selectable: selectable,
      onTapLink: (text, href, title) {
        if (href == null || href.isEmpty) return;
        final uri = Uri.tryParse(href);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      styleSheet: MarkdownStyleSheet(
        p: body,
        listBullet: body,
        a: body.copyWith(
          color: MarioColors.primaryPressed,
          decoration: TextDecoration.underline,
          decorationColor: MarioColors.primaryPressed.withValues(alpha: 0.4),
        ),
        strong: body.copyWith(fontWeight: FontWeight.w600),
        em: body.copyWith(fontStyle: FontStyle.italic),
        // Headings inside a 360px panel: the stock scale makes an h1 shout.
        h1: GoogleFonts.spaceGrotesk(
            fontSize: fontSize + 3,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface),
        h2: GoogleFonts.spaceGrotesk(
            fontSize: fontSize + 2,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface),
        h3: GoogleFonts.spaceGrotesk(
            fontSize: fontSize + 1,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface),
        code: GoogleFonts.robotoMono(
          fontSize: fontSize - 1.5,
          backgroundColor: scheme.surfaceContainerHighest,
          color: scheme.onSurface,
        ),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outlineVariant),
        ),
        codeblockPadding: const EdgeInsets.all(9),
        blockquote: body.copyWith(color: scheme.onSurfaceVariant),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: scheme.outlineVariant, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 10),
        // Tighter than the defaults, which are tuned for a full-width document
        // rather than a side panel.
        pPadding: const EdgeInsets.only(bottom: 6),
        h1Padding: const EdgeInsets.only(top: 10, bottom: 3),
        h2Padding: const EdgeInsets.only(top: 10, bottom: 3),
        h3Padding: const EdgeInsets.only(top: 8, bottom: 2),
        listIndent: 18,
        tableBorder: TableBorder.all(color: scheme.outlineVariant, width: 1),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        tableBody: body.copyWith(fontSize: fontSize - 1),
        tableHead: body.copyWith(
            fontSize: fontSize - 1, fontWeight: FontWeight.w600),
      ),
    );
  }
}
