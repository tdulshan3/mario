/// Turning a page into text a model can read.
///
/// The obvious approach — reuse `documentToMarkdown` from the exporter — is
/// wrong here, and quietly so. That encoder only understands AppFlowy's stock
/// blocks, so every Mario block it has never heard of comes out empty: the
/// LaTeX in a math block, the body of a code block, the lines OCR'd out of a
/// photographed slide, the transcript of a recorded lecture. Those are not
/// incidental decorations in a study app, they are the notes. A quiz generated
/// from a page whose formulas were silently dropped is a quiz about the prose
/// between the formulas.
///
/// So extraction walks the document itself and reads each block's own
/// attributes:
///
///   math_equation -> `formula`      (as LaTeX, fenced so it survives)
///   code          -> `code` + `language`
///   image         -> `ocr_lines`    (text detected in the picture)
///   audio_clip    -> `transcript`   (what was said)
///   spreadsheet   -> `workbook`     (rendered as rows)
///   drawing       -> nothing readable; noted as a placeholder so the model
///                    knows something is there rather than inferring a gap
///
/// Every extracted block keeps its node id and path, which is what lets a
/// summary sentence, a quiz question or a citation point back at the exact
/// block it came from.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;

import '../editor/blocks/audio_block.dart';
import '../editor/blocks/code_block.dart';
import '../editor/blocks/drawing_block.dart';
import '../editor/blocks/math_block.dart';
import '../editor/blocks/mario_image_block.dart';
import '../editor/blocks/spreadsheet_block.dart';
import '../../core/services/ai/json_coercion.dart';

/// One readable block of a note.
class NoteBlock {
  const NoteBlock({
    required this.nodeId,
    required this.path,
    required this.type,
    required this.text,
    this.headingLevel,
  });

  /// AppFlowy node id.
  ///
  /// Session-scoped only. `Node.id` is minted as `nanoid(6)` in the
  /// constructor and is NOT serialised — `toJson` writes just (type, data),
  /// `fromJson` never reads an id back, and `copyWith` mints a fresh one. So
  /// this identifies a block reliably while the page stays open, which is all
  /// the proofreader needs (check and apply happen in one session), but it is
  /// meaningless after a reload. Anything persisted must re-anchor by content
  /// — which is why a saved suggestion also carries its exact `before` text.
  final String nodeId;

  /// Position in the document tree, used to order and slice.
  final List<int> path;

  /// AppFlowy block type ('paragraph', 'heading', 'code', 'math_equation'…).
  final String type;

  /// The block rendered as text for the model.
  final String text;

  /// 1-6 for headings, null otherwise. Drives section-aware chunking.
  final int? headingLevel;

  bool get isHeading => headingLevel != null;
  bool get isEmpty => text.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'path': path,
        'type': type,
        'text': text,
        if (headingLevel != null) 'headingLevel': headingLevel,
      };
}

/// A whole page, read.
class NoteText {
  const NoteText({required this.title, required this.blocks});

  final String title;
  final List<NoteBlock> blocks;

  bool get isEmpty => blocks.every((b) => b.isEmpty);

  /// Rough token estimate, scaled by the script the note is actually written in.
  ///
  /// The usual "four characters to a token" rule is an English rule. For
  /// Sinhala, Tamil, Devanagari, Arabic or CJK the real ratio is closer to one
  /// or one-and-a-half, so a flat /4 under-counts a non-Latin note by three to
  /// four times. That is not a rounding error, it is a silent truncation: the
  /// budget check decides the note fits, the server quietly drops the overflow
  /// (llama-server truncates rather than erroring), and the model summarises
  /// the tail of a page while appearing to have read all of it.
  int get approxTokens => estimateTokens(render());

  int get characters =>
      blocks.fold(0, (sum, b) => sum + b.text.length + 1);

  String render() {
    final buf = StringBuffer();
    if (title.trim().isNotEmpty) buf.writeln('# $title\n');
    for (final b in blocks) {
      if (b.isEmpty) continue;
      buf.writeln(b.text);
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  /// The blocks above [path] in document order — what `/summary` means by
  /// "the note above this point".
  NoteText above(List<int> path) => NoteText(
        title: title,
        blocks: [
          for (final b in blocks)
            if (_comparePaths(b.path, path) < 0) b,
        ],
      );

  /// Truncates to a *token* budget, keeping the opening of the note.
  ///
  /// Notes are written top-down, so the beginning carries the definitions and
  /// framing a later paragraph depends on. Dropping the tail loses detail;
  /// dropping the head loses the thread.
  ///
  /// Measured in tokens rather than characters so the limit means the same
  /// thing in every script — see [approxTokens].
  NoteText limitToTokens(int maxTokens) {
    if (approxTokens <= maxTokens) return this;
    final kept = <NoteBlock>[];
    var used = 0;
    for (final b in blocks) {
      final cost = estimateTokens(b.text) + 1;
      if (used + cost > maxTokens) break;
      kept.add(b);
      used += cost;
    }
    return NoteText(title: title, blocks: kept);
  }
}

/// Token estimate for [text], scaled by its dominant script.
///
/// Deliberately crude — the job is to decide what fits, not to bill anyone —
/// but crude in the *safe* direction for every script rather than only for
/// English. Ratios are the widely-observed byte-pair behaviour of current
/// tokenizers: Latin prose runs about four characters to a token, Indic,
/// Arabic, Hebrew and Thai text about one and a half, and CJK about one.
///
/// Sampling rather than scanning the whole string keeps this cheap enough to
/// call on every block; a note does not change script halfway through often
/// enough to matter, and mixed text lands between the two ratios anyway.
int estimateTokens(String text) {
  if (text.isEmpty) return 0;

  const sampleLimit = 2000;
  final sample =
      text.length <= sampleLimit ? text : text.substring(0, sampleLimit);

  var wide = 0; // CJK — roughly one token per character
  var dense = 0; // Indic / Arabic / Hebrew / Thai — roughly 1.5
  var counted = 0;

  for (final rune in sample.runes) {
    if (rune <= 0x7F) continue; // ASCII: the common case, already covered by /4
    counted++;
    if (_isWideScript(rune)) {
      wide++;
    } else if (_isDenseScript(rune)) {
      dense++;
    }
  }

  if (counted == 0) return (text.length / 4).ceil();

  // Which non-ASCII script dominates decides the divisor. A note with a couple
  // of accented characters stays on the Latin ratio.
  final nonAsciiShare = counted / sample.runes.length;
  if (nonAsciiShare < 0.15) return (text.length / 4).ceil();

  final divisor = wide >= dense ? 1.0 : 1.5;
  return (text.length / divisor).ceil();
}

/// Han, Hiragana, Katakana, Hangul — about one token per character.
bool _isWideScript(int rune) =>
    (rune >= 0x3040 && rune <= 0x30FF) || // kana
    (rune >= 0x3400 && rune <= 0x4DBF) || // CJK ext A
    (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK unified
    (rune >= 0xAC00 && rune <= 0xD7AF) || // Hangul syllables
    (rune >= 0xF900 && rune <= 0xFAFF);

/// Indic scripts, Arabic, Hebrew, Thai — about 1.5 characters per token.
bool _isDenseScript(int rune) =>
    (rune >= 0x0590 && rune <= 0x05FF) || // Hebrew
    (rune >= 0x0600 && rune <= 0x06FF) || // Arabic
    (rune >= 0x0900 && rune <= 0x097F) || // Devanagari
    (rune >= 0x0980 && rune <= 0x09FF) || // Bengali
    (rune >= 0x0B80 && rune <= 0x0BFF) || // Tamil
    (rune >= 0x0D80 && rune <= 0x0DFF) || // Sinhala
    (rune >= 0x0E00 && rune <= 0x0E7F);   // Thai

/// Reads a document into [NoteBlock]s.
NoteText extractNoteText(afe.Document document, {String title = ''}) {
  final blocks = <NoteBlock>[];
  for (final child in document.root.children) {
    _walk(child, blocks);
  }
  return NoteText(title: title, blocks: blocks);
}

void _walk(afe.Node node, List<NoteBlock> out) {
  final rendered = _renderNode(node);
  if (rendered != null) {
    out.add(NoteBlock(
      nodeId: node.id,
      path: List<int>.from(node.path),
      type: node.type,
      text: rendered.text,
      headingLevel: rendered.headingLevel,
    ));
  }
  // Nested blocks (list items, toggles, quotes) carry their children below
  // them; a code block's children, if any, are not content.
  if (node.type != CodeBlockKeys.type) {
    for (final child in node.children) {
      _walk(child, out);
    }
  }
}

({String text, int? headingLevel})? _renderNode(afe.Node node) {
  final attrs = node.attributes;

  switch (node.type) {
    case MathBlockKeys.type:
      final formula = asStringOr(attrs[MathBlockKeys.formula]).trim();
      if (formula.isEmpty) return null;
      // Fenced as LaTeX: an unfenced formula reads as broken prose, and models
      // handle `$$…$$` far better than a bare string of backslashes.
      return (text: '\$\$$formula\$\$', headingLevel: null);

    case CodeBlockKeys.type:
      final code = asStringOr(attrs[CodeBlockKeys.code]).trim();
      if (code.isEmpty) return null;
      final lang = asStringOr(attrs[CodeBlockKeys.language]);
      return (text: '```$lang\n$code\n```', headingLevel: null);

    case MarioImageKeys.type:
      final lines = asStringList(attrs[MarioImageKeys.ocrLines])
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        // Still worth a marker: "there is a picture here" stops the model
        // inventing a transition across the gap.
        return (text: '[image]', headingLevel: null);
      }
      return (
        text: '[image — text detected in it]\n${lines.join('\n')}',
        headingLevel: null
      );

    case AudioBlockKeys.type:
      final transcript =
          asStringOr(attrs[AudioBlockKeys.transcript]).trim();
      return transcript.isEmpty
          ? (text: '[audio recording, not transcribed]', headingLevel: null)
          : (text: '[audio transcript]\n$transcript', headingLevel: null);

    case SpreadsheetBlockKeys.type:
      final rendered = _renderWorkbook(attrs[SpreadsheetBlockKeys.workbook]);
      return rendered == null ? null : (text: rendered, headingLevel: null);

    case DrawingBlockKeys.type:
      return (text: '[drawing]', headingLevel: null);
  }

  // Stock text-bearing blocks.
  final delta = node.delta;
  final raw = delta?.toPlainText().trim() ?? '';
  if (raw.isEmpty) return null;

  switch (node.type) {
    case 'heading':
      final level = asInt(attrs['level']) ?? 1;
      return (text: '${'#' * level.clamp(1, 6)} $raw', headingLevel: level);
    case 'quote':
      return (text: '> $raw', headingLevel: null);
    case 'bulleted_list':
      return (text: '- $raw', headingLevel: null);
    case 'numbered_list':
      return (text: '1. $raw', headingLevel: null);
    case 'todo_list':
      final checked = attrs['checked'] == true;
      return (text: '- [${checked ? 'x' : ' '}] $raw', headingLevel: null);
    default:
      return (text: raw, headingLevel: null);
  }
}

/// Renders a spreadsheet as text rows, skipping empty trailing cells.
String? _renderWorkbook(Object? raw) {
  if (raw is! Map) return null;
  final sheets = raw['sheets'];
  final list = sheets is List ? sheets : [raw];
  final buf = StringBuffer();

  for (final s in list) {
    if (s is! Map) continue;
    final name = asStringOr(s['name'], 'Sheet');
    final cells = s['cells'];
    if (cells is! Map || cells.isEmpty) continue;

    // Cell keys are "A1"/"B2"; group them back into rows.
    final byRow = <int, Map<int, String>>{};
    for (final entry in cells.entries) {
      final parsed = _parseCellId(entry.key.toString());
      if (parsed == null) continue;
      final value = entry.value?.toString() ?? '';
      if (value.trim().isEmpty) continue;
      (byRow[parsed.row] ??= <int, String>{})[parsed.col] = value;
    }
    if (byRow.isEmpty) continue;

    buf.writeln('[spreadsheet: $name]');
    final rows = byRow.keys.toList()..sort();
    for (final r in rows) {
      final cols = byRow[r]!.keys.toList()..sort();
      buf.writeln([for (final c in cols) byRow[r]![c]!].join('\t'));
    }
  }
  final out = buf.toString().trim();
  return out.isEmpty ? null : out;
}

({int row, int col})? _parseCellId(String id) {
  final m = RegExp(r'^([A-Za-z]+)(\d+)$').firstMatch(id);
  if (m == null) return null;
  final letters = m.group(1)!.toUpperCase();
  var col = 0;
  for (final code in letters.codeUnits) {
    col = col * 26 + (code - 64);
  }
  return (row: int.parse(m.group(2)!), col: col);
}

/// Document order comparison for two node paths.
int _comparePaths(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return a.length.compareTo(b.length);
}
