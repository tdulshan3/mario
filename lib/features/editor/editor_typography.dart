/// How the page is set: the type, the line box, and the space around blocks.
///
/// The model is VS Code's Markdown preview — 14px text on a 22px line, a
/// heading with a band of air above and below it, a rule under a level-1
/// heading, a 2px horizontal rule, GitHub's `:smile:` shortcodes — because that
/// is the rendering people already know a Markdown document by.
///
/// The one idea that matters for a notes app: **a block is a line.** Enter
/// makes a new block, so a page written the way notes are written — one
/// thought per line, a list item per line — is a stack of one-line blocks. If
/// each block carries its own vertical padding, that stack reads as text set
/// with enormous leading, while a paragraph that happens to wrap reads
/// normally. It used to: AppFlowy pads EVERY block by `editorStyle.padding`,
/// and 8px of vertical padding there put 16px between each line and the next
/// — the "line height is too much" that a user sees, though no line height
/// was involved.
///
/// So blocks carry no padding at all, and the line box does the work: the
/// text style applies its height to the first line's ascent and the last
/// line's descent, which makes a one-line block exactly one line tall. Lines
/// inside a block and lines across blocks then sit on the same 22px pitch, and
/// a blank block is a paragraph break. Headings and dividers are the only
/// blocks that claim space of their own, because they are the only things a
/// Markdown preview spaces differently from body text.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md show emojis;

import '../../ui/theme.dart';

/// Body size and line box. 14px over 22px is what VS Code's preview renders.
const double kEditorFontSize = 14;
const double kEditorLineHeight = 22 / 14;

/// Air above and below a heading. The browser defaults VS Code's preview
/// inherits give h1–h3 margins of 0.67em–1em of their own size, which all
/// come to 17–19px at a 14px base; one value keeps the rhythm even.
const double kHeadingSpaceAbove = 18;
const double kHeadingSpaceBelow = 18;

/// Air above the first and below the last item of a list, or line of a
/// quote. A preview sets a list off from the prose around it (a 1em margin
/// on the `ul`, collapsing with the paragraph's) while the items inside sit
/// a line apart; here the items are blocks, so the run is found from the
/// neighbours. Half a preview's margin, because the lines either side of it
/// are set flush and a full one would float the list off its own lead-in.
const double kRunSpace = 8;

/// Heading sizes: the browser defaults — 2em, 1.5em, 1.17em, 1em — for the
/// four levels anyone writes. Levels 5 and 6 would be .83em and .67em, which
/// is smaller than the body text; they are held at body size instead.
double headingFontSize(int level) => switch (level) {
      1 => 28,
      2 => 21,
      3 => 16.5,
      _ => kEditorFontSize,
    };

/// A heading's text style, merged over the body style the block inherits —
/// so it names no face and no colour, and takes both from the body.
///
/// Weight stays semi-bold. VS Code's preview sets h1–h3 in the regular weight
/// and lets size alone do the work; in a page people write into, a heading
/// that is only bigger is easy to mistake for a large paragraph.
TextStyle editorHeadingStyle(int level) => TextStyle(
      fontSize: headingFontSize(level),
      fontWeight: FontWeight.w600,
      height: 1.25,
    );

/// The vertical space a block claims for itself.
///
/// Zero for a line of text — see the library comment. A heading takes its
/// band above (the band below is drawn by [editorHeadingWrapper], so that a
/// level-1 rule can sit between the text and the space). A list item or a
/// quote line takes [kRunSpace] where its run starts and ends. A divider
/// takes the margin a preview gives an `<hr>`, which with the paragraph
/// margins around it collapses to about a line's worth either side.
///
/// Neighbours are read at build time. Turning a block into a list item, or
/// adding one, is a structural change in AppFlowy — the old node goes and a
/// new one is inserted — which rebuilds the page and every block on it, so
/// a run's edges are recomputed whenever a run changes.
EdgeInsets editorBlockPadding(afe.Node node) {
  switch (node.type) {
    case afe.HeadingBlockKeys.type:
      // The first block sits under the page title, which already holds it
      // off; a band on top of that pushed the first heading a full line down.
      return EdgeInsets.only(
          top: _isFirstOnPage(node) ? 0 : kHeadingSpaceAbove);
    case afe.BulletedListBlockKeys.type:
    case afe.NumberedListBlockKeys.type:
    case afe.TodoListBlockKeys.type:
    case afe.QuoteBlockKeys.type:
      // Top-level runs only. A nested list lives inside its parent item and
      // is spaced by that item's own run.
      if (node.parent?.type != afe.PageBlockKeys.type) return EdgeInsets.zero;
      final startsRun = node.previous?.type != node.type;
      final endsRun = node.next?.type != node.type;
      return EdgeInsets.only(
        top: startsRun && !_isFirstOnPage(node) ? kRunSpace : 0,
        bottom: endsRun ? kRunSpace : 0,
      );
    case afe.DividerBlockKeys.type:
      return const EdgeInsets.symmetric(vertical: 9);
    default:
      return EdgeInsets.zero;
  }
}

bool _isFirstOnPage(afe.Node node) =>
    node.parent?.type == afe.PageBlockKeys.type && node.previous == null;

/// The block configuration every standard block shares.
///
/// Placeholder text is left at the package default (a blank), which is what
/// the editor has always shown; only the padding is the point here.
final afe.BlockComponentConfiguration editorBlockConfiguration =
    afe.BlockComponentConfiguration(padding: editorBlockPadding);

/// Draws around a heading: the space below it, and for level 1 the rule a
/// Markdown preview puts under the document's top heading. The rule sits
/// 0.3em under the text and the space comes after it, as in VS Code's
/// stylesheet, so the line belongs to the heading rather than floating
/// between it and the paragraph.
Widget editorHeadingWrapper(BuildContext context, afe.Node node, Widget child) {
  final level = node.attributes[afe.HeadingBlockKeys.level] as int? ?? 1;
  if (level != 1) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kHeadingSpaceBelow),
      child: child,
    );
  }
  return Container(
    margin: const EdgeInsets.only(bottom: kHeadingSpaceBelow),
    padding: EdgeInsets.only(bottom: headingFontSize(1) * 0.3),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: markdownRuleColor(Theme.of(context).colorScheme),
        ),
      ),
    ),
    child: child,
  );
}

/// The text styles every text block is set in.
///
/// [ink] is the body colour for the current ground. Height is applied to the
/// first ascent and last descent as well as between lines, so a one-line
/// block is one full line tall — the whole reason blocks can go unpadded.
afe.TextStyleConfiguration editorTextStyles(
  BuildContext context, {
  required Color ink,
}) {
  final t = marioTokens(context);
  final scheme = Theme.of(context).colorScheme;
  return afe.TextStyleConfiguration(
    text: GoogleFonts.inter(
      fontSize: kEditorFontSize,
      height: kEditorLineHeight,
      color: ink,
    ),
    lineHeight: kEditorLineHeight,
    applyHeightToFirstAscent: true,
    applyHeightToLastDescent: true,
    // Inline code the way a preview sets it: the code block's own face, a
    // touch smaller than the prose, on a quiet fill. The package default is
    // red on cyan.
    code: GoogleFonts.jetBrainsMono(
      fontSize: 13,
      color: ink,
      backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
    ),
    // The accent's text tone — the one accent colour that may carry a word.
    href: TextStyle(
      color: t.accentText,
      decoration: TextDecoration.underline,
      decorationColor: t.accentText.withValues(alpha: 0.5),
    ),
  );
}

/// The heading and divider builders, styled.
///
/// Returned as a map so the caller can spread it over the standard set: the
/// two are the standard builders with a text style, a wrapper and a line
/// colour handed in, nothing more.
Map<String, afe.BlockComponentBuilder> editorTypographyBuilders(
    BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return {
    afe.HeadingBlockKeys.type: afe.HeadingBlockComponentBuilder(
      configuration: editorBlockConfiguration,
      textStyleBuilder: editorHeadingStyle,
      wrapper: editorHeadingWrapper,
    ),
    // A preview's `<hr>`: 2px, in the rule tone, with the margin an hr gets
    // — this height, centred on the line, plus the block padding above.
    afe.DividerBlockKeys.type: afe.DividerBlockComponentBuilder(
      configuration: editorBlockConfiguration,
      lineColor: markdownRuleColor(scheme),
      thickness: 2,
      height: 12,
    ),
  };
}

/// `:smile:` → 😄 as it is typed, the way GitHub reads it.
///
/// Fires on the closing colon. Nothing happens unless the text before the
/// caret ends in `:alias` for an alias the `markdown` package knows — the
/// same table the AI panel and the Markdown importer already use, so a
/// shortcode that renders in an answer also converts under the keys. A time
/// like 10:30, a URL scheme, an emoticon, or a colon after a word are all
/// left alone and the colon goes in as typed.
final afe.CharacterShortcutEvent marioEmojiShortcut =
    afe.CharacterShortcutEvent(
  key: 'convert an emoji shortcode to its emoji',
  character: ':',
  handler: convertEmojiShortcode,
);

/// The shortcut's work, callable without a keystroke. Returns false when there
/// was nothing to convert, which tells the editor to insert the colon.
Future<bool> convertEmojiShortcode(afe.EditorState editorState) async {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) return false;

  final node = editorState.getNodeAtPath(selection.end.path);
  final delta = node?.delta;
  if (node == null || delta == null) return false;

  final offset = selection.end.offset;
  final text = delta.toPlainText();
  if (offset > text.length) return false;

  final match = _shortcode.firstMatch(text.substring(0, offset));
  if (match == null) return false;
  final emoji = md.emojis[match.group(1)!];
  if (emoji == null) return false;

  final transaction = editorState.transaction
    ..replaceText(node, match.start, offset - match.start, emoji);
  await editorState.apply(transaction);
  return true;
}

/// GitHub's alias alphabet — lower-case, digits, underscore, and the `+1` /
/// `-1` pair — anchored to the caret.
final RegExp _shortcode = RegExp(r':([a-z0-9_+-]+)$');
