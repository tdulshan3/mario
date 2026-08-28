/// The waiting indicator actually animates and lays out.
///
/// A loader that throws or renders nothing is worse than no loader — the user
/// sees a blank panel and assumes the app hung, which is the exact thing it
/// exists to prevent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/ui/widgets/mario_loader.dart';

void main() {
  testWidgets('renders and animates without throwing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: MarioLoader())),
    ));
    expect(find.byType(MarioLoader), findsOneWidget);
    // Advance through the animation rather than only the first frame.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a too-small size is raised to stay legible', (tester) async {
    // Four dots rotating in 8px is a smudge, not an animation.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: MarioLoader(size: 8))),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    final box = tester.getSize(find.byType(MarioLoader));
    expect(box.width, greaterThanOrEqualTo(MarioLoader.minLegibleSize));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits the 22x20 slot the progress list gives it', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 22, height: 20, child: MarioLoader(size: 16)),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull,
        reason: 'the active-step slot must not overflow');
  });

  testWidgets('the labelled variant shows its label and trailing action',
      (tester) async {
    var stopped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MarioLoaderWithLabel(
          label: 'Marking 3 of 20',
          trailing: TextButton(
            onPressed: () => stopped = true,
            child: const Text('Stop'),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Marking 3 of 20'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    expect(stopped, isTrue);
    expect(tester.takeException(), isNull);
  });
}
