/// The Simple design system's components hold their spec, on all four grounds.
///
/// These are the shapes the remodel introduced — the segmented control, the
/// 38×22 toggle, the ruled setting row, the underlined tab, and the 2px accent
/// bar that marks a selected row. Each is drawn from explicit numbers on the
/// artboard, so the numbers are what is asserted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/ui/colors.dart';
import 'package:mario/ui/organic.dart';
import 'package:mario/ui/theme.dart';

final _grounds = <String, ThemeData Function()>{
  'light': MarioTheme.light,
  'white': MarioTheme.white,
  'night': MarioTheme.night,
  'black': MarioTheme.black,
};

Future<void> _pump(WidgetTester tester, ThemeData theme, Widget child) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: Center(child: child)),
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final g in _grounds.entries) {
    testWidgets('every component renders on ${g.key}', (tester) async {
      await _pump(
        tester,
        g.value(),
        SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 35,
                child: Row(children: [
                  MarioTab(label: 'Recent', selected: true, onTap: () {}),
                  MarioTab(label: 'Research', selected: false, onTap: () {}),
                ]),
              ),
              const MarioSearchField(hint: 'Search', trailing: 'Ctrl ⇧ F'),
              const MarioSearchField(hint: 'Search page…', bordered: true),
              MarioSettingRow(
                label: 'Match the system',
                description: 'Light by day, Calm night after dark.',
                child: MarioToggle(value: true, onChanged: (_) {}),
              ),
              MarioSettingRow(
                label: 'Page width',
                last: true,
                child: MarioSegmented<String>(
                  options: const ['Narrow', 'Medium', 'Full'],
                  value: 'Medium',
                  onChanged: (_) {},
                  labelOf: (v) => v,
                ),
              ),
              const MarioKicker('Today'),
              const MarioAvatar(initials: 'TD'),
              const MarioTag('draft'),
              const MarioCountBadge(4),
              const MarioKeyHint('esc'),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the toggle is the artboard\'s 38×22', (tester) async {
    var on = false;
    await _pump(
      tester,
      MarioTheme.light(),
      StatefulBuilder(
        builder: (_, setState) => MarioToggle(
          value: on,
          onChanged: (v) => setState(() => on = v),
        ),
      ),
    );

    final box = tester.getSize(find.byType(MarioToggle));
    expect(box.width, 38);
    expect(box.height, 22);

    await tester.tap(find.byType(MarioToggle));
    await tester.pumpAndSettle();
    expect(on, isTrue);
  });

  testWidgets('the segmented control can have nothing chosen', (tester) async {
    // The Theme row is in exactly this state while "match the system" is on.
    String? picked;
    await _pump(
      tester,
      MarioTheme.light(),
      MarioSegmented<String>(
        options: const ['Light', 'White', 'Calm night', 'Black'],
        value: null,
        onChanged: (v) => picked = v,
        labelOf: (v) => v,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Calm night'), findsOneWidget);

    await tester.tap(find.text('Calm night'));
    await tester.pump();
    expect(picked, 'Calm night');
  });

  testWidgets('the accent bar marks a row without displacing its label',
      (tester) async {
    // The artboard draws it as an inset shadow, which does not take space.
    // Drawn as a Border it would push the label 2px across, so selected and
    // unselected rows would not line up — the whole reason it is an overlay.
    Future<double> xFor(bool active) async {
      await _pump(
        tester,
        MarioTheme.light(),
        SizedBox(
          width: 240,
          child: MarioAccentEdge(
            active: active,
            child: const SizedBox(
              height: 32,
              child: Padding(
                padding: EdgeInsets.only(left: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Activity 3'),
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getTopLeft(find.text('Activity 3')).dx;
    }

    final off = await xFor(false);
    final on = await xFor(true);
    expect(on, off, reason: 'the bar is an overlay, not a border');
  });

  testWidgets('a live tab is heavier and inked; an idle one is secondary',
      (tester) async {
    await _pump(
      tester,
      MarioTheme.light(),
      SizedBox(
        height: 35,
        child: Row(children: [
          MarioTab(label: 'Recent', selected: true, onTap: () {}),
          MarioTab(label: 'Research', selected: false, onTap: () {}),
        ]),
      ),
    );

    final live = tester.widget<Text>(find.text('Recent'));
    final idle = tester.widget<Text>(find.text('Research'));
    expect(live.style?.fontWeight, FontWeight.w600);
    expect(idle.style?.fontWeight, FontWeight.w400);
    expect(live.style?.color, MarioColors.ink);
    expect(idle.style?.color, MarioColors.sec);
    expect(live.style?.fontSize, 13);
  });

  testWidgets('density reaches the rows that use it', (tester) async {
    for (final d in MarioDensity.values) {
      late MarioTokens tok;
      await _pump(
        tester,
        MarioTheme.light(density: d),
        Builder(builder: (c) {
          tok = marioTokens(c);
          return const SizedBox();
        }),
      );
      // Row height and type size are discrete, so MarioTokens.lerp snaps them
      // at the halfway point of a theme change rather than interpolating.
      // Successive pumps here reuse the element tree and animate, so the
      // transition has to finish before the new density is the live one.
      await tester.pumpAndSettle();
      expect(tok.row, d.row);
      expect(tok.rowFontSize, d.fontSize);
    }
  });

  testWidgets('the avatar is neutral, not gold', (tester) async {
    // The remodel spends the accent on the two 2px bars and nothing else.
    await _pump(
      tester,
      MarioTheme.light(),
      const MarioAvatar(initials: 'TD'),
    );
    final box = tester.getSize(find.byType(MarioAvatar));
    expect(box.width, 24);
    expect(box.height, 24);

    final decorated = tester.widget<Container>(
      find.descendant(
        of: find.byType(MarioAvatar),
        matching: find.byType(Container),
      ),
    );
    final decoration = decorated.decoration as BoxDecoration;
    expect(decoration.color, MarioColors.fill);
    expect(decoration.color, isNot(MarioColors.gold));
  });

  testWidgets('a key hint is plain text, not a pill', (tester) async {
    await _pump(tester, MarioTheme.light(), const MarioKeyHint('Ctrl ⇧ F'));
    // No box of any kind around it — the artboard sets these bare.
    expect(
      find.descendant(
        of: find.byType(MarioKeyHint),
        matching: find.byType(DecoratedBox),
      ),
      findsNothing,
    );
    final t = tester.widget<Text>(find.text('Ctrl ⇧ F'));
    expect(t.style?.fontSize, 11);
    expect(t.style?.color, MarioColors.mut);
  });
}
