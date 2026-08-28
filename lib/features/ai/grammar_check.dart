/// Spelling and grammar suggestions.
///
/// Deliberately **on demand**, not as-you-type. Running a model on every
/// keystroke is the wrong shape twice over: a local 4B model cannot keep up
/// with typing, and a suggestion that appears mid-sentence is interrupting
/// someone who has not finished the thought yet. Mario checks when the user
/// asks it to, over the page or the selection, and presents a list.
///
/// Applying a fix is the part that has to be exactly right, because it edits
/// the user's own words. Three rules:
///
///  * **Anchored to a block, matched by text.** A suggestion carries the node
///    id it came from *and* the exact `before` string. Applying it re-reads
///    that block and only edits if the text is still there — if the user has
///    since rewritten the sentence, the suggestion is stale and is dropped
///    rather than applied to whatever now sits at that offset. The text match
///    is not belt-and-braces: AppFlowy node ids are session-scoped and not
///    serialised (see [NoteBlock.nodeId]), so the quoted text is the only
///    anchor that survives anything.
///  * **One fix per transaction.** Each accepted suggestion is its own undo
///    step, so Ctrl+Z takes back one correction rather than all of them.
///  * **Never silently rewritten.** Nothing is applied without a press.
library;

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;

import '../../core/services/ai/llm_service.dart';
import '../../core/services/ai/llm_types.dart';
import '../editor/blocks/_safe_transaction.dart';
import 'ai_progress.dart';
import 'note_context.dart';
import '../../core/services/ai/json_coercion.dart';

enum GrammarIssueKind { spelling, grammar, punctuation, clarity }

extension GrammarIssueKindLabel on GrammarIssueKind {
  String get label => switch (this) {
        GrammarIssueKind.spelling => 'Spelling',
        GrammarIssueKind.grammar => 'Grammar',
        GrammarIssueKind.punctuation => 'Punctuation',
        GrammarIssueKind.clarity => 'Clarity',
      };
}

class GrammarSuggestion {
  const GrammarSuggestion({
    required this.nodeId,
    required this.before,
    required this.after,
    required this.kind,
    this.reason = '',
  });

  /// The block this came from.
  final String nodeId;

  /// The exact original text. Also the safety check at apply time.
  final String before;

  final String after;
  final GrammarIssueKind kind;
  final String reason;

  bool get isNoop => before.trim() == after.trim();
}

/// Runs a check over [note] and reports suggestions.
class GrammarChecker {
  GrammarChecker(this.llm);

  final LlmService llm;

  static const _system =
      'You proofread a student\'s own notes.\n'
      'Report only clear errors: misspellings, subject-verb disagreement, '
      'missing or wrong punctuation, and sentences that do not parse.\n'
      'Do NOT rewrite for style, do NOT change British to American spelling or '
      'the reverse, and do NOT touch technical terms, proper nouns, variable '
      'names, code, formulas or abbreviations you do not recognise — in study '
      'notes an unfamiliar word is far more likely to be correct jargon than a '
      'typo.\n'
      'Notes are often written in shorthand. Sentence fragments and dropped '
      'articles are a deliberate note-taking style, not errors.\n'
      'Quote "before" exactly as it appears, character for character, and keep '
      'it short — the phrase that is wrong, not the whole paragraph.\n'
      'If the text is fine, return an empty list. That is a good outcome, not '
      'a failure.';

  static const schema = {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'suggestions': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'blockIndex': {
              'type': 'integer',
              'description': 'The [n] marker of the block this is in.',
            },
            'before': {'type': 'string'},
            'after': {'type': 'string'},
            'kind': {
              'type': 'string',
              'enum': ['spelling', 'grammar', 'punctuation', 'clarity'],
            },
            'reason': {'type': 'string'},
          },
          'required': ['blockIndex', 'before', 'after', 'kind'],
        },
      },
    },
    'required': ['suggestions'],
  };

  AiRun check(NoteText note) {
    final run = AiRun(const [
      AiStepKind.readingNote,
      AiStepKind.thinking,
      AiStepKind.checking,
    ]);
    unawaited(_run(run, note));
    return run;
  }

  Future<void> _run(AiRun run, NoteText note) async {
    try {
      final provider = await llm.requireProvider();
      run.setBackend(provider.displayName);

      run.begin(AiStepKind.readingNote);
      // Only prose is worth proofreading. Sending a code block to a grammar
      // checker produces confident nonsense about the punctuation in a for-loop.
      final prose = [
        for (final b in note.blocks)
          if (_isProse(b)) b,
      ];
      if (prose.isEmpty) {
        throw const LlmException('There is no prose here to check.');
      }
      run.detail('${prose.length} paragraph(s)');

      // Numbered so a suggestion can name the block it belongs to without the
      // model having to echo node ids it will inevitably corrupt.
      final numbered = StringBuffer();
      for (var i = 0; i < prose.length; i++) {
        numbered.writeln('[$i] ${prose[i].text}');
      }

      run.begin(AiStepKind.thinking);
      final result = await llm.structured(
        request: LlmRequest(
          system: _system,
          messages: [LlmMessage.user(numbered.toString())],
          maxTokens: 1400,
          temperature: 0,
          effort: LlmEffort.low,
        ),
        schemaName: 'grammar_suggestions',
        schema: schema,
        cancel: run.cancelToken,
      );

      run.begin(AiStepKind.checking);
      final suggestions = parseGrammarSuggestions(result, prose);
      run.setResult(suggestions);
      run.appendAnswer(suggestions.isEmpty
          ? 'No problems found.'
          : '${suggestions.length} suggestion(s).');
      run.finish();
    } catch (e) {
      run.fail(e);
    }
  }

  static bool _isProse(NoteBlock b) =>
      const {'paragraph', 'heading', 'quote', 'bulleted_list', 'numbered_list',
              'todo_list'}
          .contains(b.type) &&
      b.text.trim().length > 2;
}

/// Turns the model's reply into suggestions that are safe to offer.
///
/// Everything unverifiable is dropped here rather than at apply time, so the
/// user is never shown a fix that cannot be applied:
///
///  * a `blockIndex` outside the list we sent
///  * a `before` string that does not actually occur in that block — the model
///    paraphrased instead of quoting, and applying it would edit the wrong text
///  * a no-op, where `after` equals `before`
///  * a "fix" that deletes the text entirely
List<GrammarSuggestion> parseGrammarSuggestions(
  Map<String, dynamic> raw,
  List<NoteBlock> prose,
) {
  final out = <GrammarSuggestion>[];
  for (final m in asMapList(raw['suggestions'])) {
    final index = asInt(m['blockIndex']);
    if (index == null || index < 0 || index >= prose.length) continue;

    final before = asStringOr(m['before']);
    final after = asStringOr(m['after']);
    if (before.trim().isEmpty || after.trim().isEmpty) continue;
    if (before.trim() == after.trim()) continue;

    // The quote has to be real. This is the check that stops a paraphrasing
    // model from silently rewriting a sentence it never actually read.
    if (!prose[index].text.contains(before)) continue;

    out.add(GrammarSuggestion(
      nodeId: prose[index].nodeId,
      before: before,
      after: after,
      kind: switch (m['kind']) {
        'spelling' => GrammarIssueKind.spelling,
        'punctuation' => GrammarIssueKind.punctuation,
        'clarity' => GrammarIssueKind.clarity,
        _ => GrammarIssueKind.grammar,
      },
      reason: asStringOr(m['reason']).trim(),
    ));
  }
  return out;
}

/// Applies one suggestion, if the text it describes is still there.
///
/// Returns false when the block is gone or has been edited since the check —
/// which is not an error, just a suggestion that expired.
Future<bool> applyGrammarSuggestion(
  afe.EditorState editorState,
  GrammarSuggestion suggestion,
) async {
  if (editorState.isDisposed) return false;

  final node = _findNodeById(editorState.document.root, suggestion.nodeId);
  final delta = node?.delta;
  if (node == null || delta == null) return false;

  final text = delta.toPlainText();
  final at = text.indexOf(suggestion.before);
  // The user rewrote this sentence while the check was running, or accepted an
  // overlapping fix first. Either way the offsets no longer mean anything.
  if (at < 0) return false;

  return safeApply(editorState, (tx) {
    tx.replaceText(node, at, suggestion.before.length, suggestion.after);
  });
}

afe.Node? _findNodeById(afe.Node root, String id) {
  for (final child in root.children) {
    if (child.id == id) return child;
    final found = _findNodeById(child, id);
    if (found != null) return found;
  }
  return null;
}
