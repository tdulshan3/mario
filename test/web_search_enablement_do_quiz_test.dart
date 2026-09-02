/// Web search reaches Do and Quiz, and the context claim is backed by a
/// request.
///
/// Three separate faults sat behind "enable web search for do and quiz":
///
///  * the agent had no search at all — it planned from the page and filled
///    any gap itself;
///  * the quiz HAD one, gated on difficulty, but the panel never passed the
///    difficulty through, so every quiz generated as "easy" and the look-up
///    could not fire whatever the user picked;
///  * both were pinned to whatever the difficulty implied, so "easy questions
///    on the current syllabus" and "hard questions strictly from my notes"
///    were unreachable.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider_config.dart';
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/features/ai/ai_session_state.dart';
import 'package:mario/features/ai/quiz_style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the quiz decides for itself whether to search', () {
    QuizSession session({QuizDifficulty? d, bool? web}) => QuizSession(
          difficulty: d ?? QuizDifficulty.easy,
          useWeb: web,
        );

    test('null follows the difficulty', () {
      expect(session(d: QuizDifficulty.easy).searchesWeb, isFalse);
      expect(session(d: QuizDifficulty.hard).searchesWeb, isTrue);
    });

    test('"always" searches even on easy', () {
      expect(session(d: QuizDifficulty.easy, web: true).searchesWeb, isTrue);
    });

    test('"never" holds even on hard', () {
      expect(session(d: QuizDifficulty.hard, web: false).searchesWeb, isFalse);
    });

    test('the notifier sets all three states', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(quizSessionProvider.notifier);

      expect(container.read(quizSessionProvider).useWeb, isNull);
      n.setWeb(true);
      expect(container.read(quizSessionProvider).useWeb, isTrue);
      n.setWeb(false);
      expect(container.read(quizSessionProvider).useWeb, isFalse);
      n.setWeb(null);
      expect(container.read(quizSessionProvider).useWeb, isNull,
          reason: 'back to following the difficulty');
    });
  });

  group('Do carries its own web preference', () {
    test('it starts on auto and cycles auto → on → off', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(agentSessionProvider.notifier);

      expect(container.read(agentSessionProvider).useWeb, isNull);
      n.cycleWeb();
      expect(container.read(agentSessionProvider).useWeb, isTrue);
      n.cycleWeb();
      expect(container.read(agentSessionProvider).useWeb, isFalse);
      n.cycleWeb();
      expect(container.read(agentSessionProvider).useWeb, isNull);
    });

    test('it is a separate decision from the Ask tab\'s', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(agentSessionProvider.notifier).cycleWeb();

      expect(container.read(agentSessionProvider).useWeb, isTrue);
      expect(container.read(askSessionProvider).useWeb, isNull,
          reason: 'asking a question and editing a page are different choices');
    });
  });

  group('the local context window', () {
    test('is 64k, not the old 8k', () {
      expect(kLocalContextTokens, 65536);

      for (final kind in [
        LlmProviderKind.ollama,
        LlmProviderKind.openAiCompatible,
      ]) {
        expect(kind.assumedCapabilities.contextTokens, kLocalContextTokens,
            reason: '${kind.name} was pinned to 8k');
      }
    });

    test('a server that states its own window still wins', () {
      // local_model_discovery carries contextLength through, so a 262k model
      // is not treated as a 64k one either.
      const stated = LlmCapabilities(contextTokens: 262144);
      expect(stated.contextTokens, isNot(kLocalContextTokens));
    });
  });
}
