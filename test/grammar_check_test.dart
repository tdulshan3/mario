/// Filtering proofreading suggestions before they are offered.
///
/// This code edits the user's own sentences, so the bar is higher than
/// elsewhere: a suggestion is only shown if it can be applied exactly. The
/// critical case is the paraphrase — a model asked to quote the text verbatim
/// will sometimes summarise it instead, and applying that "fix" would replace
/// words the model never actually read.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/grammar_check.dart';
import 'package:mario/features/ai/note_context.dart';

void main() {
  NoteBlock block(String text, {String id = 'n1', int index = 0}) => NoteBlock(
        nodeId: id,
        path: [index],
        type: 'paragraph',
        text: text,
      );

  Map<String, dynamic> reply(List<Map<String, dynamic>> suggestions) =>
      {'suggestions': suggestions};

  group('parseGrammarSuggestions', () {
    final prose = [
      block('Their going to the libary tomorrow.', id: 'a', index: 0),
      block('The mitochondria is the powerhouse.', id: 'b', index: 1),
    ];

    test('keeps a suggestion that quotes the text exactly', () {
      final out = parseGrammarSuggestions(
        reply([
          {
            'blockIndex': 0,
            'before': 'Their going',
            'after': "They're going",
            'kind': 'grammar',
            'reason': 'possessive vs contraction',
          }
        ]),
        prose,
      );
      expect(out, hasLength(1));
      expect(out.first.nodeId, 'a');
      expect(out.first.after, "They're going");
      expect(out.first.kind, GrammarIssueKind.grammar);
    });

    test('maps blockIndex to the right node id', () {
      final out = parseGrammarSuggestions(
        reply([
          {
            'blockIndex': 1,
            'before': 'mitochondria is',
            'after': 'mitochondria are',
            'kind': 'grammar',
          }
        ]),
        prose,
      );
      expect(out.single.nodeId, 'b');
    });

    test('drops a paraphrase that does not occur in the block', () {
      // The single most dangerous failure: applying this would replace text
      // the model never quoted.
      final out = parseGrammarSuggestions(
        reply([
          {
            'blockIndex': 0,
            'before': 'they are going to the library',
            'after': "They're going to the library",
            'kind': 'grammar',
          }
        ]),
        prose,
      );
      expect(out, isEmpty);
    });

    test('drops an out-of-range blockIndex', () {
      final out = parseGrammarSuggestions(
        reply([
          {
            'blockIndex': 7,
            'before': 'anything',
            'after': 'something',
            'kind': 'spelling',
          }
        ]),
        prose,
      );
      expect(out, isEmpty);
    });

    test('drops a no-op suggestion', () {
      final out = parseGrammarSuggestions(
        reply([
          {
            'blockIndex': 0,
            'before': 'Their going',
            'after': 'Their going',
            'kind': 'grammar',
          }
        ]),
        prose,
      );
      expect(out, isEmpty);
    });

    test('drops a fix that would delete the text', () {
      final out = parseGrammarSuggestions(
        reply([
          {
            'blockIndex': 0,
            'before': 'Their going',
            'after': '',
            'kind': 'grammar',
          }
        ]),
        prose,
      );
      expect(out, isEmpty);
    });

    test('an empty list is a valid, successful result', () {
      // Clean prose must read as "nothing to fix", never as a failed check.
      expect(parseGrammarSuggestions(reply([]), prose), isEmpty);
      expect(parseGrammarSuggestions(const {}, prose), isEmpty);
    });

    test('malformed entries are skipped without losing the good ones', () {
      final out = parseGrammarSuggestions(
        reply([
          {'blockIndex': 0, 'before': 'nope', 'after': 'x', 'kind': 'spelling'},
          {
            'blockIndex': 0,
            'before': 'libary',
            'after': 'library',
            'kind': 'spelling',
          },
        ]),
        prose,
      );
      expect(out, hasLength(1));
      expect(out.single.after, 'library');
    });

    test('an unrecognised kind falls back to grammar rather than dropping', () {
      final out = parseGrammarSuggestions(
        reply([
          {
            'blockIndex': 0,
            'before': 'libary',
            'after': 'library',
            'kind': 'typo-ish',
          }
        ]),
        prose,
      );
      expect(out.single.kind, GrammarIssueKind.grammar);
    });

    test('every issue kind has a human label', () {
      for (final k in GrammarIssueKind.values) {
        expect(k.label, isNotEmpty);
      }
    });
  });
}
