/// The remodel's chrome fits in the height the design gives it.
///
/// The top bar went from 68px to 43 and the notebook strip is 35, with a 20px
/// mark, 28px controls and a 24px avatar inside them. Those are tight enough
/// that an overflow is a real risk rather than a theoretical one — and a
/// RenderFlex overflow in the app's permanent chrome would be on screen the
/// whole time, on every page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/models/notebook.dart';
import 'package:mario/core/services/auth_service.dart';
import 'package:mario/features/auth/auth_notifier.dart';
import 'package:mario/features/shell/notebook_tabs.dart';
import 'package:mario/features/shell/shell_state.dart';
import 'package:mario/features/shell/toolbar.dart';
import 'package:mario/ui/theme.dart';

final _grounds = <String, ThemeData Function()>{
  'light': MarioTheme.light,
  'white': MarioTheme.white,
  'night': MarioTheme.night,
  'black': MarioTheme.black,
};

Notebook _nb(String id, String name) => Notebook(
      id: id,
      name: name,
      ownerId: 'u1',
      colorIndex: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

final _notebooks = [
  _nb('n1', 'test'),
  _nb('n2', 'Research'),
  _nb('n3', 'Isssues'),
  _nb('n4', '2/4'),
];

Future<void> _pumpChrome(
  WidgetTester tester, {
  required ThemeData theme,
  required double width,
  MarioUser? user,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      authStateProvider.overrideWith((ref) => Stream.value(user)),
      notebooksStreamProvider.overrideWith((ref) => Stream.value(_notebooks)),
    ],
    child: MaterialApp(
      theme: theme,
      home: const Scaffold(
        appBar: ShellToolbar(),
        body: Column(children: [NotebookTabBar(), Expanded(child: SizedBox())]),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final g in _grounds.entries) {
    testWidgets('the bar and the strip fit on ${g.key}', (tester) async {
      await _pumpChrome(tester, theme: g.value(), width: 1272);
      expect(tester.takeException(), isNull);

      // The artboard's own heights, including each band's hairline.
      expect(tester.getSize(find.byType(ShellToolbar)).height, 43);
      expect(tester.getSize(find.byType(NotebookTabBar)).height, 35);
    });
  }

  testWidgets('the chrome survives every width it can be dragged to',
      (tester) async {
    // 1272 is the artboard. 800 is the app's documented desktop minimum; the
    // narrower two are what the responsive thresholds in the bar exist for,
    // and are where an overflow would actually show up.
    for (final w in [1600.0, 1272.0, 900.0, 800.0, 620.0, 420.0, 320.0]) {
      await _pumpChrome(tester, theme: MarioTheme.light(), width: w);
      expect(tester.takeException(), isNull, reason: 'overflowed at ${w}px');
    }
  });

  testWidgets('the search field gives way before anything else',
      (tester) async {
    // Wide: the field is on the bar and the right cluster has no search icon.
    await _pumpChrome(tester, theme: MarioTheme.light(), width: 1272);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Ctrl ⇧ F'), findsOneWidget);

    // Narrow: the field is gone, but searching is not — it falls back to an
    // icon in the right cluster rather than disappearing.
    await _pumpChrome(tester, theme: MarioTheme.light(), width: 420);
    expect(find.text('Search'), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);
    // Ask is never the thing that gets dropped.
    expect(find.text('Ask'), findsOneWidget);
  });

  testWidgets('the wordmark drops before the mark does', (tester) async {
    await _pumpChrome(tester, theme: MarioTheme.light(), width: 1272);
    expect(find.text('Mario'), findsOneWidget);

    await _pumpChrome(tester, theme: MarioTheme.light(), width: 320);
    expect(find.text('Mario'), findsNothing);
    expect(find.byType(Image), findsOneWidget, reason: 'the mark stays');
  });

  testWidgets('Recent leads the strip, and is live when home is',
      (tester) async {
    await _pumpChrome(tester, theme: MarioTheme.light(), width: 1272);

    // The selection starts at home, so Recent is the live tab.
    final recent = tester.widget<Text>(find.text('Recent'));
    expect(recent.style?.fontWeight, FontWeight.w600);

    for (final nb in _notebooks) {
      expect(find.text(nb.name), findsOneWidget);
      final tab = tester.widget<Text>(find.text(nb.name));
      expect(tab.style?.fontWeight, FontWeight.w400);
    }
  });

  testWidgets('a signed-out account shows no avatar', (tester) async {
    // The bar omits the chip rather than inventing a monogram.
    await _pumpChrome(tester, theme: MarioTheme.light(), width: 1272);
    expect(find.text('TD'), findsNothing);
  });
}
