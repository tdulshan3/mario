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
import '../editor/blocks/math_block.dart';
import '../math/latex_normalizer.dart';

/// A fenced code block — ```lang … ``` — as the app's code block, or, when
/// the fence is a maths one, as the app's formula block.
///
/// The `markdown` package emits `<pre><code class="language-dart">`, so the
/// language rides on the class of the inner `code` element. An indented code
/// block (four spaces) produces the same shape with no class, and lands as
/// plaintext. A ```math, ```latex or ```tex fence — and a `$$` block, which
/// [displayMathAsFences] turns into one — becomes a formula block, rendered
/// rather than shown as LaTeX source.
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

    if (_mathLanguages.contains(language)) {
      final formula = normalizeLatexFormula(text);
      if (formula.isNotEmpty) return [mathEquationNode(formula: formula)];
    }
    return [codeBlockNode(code: text, language: language)];
  }

  static const _mathLanguages = {'math', 'latex', 'tex', 'katex'};

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

/// A GitHub callout — `> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`,
/// `[!CAUTION]` — as a quote block with the callout's title in bold.
///
/// The `markdown` package's GitHub set parses these into
/// `<div class="markdown-alert markdown-alert-tip">` with a title paragraph
/// first, which no AppFlowy parser claims, so a study note full of tips lost
/// every one of them on the way in. Mario has no callout block of its own;
/// a quote with a bold first line is what the same note looks like in a
/// preview, minus the colour.
class MarioAlertParser extends afe.CustomMarkdownParser {
  const MarioAlertParser();

  @override
  List<afe.Node> transform(
    md.Node element,
    List<afe.CustomMarkdownParser> parsers, {
    afe.MarkdownListType listType = afe.MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element || element.tag != 'div') return [];
    final classes = element.attributes['class'] ?? '';
    if (!classes.contains('markdown-alert')) return [];

    final delta = afe.Delta();
    final decoder = afe.DeltaMarkdownDecoder();
    var first = true;
    for (final child in element.children ?? const <md.Node>[]) {
      if (child is! md.Element) continue;
      if (child.attributes['class'] == 'markdown-alert-title') {
        delta.insert(child.textContent.trim(), attributes: {'bold': true});
        first = false;
        continue;
      }
      if (!first) delta.insert('\n');
      first = false;
      // A paragraph keeps its inline styling; anything else — a list, a
      // fence — is kept as text rather than lost.
      if (child.tag == 'p' && child.children != null) {
        final inner = decoder.convertNodes(child.children!);
        for (final op in inner) {
          if (op is afe.TextInsert) {
            delta.insert(op.text, attributes: op.attributes);
          }
        }
      } else {
        delta.insert(child.textContent.trim());
      }
    }
    if (delta.isEmpty) return [];
    return [afe.quoteNode(delta: delta)];
  }
}

/// The decoder set the app uses everywhere it turns model output into blocks.
///
/// AppFlowy's own defaults are appended by `markdownToDocument`; this only has
/// to carry what it is missing.
const List<afe.CustomMarkdownParser> marioMarkdownParsers = [
  MarioCodeBlockParser(),
  MarioAlertParser(),
];

/// Markdown → detached nodes, ready to insert.
///
/// `copyWith` detaches each node from the parsed document's root. Inserting a
/// node that still has a parent leaves it in two trees at once, and its `path`
/// then resolves against the wrong one.
List<afe.Node> marioMarkdownToNodes(String markdown) {
  final parsed = afe.markdownToDocument(
    displayMathAsFences(markdown),
    markdownParsers: marioMarkdownParsers,
  );
  return [for (final n in parsed.root.children) n.copyWith()];
}

/// `$$ … $$` display maths as ```math fences, so the fence parser sees it.
///
/// The `markdown` package knows no maths syntax, so a `$$` block would land
/// as a paragraph of LaTeX source — which is what models and Markdown editors
/// write for a formula, and what the maths block renders. Only blocks whose
/// delimiters sit on lines of their own are converted; `$x$` inline and a
/// `$$` inside a code fence are left exactly as they are.
String displayMathAsFences(String markdown) {
  if (!markdown.contains(r'$$')) return markdown;
  final out = StringBuffer();
  final lines = markdown.split('\n');
  var inFence = false;
  var inMath = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (!inMath && _fenceRun(trimmed) >= 3) {
      inFence = !inFence;
      out.writeln(line);
      continue;
    }
    if (inFence) {
      out.writeln(line);
      continue;
    }
    if (trimmed == r'$$') {
      out.writeln(inMath ? '```' : '```math');
      inMath = !inMath;
      continue;
    }
    // A one-line block: `$$ E = mc^2 $$`.
    if (!inMath &&
        trimmed.length > 4 &&
        trimmed.startsWith(r'$$') &&
        trimmed.endsWith(r'$$')) {
      out.writeln('```math');
      out.writeln(trimmed.substring(2, trimmed.length - 2).trim());
      out.writeln('```');
      continue;
    }
    out.writeln(line);
  }
  var result = out.toString();
  // writeln adds a newline the input may not have had.
  if (!markdown.endsWith('\n') && result.endsWith('\n')) {
    result = result.substring(0, result.length - 1);
  }
  // An unclosed `$$` is not a formula; put the source back as it was.
  return inMath ? markdown : result;
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
