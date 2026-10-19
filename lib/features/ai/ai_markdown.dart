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

import 'package:apple_ui/apple_ui.dart' show MacColors;
import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../ui/colors.dart';
import '../../ui/mac/mac_look.dart';
import '../../ui/theme.dart';
import 'ai_markdown_blocks.dart';

/// A model answer, rendered.
///
/// Laid out the way VS Code's Markdown preview lays out a document, scaled to
/// the panel's type size — see [_renderingFor] for the measurements. Two
/// things it adds to flutter_markdown's defaults: GitHub's `:smile:`
/// shortcodes, and builders for the two elements the stylesheet cannot draw
/// as a preview does, the rule under a level-1 heading and the horizontal rule
/// itself.
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
    final rendering =
        _renderingFor(Theme.of(context).colorScheme, fontSize, selectable);
    return MarkdownBody(
      data: data,
      selectable: selectable,
      inlineSyntaxes: _inlineSyntaxes,
      builders: rendering.builders,
      onTapLink: (text, href, title) {
        if (href == null || href.isEmpty) return;
        final uri = Uri.tryParse(href);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      styleSheet: rendering.styleSheet,
    );
  }
}

/// `:smile:` and friends. flutter_markdown parses with the GitHub-flavoured
/// set, which has tables, strikethrough and task lists but not the shortcodes
/// GitHub's own renderer adds on top; this is that one addition. One instance
/// for the app — the syntax compiles a pattern — handed to every body.
final List<md.InlineSyntax> _inlineSyntaxes = [md.EmojiSyntax()];

/// A stylesheet and the element builders that go with it.
class _Rendering {
  const _Rendering(this.styleSheet, this.builders);

  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
}

/// Built once per (scheme, size, selectable) rather than per build.
///
/// It used to be constructed inline, which meant five GoogleFonts lookups and
/// a thirty-field object on every rebuild — and while an answer streams, that
/// is every frame. MarkdownStyleSheet implements ==, so a cached instance also
/// lets the widget comparison upstream short-circuit.
final _renderings = <(ColorScheme, double, bool, bool), _Rendering>{};

/// VS Code's preview, in the panel's size.
///
/// The preview sets 14px text on a 22px line, gives paragraphs a 1em margin,
/// gives list items none, sets headings at the browser's 2em / 1.5em / 1.17em
/// with 17–19px of margin, rules the h1, draws the hr 2px, and gives a
/// blockquote a 5px accent bar on a faint fill. Margins collapse in CSS and
/// paddings do not here, so each value below is the half that adds up to the
/// same gap: paragraph 0.4em top and bottom, heading 0.6em, and a 0.2em floor
/// between any two blocks that would otherwise touch. The floor is what
/// separates list items — the one place the preview has none — so a list
/// is set almost as tight as a paragraph rather than a line apart.
_Rendering _renderingFor(ColorScheme scheme, double f, bool selectable) {
  // The look is part of the key: the same scheme renders links differently
  // on the desktop.
  final mac = useMacLook;
  final cached = _renderings[(scheme, f, selectable, mac)];
  if (cached != null) return cached;

  // Bounded, so switching theme repeatedly does not pin every ColorScheme the
  // app has ever built.
  if (_renderings.length > 8) _renderings.clear();

  final ink = scheme.onSurface;
  final rule = markdownRuleColor(scheme);
  final body = GoogleFonts.inter(fontSize: f, height: 1.5, color: ink);
  // The desktop's links are the system accent, not Mario's gold — the macOS
  // theme puts that accent in `primary`. Its code blocks sit on the kit's
  // tertiary fill rather than the sidebar grey `surfaceContainerHighest`
  // carries there.
  final linkColor = mac ? scheme.primary : MarioColors.primaryPressed;
  final macColors =
      scheme.brightness == Brightness.dark ? MacColors.dark : MacColors.light;
  final codeFill =
      mac ? macColors.fillTertiary : scheme.surfaceContainerHighest;
  final link = body.copyWith(
    color: linkColor,
    decoration: TextDecoration.underline,
    decorationColor: linkColor.withValues(alpha: 0.4),
  );
  // Inline code: the code block's face, a step smaller than the prose, on a
  // quiet fill.
  final code = GoogleFonts.jetBrainsMono(
    fontSize: f - 1,
    color: ink,
    backgroundColor: ink.withValues(alpha: 0.08),
  );
  TextStyle heading(double scale, {Color? color}) => GoogleFonts.inter(
        fontSize: f * scale,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: color ?? ink,
      );
  final headingPadding = EdgeInsets.symmetric(vertical: f * 0.6);

  final sheet = MarkdownStyleSheet(
    p: body,
    pPadding: EdgeInsets.symmetric(vertical: f * 0.4),
    blockSpacing: f * 0.2,
    listBullet: body,
    listIndent: f * 1.6,
    a: link,
    strong: body.copyWith(fontWeight: FontWeight.w600),
    em: body.copyWith(fontStyle: FontStyle.italic),
    del: body.copyWith(decoration: TextDecoration.lineThrough),
    // The browser's own scale, which is what the preview inherits. Levels 5
    // and 6 would come out smaller than the text; they stay at body size and
    // the last goes quiet instead.
    h1: heading(2),
    h2: heading(1.5),
    h3: heading(1.17),
    h4: heading(1),
    h5: heading(1),
    h6: heading(1, color: scheme.onSurfaceVariant),
    h1Padding: headingPadding,
    h2Padding: headingPadding,
    h3Padding: headingPadding,
    h4Padding: headingPadding,
    h5Padding: headingPadding,
    h6Padding: headingPadding,
    code: code,
    codeblockDecoration: BoxDecoration(
      color: codeFill,
      borderRadius: BorderRadius.circular(3),
    ),
    codeblockPadding: EdgeInsets.all(f * 0.9),
    blockquote: body,
    blockquoteDecoration: BoxDecoration(
      color: ink.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(2),
      border: Border(
        left:
            BorderSide(color: scheme.primary.withValues(alpha: 0.55), width: 4),
      ),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(10, 2, 12, 2),
    // Rows separated by rules, the head from the body by one, and no vertical
    // lines — a preview's table, not a spreadsheet's grid.
    tableBorder: TableBorder(
      horizontalInside: BorderSide(color: rule),
      bottom: BorderSide(color: rule),
    ),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    tableBody: body.copyWith(fontSize: f - 1),
    tableHead: body.copyWith(fontSize: f - 1, fontWeight: FontWeight.w600),
    horizontalRuleDecoration: _horizontalRule(rule, margin: f * 0.4),
  );

  final builders = <String, MarkdownElementBuilder>{
    'h1': _RuledHeadingBuilder(
      style: sheet.h1!,
      padding: headingPadding,
      ruleColor: rule,
      codeStyle: code,
      linkColor: linkColor,
      selectable: selectable,
    ),
  };

  return _renderings[(scheme, f, selectable, mac)] =
      _Rendering(sheet, builders);
}

/// A level-1 heading with the preview's rule under it.
///
/// flutter_markdown has no decoration slot for a heading, and a builder
/// replaces the element's rendering wholesale — including the inline runs the
/// package would have styled — so the heading's children are set here too:
/// bold, italic, code, strikethrough and link, which is everything a heading
/// carries. The rule sits 0.3em below the text and the heading's own margin
/// comes after it, as in VS Code's stylesheet.
class _RuledHeadingBuilder extends MarkdownElementBuilder {
  _RuledHeadingBuilder({
    required this.style,
    required this.padding,
    required this.ruleColor,
    required this.codeStyle,
    required this.linkColor,
    required this.selectable,
  });

  final TextStyle style;
  final EdgeInsets padding;
  final Color ruleColor;
  final TextStyle codeStyle;
  final Color linkColor;
  final bool selectable;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final span = TextSpan(
      style: style,
      children: [
        for (final child in element.children ?? const <md.Node>[])
          _spanFor(child, style),
      ],
    );
    return Padding(
      padding: padding,
      child: Container(
        key: const ValueKey('ai-markdown-h1-rule'),
        padding: EdgeInsets.only(bottom: (style.fontSize ?? 13) * 0.3),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ruleColor)),
        ),
        child: selectable ? SelectableText.rich(span) : Text.rich(span),
      ),
    );
  }

  InlineSpan _spanFor(md.Node node, TextStyle inherited) {
    if (node is md.Text) return TextSpan(text: node.text, style: inherited);
    if (node is! md.Element) return const TextSpan();
    if (node.tag == 'br') return const TextSpan(text: '\n');
    // Overlays, not the stylesheet's full styles: those carry the body size,
    // and merging one in would shrink the heading to a paragraph.
    final overlay = switch (node.tag) {
      'strong' => const TextStyle(fontWeight: FontWeight.w700),
      'em' => const TextStyle(fontStyle: FontStyle.italic),
      'del' => const TextStyle(decoration: TextDecoration.lineThrough),
      'code' => TextStyle(
          fontFamily: codeStyle.fontFamily,
          fontFamilyFallback: codeStyle.fontFamilyFallback,
          backgroundColor: codeStyle.backgroundColor,
        ),
      'a' => TextStyle(color: linkColor, decoration: TextDecoration.underline),
      _ => const TextStyle(),
    };
    final style = inherited.merge(overlay);
    return TextSpan(
      style: style,
      children: [
        for (final child in node.children ?? const <md.Node>[])
          _spanFor(child, style),
      ],
    );
  }
}

/// `---`, drawn as the preview draws it: a 2px rule with [margin] either side.
///
/// flutter_markdown gives an `hr` a bare `Container(decoration: …)` — no
/// child, no height, and no way in for a builder, which it consults and then
/// overrides for this tag. Such a box is exactly as tall as its border, so
/// the margin is a transparent border top and bottom, and the rule is the
/// box's own fill: a gradient that is clear except for the two pixels in the
/// middle. The default decoration was a 5px slab on the top edge of nothing.
BoxDecoration _horizontalRule(Color color, {required double margin}) {
  const thickness = 2.0;
  final total = margin * 2 + thickness;
  final from = margin / total;
  final to = (margin + thickness) / total;
  const clear = Color(0x00000000);
  return BoxDecoration(
    border: Border(
      top: BorderSide(width: margin, color: clear),
      bottom: BorderSide(width: margin, color: clear),
    ),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [clear, clear, color, color, clear, clear],
      stops: [0, from, from, to, to, 1],
    ),
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
        // The accent on the desktop, like the answer's own links.
        color: useMacLook
            ? theme.colorScheme.primary
            : theme.colorScheme.secondary,
        decoration: TextDecoration.underline,
      );
    }
    return s;
  }
}
