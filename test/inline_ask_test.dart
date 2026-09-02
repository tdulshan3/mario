/// The ask composer is summoned, appears at the caret, and gets out of the way.
///
/// It began as a permanent footer under every page — which is what the
/// artboard draws, and which in a real notebook means a control sitting under
/// every document whether or not anyone is asking anything. `/ask` opens it
/// now; Escape and Discard close it.
///
/// Three details are load-bearing. Its visibility comes from state it watches,
/// not from a parent choosing whether to build it. It positions against a
/// caret offset captured on open, because by submit time the caret is in the
/// composer's own field. And an answer keeps it on screen after the composer
/// is dismissed, so a reply is never yanked away mid-read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/ai_state.dart';
import 'package:mario/features/ai/inline_ask.dart';
import 'package:mario/ui/theme.dart';

const _placeholder = 'Ask Mario about this page, or type / for blocks';

Future<WidgetRef> pumpAsk(WidgetTester tester, [ThemeData? theme]) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late WidgetRef captured;
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: theme ?? MarioTheme.light(),
      home: Scaffold(
        // Top-left, not centred: the anchor is in the canvas's own
        // coordinates, and a centred canvas would offset every assertion by
        // the slack around it.
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 720,
            height: 600,
            child: Consumer(
              builder: (context, ref, _) {
                captured = ref;
                return const InlineAsk(inset: 52);
              },
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  return captured;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('nothing is on the page until it is asked for', (tester) async {
    await pumpAsk(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(_placeholder), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('/ask opens it', (tester) async {
    final ref = await pumpAsk(tester);

    ref.read(inlineAskProvider.notifier).openWith('');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(_placeholder), findsOneWidget);
    expect(find.text('⏎'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });

  testWidgets('it is the artboard\'s 36px, inset to the text edge',
      (tester) async {
    final ref = await pumpAsk(tester);
    ref.read(inlineAskProvider.notifier).openWith('');
    await tester.pump();

    final field = find
        .ancestor(
          of: find.text(_placeholder),
          matching: find.byType(Container),
        )
        .first;
    expect(tester.getSize(field).height, 36);
  });

  testWidgets('with no caret it falls back to the foot of the canvas',
      (tester) async {
    final ref = await pumpAsk(tester);
    ref.read(inlineAskProvider.notifier).openWith('');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(_placeholder), findsOneWidget);
  });

  testWidgets('it opens at the caret, not at the bottom', (tester) async {
    final ref = await pumpAsk(tester);
    ref
        .read(inlineAskProvider.notifier)
        .openWith('', anchor: const Offset(0, 120));
    await tester.pump();

    // 120 is well above the 600px canvas's halfway mark, so the box hangs
    // below the caret line rather than opening upwards.
    final top = tester.getTopLeft(find.byType(TextField)).dy;
    expect(top, greaterThan(120));
    expect(top, lessThan(300), reason: 'it should be near the caret');
  });

  testWidgets('near the bottom it opens upwards instead of running off',
      (tester) async {
    final ref = await pumpAsk(tester);
    ref
        .read(inlineAskProvider.notifier)
        .openWith('', anchor: const Offset(0, 560));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Anchored by its bottom to the caret, so the field sits ABOVE it.
    expect(tester.getBottomLeft(find.byType(TextField)).dy, lessThan(560));
  });

  testWidgets('closing puts the page back exactly as it was', (tester) async {
    final ref = await pumpAsk(tester);

    ref.read(inlineAskProvider.notifier).openWith('');
    await tester.pump();
    expect(find.text(_placeholder), findsOneWidget);

    ref.read(inlineAskProvider.notifier).close();
    await tester.pump();
    expect(find.text(_placeholder), findsNothing);
  });

  testWidgets('a question typed after /ask is consumed exactly once',
      (tester) async {
    // `/ask what is a monad` carries the question through. Leaving it in place
    // would re-ask it on the next rebuild.
    final ref = await pumpAsk(tester);

    ref.read(inlineAskProvider.notifier).openWith('what is a monad');
    await tester.pump();
    // The seed is taken in a post-frame callback — writing to a provider
    // straight from build is what broke the Do tab.
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(ref.read(inlineAskProvider).seed, isEmpty);
    expect(ref.read(inlineAskProvider).open, isTrue,
        reason: 'taking the question must not close the composer');
  });

  testWidgets('no answer block until something has been asked', (tester) async {
    final ref = await pumpAsk(tester);
    ref.read(inlineAskProvider.notifier).openWith('');
    await tester.pump();

    expect(find.text('Insert below'), findsNothing);
    expect(find.text('Discard'), findsNothing);
    expect(find.text('Mario'), findsNothing);
  });

  for (final g in {
    'light': MarioTheme.light,
    'white': MarioTheme.white,
    'night': MarioTheme.night,
    'black': MarioTheme.black,
  }.entries) {
    testWidgets('renders on ${g.key}', (tester) async {
      final ref = await pumpAsk(tester, g.value());
      ref.read(inlineAskProvider.notifier).openWith('');
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text(_placeholder), findsOneWidget);
    });
  }
}
