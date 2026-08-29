/// Where the panel's one composer sends what you type.
///
/// The composer is a single control docked at the foot of every tab, which
/// makes it easy to forget that it has more than one destination. It used to
/// have exactly one: everything typed anywhere went to Ask. On the Do tab that
/// meant the visible composer answered questions about the page while a second,
/// larger box above it was the only thing that could actually change the page —
/// and a preset tapped from the launcher put three lines of prompt into that
/// box and left it there, which reads as "not sent".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/ai_state.dart';

void main() {
  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('a question goes to Ask', () {
    test('opening the panel on the Ask tab with the question queued', () {
      final c = container();
      c.read(aiPanelProvider.notifier).askQuestion('what is glycolysis?');

      final state = c.read(aiPanelProvider);
      expect(state.isOpen, isTrue);
      expect(state.tab, AiPanelTab.ask);
      expect(state.pendingQuestion, 'what is glycolysis?');
      expect(state.pendingInstruction, isNull,
          reason: 'a question must never arrive at the agent as an edit');
    });

    test('it is consumed exactly once', () {
      // The tab reads this on mount; a rebuild that read it again would run the
      // same question twice.
      final c = container();
      final panel = c.read(aiPanelProvider.notifier);
      panel.askQuestion('q');
      expect(panel.takePendingQuestion(), 'q');
      expect(panel.takePendingQuestion(), isNull);
    });
  });

  group('an instruction goes to Do', () {
    test('opening the panel on the Do tab with the instruction queued', () {
      final c = container();
      c.read(aiPanelProvider.notifier).runInstruction('add a table');

      final state = c.read(aiPanelProvider);
      expect(state.isOpen, isTrue);
      expect(state.tab, AiPanelTab.agent);
      expect(state.pendingInstruction, 'add a table');
      expect(state.pendingQuestion, isNull,
          reason: 'an edit must never arrive at Ask as a question');
    });

    test('it is consumed exactly once', () {
      final c = container();
      final panel = c.read(aiPanelProvider.notifier);
      panel.runInstruction('rename this page');
      expect(panel.takePendingInstruction(), 'rename this page');
      expect(panel.takePendingInstruction(), isNull);
    });
  });

  group('the two queues do not interfere', () {
    test('taking one leaves the other', () {
      // Both can be outstanding: /ask queues a question, then the user taps a
      // preset before the Ask tab has mounted to collect it.
      final c = container();
      final panel = c.read(aiPanelProvider.notifier);
      panel.askQuestion('q');
      panel.runInstruction('i');

      expect(panel.takePendingQuestion(), 'q');
      expect(c.read(aiPanelProvider).pendingInstruction, 'i',
          reason: 'consuming the question must not clear the instruction');
      expect(panel.takePendingInstruction(), 'i');
    });

    test('switching tabs by hand clears neither', () {
      final c = container();
      final panel = c.read(aiPanelProvider.notifier);
      panel.runInstruction('i');
      panel.showTab(AiPanelTab.quiz);
      expect(c.read(aiPanelProvider).pendingInstruction, 'i');
    });
  });
}
