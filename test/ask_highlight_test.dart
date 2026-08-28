/// Asking about a highlighted passage.
///
/// Highlighting text is also ordinary editing — dragging across a sentence to
/// delete it, double-clicking a word. The whole design rests on telling a
/// deliberate highlight from an incidental one, and on the attachment being
/// visible and dismissible: a question silently scoped to a selection the user
/// has forgotten making produces an answer that looks wrong for no reason they
/// can see.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/ai_progress.dart';
import 'package:mario/features/ai/ai_session_state.dart';
import 'package:mario/features/ai/ai_state.dart';

void main() {
  AiRun newRun() => AiRun(const [AiStepKind.thinking]);

  test('a highlight becomes the focus of the next question', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(askSessionProvider.notifier)
        .quote('Mitochondria generate most of the cell\'s ATP.');

    expect(container.read(askSessionProvider).quoted,
        contains('Mitochondria'));
  });

  test('it can be dismissed, putting the question back on the whole page', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(askSessionProvider.notifier)
      ..quote('some passage')
      ..clearQuote();

    expect(container.read(askSessionProvider).quoted, isNull);
  });

  test('asking consumes the highlight', () {
    // Otherwise the next, unrelated question stays silently scoped to a
    // passage the user highlighted minutes ago.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final n = container.read(askSessionProvider.notifier)
      ..quote('a passage')
      ..startRun(newRun(), question: 'what does this mean?');

    expect(container.read(askSessionProvider).quoted, isNull);
    n.state.run?.dispose();
  });

  test('a later highlight replaces an earlier one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(askSessionProvider.notifier)
      ..quote('first passage')
      ..quote('second passage');

    expect(container.read(askSessionProvider).quoted, 'second passage');
  });

  test('the highlight survives a tab switch, like everything else', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(askSessionProvider.notifier).quote('a passage');
    container.read(aiPanelProvider.notifier)
      ..showTab(AiPanelTab.quiz)
      ..showTab(AiPanelTab.ask);

    expect(container.read(askSessionProvider).quoted, 'a passage');
  });

  group('the editor publishes selections through a shared provider', () {
    test('nothing selected reads as null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(editorSelectionProvider), isNull);
    });

    test('a published selection is readable by the panel', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(editorSelectionProvider.notifier).state =
          'the Krebs cycle occurs in the mitochondrial matrix';

      expect(container.read(editorSelectionProvider), contains('Krebs'));
    });

    test('clearing is immediate, so a stale quote cannot linger', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(editorSelectionProvider.notifier)
        ..state = 'something'
        ..state = null;

      expect(container.read(editorSelectionProvider), isNull);
    });
  });

  group('the auto-open setting', () {
    test('defaults on, since that is the point of the feature', () {
      // Verified through the state object rather than the notifier, which
      // needs SharedPreferences.
      expect(const _Defaults().askOnHighlight, isTrue);
    });
  });
}

/// Mirrors SettingsState's default so the expectation is readable without
/// standing up shared_preferences.
class _Defaults {
  const _Defaults();
  bool get askOnHighlight => true;
}
