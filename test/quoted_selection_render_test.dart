/// The highlight chip paints.
///
/// This was a render-time assertion, not a compile error: the analyser and the
/// build were both clean while every frame threw. Flutter allows a non-uniform
/// border only when the *visible* sides share a colour, and the chip had four
/// visible sides in two colours alongside a borderRadius. The accent is now a
/// child rather than a coloured left border.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/ai_session_state.dart';
import 'package:mario/features/ai/ask_panel.dart';

void main() {
  testWidgets('the highlight chip renders without a border assertion',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(askSessionProvider.notifier)
        .quote('The Krebs cycle occurs in the mitochondrial matrix.');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SizedBox(width: 360, child: AskPanel())),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('ASKING ABOUT YOUR HIGHLIGHT'), findsOneWidget);
  });

  testWidgets('nothing overflows at the panel minimum width', (tester) async {
    // 280 is ResizablePanel's minWidth for this panel, so it is a width the
    // user can actually drag to.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SizedBox(width: 280, child: AskPanel())),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long highlight does not overflow the panel', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(askSessionProvider.notifier)
        .quote('A very long highlighted passage. ' * 30);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SizedBox(width: 280, child: AskPanel())),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing it clears the quote', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(askSessionProvider.notifier).quote('a passage worth asking');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SizedBox(width: 360, child: AskPanel())),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('Ask about the whole page instead'));
    await tester.pump();

    expect(container.read(askSessionProvider).quoted, isNull);
    expect(tester.takeException(), isNull);
  });
}
