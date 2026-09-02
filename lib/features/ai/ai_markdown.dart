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

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/colors.dart';
import 'ai_markdown_blocks.dart';

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
    return MarkdownBody(
      data: data,
      selectable: selectable,
      onTapLink: (text, href, title) {
        if (href == null || href.isEmpty) return;
        final uri = Uri.tryParse(href);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      styleSheet: _styleSheetFor(Theme.of(context).colorScheme, fontSize),
    );
  }
}

/// The stylesheet, built once per (scheme, size) rather than per build.
///
/// It used to be constructed inline, which meant five GoogleFonts lookups and
/// a thirty-field object on every rebuild — and while an answer streams, that
/// is every frame. MarkdownStyleSheet implements ==, so a cached instance also
/// lets the widget comparison upstream short-circuit.
final _styleSheets = <(ColorScheme, double), MarkdownStyleSheet>{};

MarkdownStyleSheet _styleSheetFor(ColorScheme scheme, double fontSize) {
  final cached = _styleSheets[(scheme, fontSize)];
  if (cached != null) return cached;

  // Bounded, so switching theme repeatedly does not pin every ColorScheme the
  // app has ever built.
  if (_styleSheets.length > 4) _styleSheets.clear();

  final body = GoogleFonts.inter(
    fontSize: fontSize,
    height: 1.5,
    color: scheme.onSurface,
  );
  return _styleSheets[(scheme, fontSize)] = MarkdownStyleSheet(
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
    tableHead:
        body.copyWith(fontSize: fontSize - 1, fontWeight: FontWeight.w600),
  );
}

/// A model answer that is still arriving.
///
/// Rendering the growing string with [AiMarkdown] directly is what made a long
/// answer slow to a crawl and eventually take the app down with it. Two costs
/// compound, both paid per token and both proportional to the whole answer:
///
///  * `MarkdownBody` re-parses its entire `data` whenever the string changes —
///    a new `md.Document`, every line re-split, the whole AST rebuilt.
///  * Worse, `MarkdownBuilder` gives every block it emits a fresh `UniqueKey`.
///    Flutter cannot match those against the previous frame, so every
///    paragraph, heading, list item and table cell is *unmounted and
///    recreated* — element, State and RenderObject — on every parse. Nothing
///    is reused, no layout is cached.
///
/// Together that is O(n²) over the length of an answer, which is exactly the
/// reported shape: fine at first, slower as it goes, dead at the end.
///
/// The fix is to stop handing finished text back to the parser. Markdown above
/// the last blank line cannot be changed by anything appended after it, so it
/// is rendered once into a widget instance that is then held. Returning the
/// *same* instance makes `Element.updateChild` short-circuit on
/// `child.widget == newWidget`, so the settled part is not rebuilt at all — no
/// parse, no teardown — and only the last paragraph or two re-renders per
/// token.
class StreamingMarkdown extends StatefulWidget {
  const StreamingMarkdown(
    this.data, {
    super.key,
    this.done = false,
    this.fontSize = 13,
  });

  final String data;

  /// True once the run has finished. The whole answer is then rendered in one
  /// piece, so selection can span the split and the final layout is exact.
  final bool done;

  final double fontSize;

  @override
  State<StreamingMarkdown> createState() => _StreamingMarkdownState();
}

class _StreamingMarkdownState extends State<StreamingMarkdown> {
  /// The prefix already rendered into [_settledWidget].
  String _settledSrc = '';
  Widget? _settledWidget;

  @override
  Widget build(BuildContext context) {
    // Finished: one widget, so a selection can run across the whole answer and
    // the split leaves no trace in the layout.
    if (widget.done) {
      return AiMarkdown(widget.data, fontSize: widget.fontSize);
    }

    final cut = settlePoint(widget.data);

    // Keyed on the source, not its length. The web rescue in AiTasks clears
    // the answer and streams a different one, and a cache keyed on an offset
    // would happily reuse the old text under the new.
    if (cut > 0 && !widget.data.startsWith(_settledSrc)) {
      _settledSrc = '';
      _settledWidget = null;
    }

    if (cut > _settledSrc.length) {
      _settledSrc = widget.data.substring(0, cut);
      _settledWidget = AiMarkdown(
        _settledSrc,
        fontSize: widget.fontSize,
        // Not selectable while streaming: a SelectableText per block puts
        // dozens of gesture recognisers in the hit-test path of every scroll
        // event, and the finished answer above replaces this anyway.
        selectable: false,
      );
    }

    final tail = widget.data.substring(_settledSrc.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The identical instance every build — that is the whole mechanism.
        if (_settledWidget != null) _settledWidget!,
        if (tail.isNotEmpty)
          AiMarkdown(tail, fontSize: widget.fontSize, selectable: false),
      ],
    );
  }
}

/// Where [text] can be cut so that nothing before the cut can still change.
///
/// Public because it is the whole mechanism, and testing it through rendered
/// widgets can only observe that nothing crashed — not where the cut landed,
/// which is the part that has to be right.
///
/// A blank line ends a Markdown block, so anything above the last one is
/// settled — unless it is inside a fenced code block, where a blank line means
/// nothing and the fence could still be closed by text yet to arrive.
///
/// Returns 0 when there is no safe cut, in which case the caller re-renders
/// everything, exactly as before.
int settlePoint(String text) {
  var fenced = false;
  var cut = 0;
  var lineStart = 0;
  var previousBlank = false;

  for (var i = 0; i <= text.length; i++) {
    if (i < text.length && text[i] != '\n') continue;

    final line = text.substring(lineStart, i);
    final trimmed = line.trimLeft();

    // Three or more backticks or tildes opens or closes a fence. Counting the
    // run rather than matching '```' exactly keeps ````-fenced blocks and
    // inline triple backticks from flipping the state.
    if (_fenceRun(trimmed) >= 3) fenced = !fenced;

    if (!fenced && line.trim().isEmpty) {
      // A blank line outside a fence: everything up to and including it is
      // settled — but only if what follows does not depend on it.
      if (!previousBlank) {
        // Past the last newline there is no newline to step over, so the cut
        // is the end itself. Adding one there walks off the string.
        final candidate = i < text.length ? i + 1 : i;
        if (!_hasTrailingLinkDefinitions(text.substring(candidate))) {
          cut = candidate;
        }
      }
      previousBlank = true;
    } else if (line.trim().isNotEmpty) {
      previousBlank = false;
    }

    lineStart = i + 1;
  }
  return cut;
}

/// Length of the leading run of ` or ~, which is what opens a fence.
int _fenceRun(String trimmedLine) {
  if (trimmedLine.isEmpty) return 0;
  final marker = trimmedLine[0];
  if (marker != '`' && marker != '~') return 0;
  var n = 0;
  while (n < trimmedLine.length && trimmedLine[n] == marker) {
    n++;
  }
  return n;
}

/// Whether [tail] holds link reference definitions — `[1]: https://…`.
///
/// Those are collected from the whole document and resolve `[1]` references
/// anywhere in it, so cutting above them would strip the destinations off
/// every citation in the settled half and render them as literal brackets.
bool _hasTrailingLinkDefinitions(String tail) =>
    RegExp(r'^\[[^\]]+\]:', multiLine: true).hasMatch(tail);

/// One line of a model's prose, styled but not laid out.
///
/// [AiMarkdown] renders BLOCKS — it is a Column of paragraphs, lists and
/// headings, with the vertical rhythm that implies. That is right for an
/// answer and wrong for the places a model writes a single line into a row
/// that already has a shape: a quiz question beside its number, an option
/// beside its radio button, a line of marking feedback, a proofreader's
/// reason. Those were showing their Markdown raw — "What does `foo()`
/// return?" arriving with the backticks visible — but dropping a block
/// renderer into them would break the row.
///
/// So this renders inline emphasis ONLY, as spans, in whatever text style the
/// call site already had.
///
/// Links are styled but not tappable. Making them tappable means a
/// [TapGestureRecognizer] per span and a StatefulWidget to dispose them, and
/// none of these sites is somewhere a model cites a source — that is the
/// answer, which goes through [AiMarkdown] and does follow its links.
class AiInlineMarkdown extends StatelessWidget {
  const AiInlineMarkdown(this.data, {super.key, this.style});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final ops = marioInlineDelta(data).toList();

    // Nothing to style — skip the span machinery entirely. This is the common
    // case, since most lines carry no markdown at all.
    //
    // The text has to match as well as the attributes being absent: a line of
    // escapes (`\_not italic\_`) parses to one unstyled run whose text is
    // NOT the input, and handing back the raw string there would put the
    // backslashes on screen.
    //
    // Note `Delta.length` is the character count, not the operation count —
    // which is why this counts the operations itself.
    if (ops.length == 1 &&
        ops.first.attributes == null &&
        ops.first is afe.TextInsert &&
        (ops.first as afe.TextInsert).text == data) {
      return Text(data, style: base);
    }

    return Text.rich(
      TextSpan(
        children: [
          for (final op in ops)
            if (op is afe.TextInsert)
              TextSpan(
                text: op.text,
                style: _styleFor(op.attributes, base, Theme.of(context)),
              ),
        ],
      ),
      style: base,
    );
  }

  TextStyle _styleFor(
    Map<String, dynamic>? attrs,
    TextStyle base,
    ThemeData theme,
  ) {
    if (attrs == null || attrs.isEmpty) return base;
    var s = base;
    if (attrs['bold'] == true) s = s.copyWith(fontWeight: FontWeight.w600);
    if (attrs['italic'] == true) s = s.copyWith(fontStyle: FontStyle.italic);
    if (attrs['underline'] == true) {
      s = s.copyWith(decoration: TextDecoration.underline);
    }
    if (attrs['strikethrough'] == true) {
      s = s.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (attrs['code'] == true) {
      s = s.copyWith(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['ui-monospace', 'Menlo', 'Consolas'],
        backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.07),
      );
    }
    if (attrs['href'] is String) {
      s = s.copyWith(
        color: theme.colorScheme.secondary,
        decoration: TextDecoration.underline,
      );
    }
    return s;
  }
}
