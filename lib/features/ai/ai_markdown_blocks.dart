/// Markdown → document, without losing the code.
///
/// AppFlowy's markdown decoder ships parsers for headings, quotes, lists,
/// tables, images and dividers — and none for a fenced code block. Anything
/// between ``` fences is therefore parsed into an element nobody claims, and
/// silently DROPPED. That matters here because model answers are full of code:
/// "Insert into page" on an answer explaining a function quietly wrote the
/// prose and threw the function away.
///
/// [marioMarkdownParsers] adds the missing one, mapping a fence onto the app's
/// own code block (`code_block.dart`) so an inserted snippet arrives
/// syntax-highlighted and with its language already selected, rather than as a
/// paragraph of grey text.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:markdown/markdown.dart' as md;

import '../editor/blocks/code_block.dart';

/// A fenced code block — ```lang … ``` — as the app's code block.
///
/// The `markdown` package emits `<pre><code class="language-dart">`, so the
/// language rides on the class of the inner `code` element. An indented code
/// block (four spaces) produces the same shape with no class, and lands as
/// plaintext.
class MarioCodeBlockParser extends afe.CustomMarkdownParser {
  const MarioCodeBlockParser();

  @override
  List<afe.Node> transform(
    md.Node element,
    List<afe.CustomMarkdownParser> parsers, {
    afe.MarkdownListType listType = afe.MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element || element.tag != 'pre') return [];

    // <pre> wraps a single <code>; anything else is not a fence.
    final children = element.children;
    if (children == null || children.isEmpty) return [];
    final code = children.first;
    if (code is! md.Element || code.tag != 'code') return [];

    final language = _languageOf(code);

    // textContent unescapes entities, which matters: a fence containing `<`
    // or `&` arrives as `&lt;` / `&amp;` in the element tree, and writing that
    // into the page would show the entity rather than the character.
    var text = code.textContent;
    // The parser keeps the newline that closed the fence; the editor adds its
    // own trailing line, so keeping it leaves a blank last row.
    if (text.endsWith('\n')) text = text.substring(0, text.length - 1);

    return [codeBlockNode(code: text, language: language)];
  }

  String _languageOf(md.Element code) {
    final classes = code.attributes['class'];
    if (classes == null) return 'plaintext';
    for (final c in classes.split(RegExp(r'\s+'))) {
      if (c.startsWith('language-')) {
        final lang = c.substring('language-'.length).trim();
        if (lang.isNotEmpty) return lang.toLowerCase();
      }
    }
    return 'plaintext';
  }
}

/// The decoder set the app uses everywhere it turns model output into blocks.
///
/// AppFlowy's own defaults are appended by `markdownToDocument`; this only has
/// to carry what it is missing.
const List<afe.CustomMarkdownParser> marioMarkdownParsers = [
  MarioCodeBlockParser(),
];

/// Markdown → detached nodes, ready to insert.
///
/// `copyWith` detaches each node from the parsed document's root. Inserting a
/// node that still has a parent leaves it in two trees at once, and its `path`
/// then resolves against the wrong one.
List<afe.Node> marioMarkdownToNodes(String markdown) {
  final parsed = afe.markdownToDocument(
    markdown,
    markdownParsers: marioMarkdownParsers,
  );
  return [for (final n in parsed.root.children) n.copyWith()];
}

/// Inline markdown — `**bold**`, `` `code` ``, `[a](b)` — as a styled delta.
///
/// What the agent needs. It writes one line at a time into a node it has
/// already chosen (a paragraph, a heading, a list item), so it wants the
/// STYLING off the markdown without the block structure.
///
/// Deliberately conservative. Multi-line text is returned verbatim, because
/// taking the first parsed block of a multi-block string would silently drop
/// everything after it — and text that survives as visible `**` is a cosmetic
/// problem, where text that vanishes is a data-loss one.
afe.Delta marioInlineDelta(String text) {
  if (text.isEmpty || text.contains('\n')) {
    return afe.Delta()..insert(text);
  }

  final afe.Document parsed;
  try {
    parsed =
        afe.markdownToDocument(text, markdownParsers: marioMarkdownParsers);
  } catch (_) {
    // A malformed fragment must not take the whole plan down.
    return afe.Delta()..insert(text);
  }

  final children = parsed.root.children;
  if (children.length != 1) return afe.Delta()..insert(text);

  final delta = children.first.delta;
  if (delta == null || delta.isEmpty) return afe.Delta()..insert(text);

  // The parse has to account for every character that was not syntax. If it
  // does not, something was dropped and the literal text is the safer answer.
  if (delta.toPlainText().trim().isEmpty && text.trim().isNotEmpty) {
    return afe.Delta()..insert(text);
  }

  return delta;
}
