/// The waiting indicator actually animates and lays out.
///
/// A loader that throws or renders nothing is worse than no loader — the user
/// sees a blank panel and assumes the app hung, which is the exact thing it
/// exists to prevent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/ui/colors.dart';
import 'package:mario/ui/theme.dart';
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

  /// The loader must follow the active theme, not a hardcoded constant.
  ///
  /// Book's primary is a warm brown; the brand amber this used to hardcode sits
  /// at roughly 1.3:1 on Book's cream paper, which is invisible rather than
  /// merely off-palette. The Material indicator it replaced got this right for
  /// free by inheriting progressIndicatorTheme, so hardcoding was a regression.
  testWidgets('takes its colour from the active theme, not a constant',
      (tester) async {
    Future<Color> colorUnder(ThemeData theme) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(body: Center(child: MarioLoader())),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      final dots = tester.widget(find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'FourRotatingDots'));
      return (dots as dynamic).color as Color;
    }

    expect(await colorUnder(MarioTheme.light()), MarioColors.primary);
    expect(await colorUnder(MarioTheme.dark()), MarioColors.primary);
    expect(await colorUnder(MarioTheme.book()), MarioColors.primaryBook);
  });

  testWidgets('an explicit colour still wins over the theme', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: MarioTheme.book(),
      home: const Scaffold(
        body: Center(child: MarioLoader(color: Color(0xFF1A1A1A))),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    final dots = tester.widget(find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'FourRotatingDots'));
    expect((dots as dynamic).color, const Color(0xFF1A1A1A));
  });

  /// Regression guard for the loading-button case.
  ///
  /// Every in-button loader in this app shows while the button is DISABLED
  /// (`onPressed: busy ? null : ...`). A disabled Material button paints
  /// onSurface at 12%, never primary — so dressing the loader in `onPrimary`,
  /// the obvious-looking choice, makes it vanish on the dark and book themes.
  /// The theme default is what actually reads on that fill.
  testWidgets('a loader in a button disabled while loading stays legible',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: MarioTheme.book(),
      home: Scaffold(
        body: Center(
          child: FilledButton.icon(
            onPressed: null, // disabled exactly while the loader shows
            icon: const MarioLoader(size: 16),
            label: const Text('Insert into page'),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    final dots = tester.widget(find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'FourRotatingDots'));
    final color = (dots as dynamic).color as Color;

    expect(color, MarioColors.primaryBook);
    expect(color, isNot(MarioTheme.book().colorScheme.onPrimary),
        reason: 'onPrimary disappears into the disabled fill');
    expect(tester.takeException(), isNull);
  });

  /// A loader that swaps in for an icon must not resize its button.
  ///
  /// FilledButton.icon lays the icon slot out at its child's intrinsic width, so
  /// a loader even a couple of pixels off its sibling icon makes the whole
  /// button jump the instant it starts loading — a small thing that reads as
  /// jank precisely when the user is already waiting.
  testWidgets('an in-button loader keeps the button the same width',
      (tester) async {
    Future<double> widthWith(Widget leading) async {
      await tester.pumpWidget(MaterialApp(
        theme: MarioTheme.light(),
        home: Scaffold(
          body: Center(
            child: FilledButton.icon(
              onPressed: null,
              icon: leading,
              label: const Text('Insert into page'),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      return tester.getSize(find.byType(FilledButton)).width;
    }

    final loading = await widthWith(const MarioLoader(size: 18));
    final idle = await widthWith(const Icon(Icons.playlist_add, size: 18));

    expect(loading, idle,
        reason: 'the loader and the icon it replaces must match in size');
  });
}
