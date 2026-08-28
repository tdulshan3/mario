/// How hard the model is told to think, and whether that reaches the backend.
///
/// The setting existed before this — LlmEffort, and a field on every request —
/// but only Anthropic was ever sent it. On an OpenAI-compatible server, which
/// is what a local model is, the field went nowhere: choosing "think harder"
/// would have changed the UI and nothing else.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/ai/llm_provider_config.dart';
import 'package:mario/core/services/ai/llm_types.dart';
import 'package:mario/features/ai/note_context.dart';

void main() {
  const config = LlmProviderConfig(
    id: 'x',
    label: 'LAN',
    kind: LlmProviderKind.openAiCompatible,
    baseUrl: 'http://192.168.1.118:8081/v1',
    model: 'qwen3.6',
  );

  group('the choice is saved against the backend', () {
    test('it survives a round trip through JSON', () {
      final saved = config.copyWith(effort: LlmEffort.high).toJson();
      expect(LlmProviderConfig.fromJson(saved).effort, LlmEffort.high);
    });

    test('a file written before this existed still loads', () {
      // Every saved config predates the field, so an absent value has to mean
      // something sensible rather than throwing or reading as "off".
      final old = {
        'id': 'x',
        'label': 'LAN',
        'kind': 'openAiCompatible',
        'baseUrl': 'http://x/v1',
        'model': 'qwen3.6',
      };
      expect(LlmProviderConfig.fromJson(old).effort, LlmEffort.medium);
    });

    test('an unrecognised value falls back rather than throwing', () {
      final broken = {...config.toJson(), 'effort': 'extreme'};
      expect(LlmProviderConfig.fromJson(broken).effort, LlmEffort.medium);
    });

    test('two backends can disagree', () {
      // The point of storing it per backend: "thorough" on a local 36B is
      // free thinking time, and on a hosted model it is money.
      final lan = config.copyWith(effort: LlmEffort.high);
      final hosted = config.copyWith(effort: LlmEffort.low);
      expect(lan.effort, LlmEffort.high);
      expect(hosted.effort, LlmEffort.low);
    });

    test('copyWith leaves it alone when not asked', () {
      final high = config.copyWith(effort: LlmEffort.high);
      expect(high.copyWith(label: 'renamed').effort, LlmEffort.high);
    });
  });

  group('every level is offered', () {
    test('three of them, and medium is the default', () {
      expect(LlmEffort.values, hasLength(3));
      expect(config.effort, LlmEffort.medium);
    });
  });

  group('thinking has to leave room to answer', () {
    // The failure this prevents: a reasoning model writes its deliberation
    // first and its answer last, out of one budget. A budget sized for the
    // answer alone gets spent thinking, the reply arrives empty, and the panel
    // says "the model returned an empty answer" — which reads as a broken
    // model rather than a budget set too low.
    test('the budget grows with the depth', () {
      expect(answerBudgetFor(LlmEffort.medium),
          greaterThan(answerBudgetFor(LlmEffort.low)));
      expect(answerBudgetFor(LlmEffort.high),
          greaterThan(answerBudgetFor(LlmEffort.medium)));
    });

    test('Fast keeps the budget it always had', () {
      // Nothing about turning thinking off should make an answer shorter than
      // it used to be.
      expect(answerBudgetFor(LlmEffort.low), 1200);
    });
  });

  group('an answer can be recovered from the thinking', () {
    test('a long deliberation is used rather than thrown away', () {
      final thinking = 'The user is asking about glycolysis. Net two ATP, '
          'because four are made and two are spent activating glucose.';
      expect(salvageFromReasoning(thinking), contains('two are spent'));
    });

    test('the end is kept, because that is where the conclusion is', () {
      final long = '${'early reasoning that was discarded. ' * 200}'
          'THE CONCLUSION IS AT THE END.';
      final salvaged = salvageFromReasoning(long);
      expect(salvaged, contains('THE CONCLUSION IS AT THE END.'));
      expect(salvaged, startsWith('…'), reason: 'say that it was cut');
      expect(salvaged.length, lessThan(1600));
    });

    test('a fragment of a thought is not offered as an answer', () {
      // Below a sentence or so it is noise, and showing it as an answer would
      // be worse than saying nothing came back.
      expect(salvageFromReasoning('Hmm, let me'), isEmpty);
      expect(salvageFromReasoning('   '), isEmpty);
      expect(salvageFromReasoning(''), isEmpty);
    });
  });
}
