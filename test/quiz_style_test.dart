/// The rules that decide what a quiz question is allowed to look like.
///
/// Two things are worth testing here, and neither is "does the string exist".
/// The first is that easy and hard genuinely differ in *kind* — if hard were
/// only "longer questions" the whole feature would be decoration. The second is
/// the search query, which is the one piece of real logic: a bad query sends a
/// paragraph to a search engine and gets a paragraph's worth of noise back.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/quiz_style.dart';

void main() {
  group('the two difficulties are different exams', () {
    test('only hard consults the web', () {
      // Easy is answerable from the notes by definition, so a lookup would add
      // latency and cost for nothing.
      expect(QuizDifficulty.easy.usesWeb, isFalse);
      expect(QuizDifficulty.hard.usesWeb, isTrue);
    });

    test('both carry the item-writing rules', () {
      for (final d in QuizDifficulty.values) {
        expect(quizStyleFor(d), contains(quizStyleCore), reason: d.name);
      }
    });

    test('easy stays inside the notes, hard reasons past them', () {
      final easy = quizStyleFor(QuizDifficulty.easy).toLowerCase();
      final hard = quizStyleFor(QuizDifficulty.hard).toLowerCase();

      expect(easy, contains('from the notes alone'));
      expect(easy, contains('recall'));

      expect(hard, contains('beyond recall'));
      expect(hard, stringContainsInOrder(['apply', 'flaw']));
    });

    test('hard is still a quiz about *these* notes', () {
      // The failure mode of "make it harder" is a model wandering off into
      // adjacent material the student was never given.
      expect(quizStyleFor(QuizDifficulty.hard).toLowerCase(),
          contains('anchored to the notes'));
    });

    test('each has a label and a blurb the setup screen can show', () {
      for (final d in QuizDifficulty.values) {
        expect(d.label, isNotEmpty);
        expect(d.blurb, isNotEmpty);
      }
      expect(QuizDifficulty.easy.label, isNot(QuizDifficulty.hard.label));
    });
  });

  group('the item-writing rules name the flaws worth naming', () {
    // Each of these is a flaw a model produces unprompted, and each one lets a
    // student answer without knowing the subject.
    test('bans the options that give the game away', () {
      final core = quizStyleCore.toLowerCase();
      expect(core, contains('all of the above'));
      expect(core, contains('none of the above'));
    });

    test('requires exactly one defensible answer', () {
      expect(quizStyleCore.toLowerCase(), contains('one defensibly correct'));
    });

    test('requires distractors to be real misconceptions', () {
      expect(quizStyleCore.toLowerCase(), contains('misconception'));
    });

    test('stops the answer being the longest option', () {
      // Length is the single most exploitable tell in machine-written items.
      expect(quizStyleCore.toLowerCase(),
          stringContainsInOrder(['longest', 'must not be the answer']));
    });

    test('asks for a markable essay rubric, not a vibe', () {
      expect(quizStyleCore.toLowerCase(), contains('cannot be marked'));
    });
  });

  group('the search query hard mode looks the subject up with', () {
    test('leads with the title, then the headings', () {
      final q =
          searchTopicFor('Cell Respiration', ['Glycolysis', 'Krebs cycle']);
      expect(q, 'Cell Respiration Glycolysis Krebs cycle');
    });

    test('drops a title that names nothing', () {
      // "Untitled" as a search term returns the internet, not the subject.
      expect(searchTopicFor('Untitled page', ['Photosynthesis']),
          'Photosynthesis');
      expect(searchTopicFor('   ', ['Photosynthesis']), 'Photosynthesis');
    });

    test('strips markdown hashes off headings', () {
      expect(searchTopicFor('', ['## Enzymes']), 'Enzymes');
    });

    test('takes only the first few headings', () {
      // A query built from forty headings describes no topic at all.
      final q = searchTopicFor('', [for (var i = 0; i < 40; i++) 'Topic$i']);
      expect(q, 'Topic0 Topic1 Topic2');
    });

    test('caps the length, because engines do worse with a paragraph', () {
      final q = searchTopicFor('x' * 400, const []);
      expect(q.length, lessThanOrEqualTo(120));
    });

    test('returns nothing when there is nothing to look up', () {
      // The caller must be able to tell "no topic" from "some topic", because
      // searching for an empty string wastes a request and a step in the UI.
      expect(searchTopicFor('', const []), isEmpty);
      expect(searchTopicFor('', const ['', '   ']), isEmpty);
      expect(searchTopicFor('Untitled', const []), isEmpty);
    });
  });
}
