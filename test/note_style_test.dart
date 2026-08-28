/// The house style actually reaches the models.
///
/// A style guide that is written but not wired in is worse than none — it reads
/// as though the problem is solved. These tests are cheap and they pin the two
/// things that silently break: that each task gets the rules it needs, and that
/// the rules a task must *not* get are absent.
///
/// They deliberately assert on the *substance* of a few rules rather than
/// matching exact prose, so rewording the guide does not break them but
/// deleting a rule does.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/note_style.dart';

void main() {
  /// The guide is wrapped prose, so a rule can straddle a line break. Matching
  /// on collapsed whitespace keeps these tests about the *rules* rather than
  /// about where the paragraph happened to wrap.
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  group('the core rules cover what actually goes wrong', () {
    test('bans the chatbot preamble', () {
      expect(flat(noteStyleCore), contains('No preamble'));
      expect(flat(noteStyleCore).toLowerCase(),
          contains('restatement of the question'));
    });

    test('pins heading case and level', () {
      expect(flat(noteStyleCore), contains('Sentence case'));
      // A second h1 competes with the page title.
      expect(flat(noteStyleCore), contains('Never write a level-1 heading'));
    });

    test('says what each emphasis form is for', () {
      for (final form in [
        '**Bold**',
        '*Italic*',
        '`Code style`',
        'block quote'
      ]) {
        expect(flat(noteStyleCore), contains(form),
            reason: '$form has no stated purpose, so the model will guess');
      }
    });

    test('says what NOT to highlight, which is the half that gets omitted', () {
      expect(flat(noteStyleCore), contains('Never bold a whole sentence'));
      expect(flat(noteStyleCore), contains('one line in ten'));
    });

    test('requires examples to be concrete and runnable', () {
      expect(flat(noteStyleCore), contains('concrete example'));
      expect(flat(noteStyleCore), contains('must actually run'));
      expect(flat(noteStyleCore), contains('shows the steps'));
    });

    test('covers formulas and tables', () {
      expect(flat(noteStyleCore), contains('display maths'));
      expect(flat(noteStyleCore), contains('Define every symbol'));
      expect(flat(noteStyleCore), contains('header row'));
    });

    test('forbids inventing facts to fill a gap', () {
      expect(flat(noteStyleCore), contains('Never invent a fact'));
    });
  });

  group('each task gets the core plus only what differs', () {
    test('every context includes the core', () {
      for (final c in NoteStyleContext.values) {
        expect(flat(noteStyleFor(c)), contains('HOUSE STYLE FOR NOTES'),
            reason: '$c would otherwise have no base rules at all');
      }
    });

    test('a summary is told not to invent structure', () {
      // A summary is read instead of the page; headings in it are noise, and
      // structure invites the reader to trust it as complete.
      final style = noteStyleFor(NoteStyleContext.summary);
      expect(flat(style), contains('No headings'));
      // Summarising wrong notes is not the same job as fixing them.
      expect(flat(style).toLowerCase(), contains('do not quietly correct'));
    });

    test('an inserted answer is told to match its surroundings', () {
      final style = noteStyleFor(NoteStyleContext.insertedAnswer);
      expect(flat(style), contains('inserted into the page'));
      expect(flat(style), contains('Match the surrounding notes'));
    });

    test('only the agent is told to create structure', () {
      // The one writer that legitimately adds headings.
      expect(flat(noteStyleFor(NoteStyleContext.agent)),
          contains('Add a heading'));
      expect(flat(noteStyleFor(NoteStyleContext.summary)),
          isNot(contains('Add a heading')));
    });

    test('quiz feedback is told to be short and unpatronising', () {
      final style = noteStyleFor(NoteStyleContext.quizFeedback);
      expect(flat(style), contains('One or two sentences'));
      expect(flat(style), contains('No encouragement'));
    });

    test('the contexts differ from one another', () {
      final rendered = NoteStyleContext.values.map(noteStyleFor).toSet();
      expect(rendered, hasLength(NoteStyleContext.values.length),
          reason: 'two contexts producing identical text means one is unused');
    });
  });

  group('it stays worth its tokens', () {
    test('the core is substantial but not a book', () {
      // Prompt text is paid for on every request, including on a local model
      // where prefill is the slow part.
      expect(noteStyleCore.length, greaterThan(1200));
      expect(noteStyleCore.length, lessThan(4500));
    });

    test('the per-task additions stay short', () {
      for (final c in NoteStyleContext.values) {
        final extra = noteStyleFor(c).length - noteStyleCore.length;
        expect(extra, lessThan(900), reason: '$c addendum is too long');
      }
    });
  });
}
