/// The four grounds of the redesign hold their spec.
///
/// These are the values the design names explicitly — the cream, the mark's
/// navy, pure black — so a drift here is a drift away from the design, not a
/// matter of taste. The Light/White and Night/Black pairs also share a
/// Brightness, which is exactly why the mode marker has to exist: brightness
/// alone cannot tell either pair apart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mario/ui/colors.dart';
import 'package:mario/ui/theme.dart';

void main() {
  testWidgets('every ground is a distinct, correctly-branded surface',
      (tester) async {
    final light = MarioTheme.light();
    final white = MarioTheme.white();
    final night = MarioTheme.night();
    final black = MarioTheme.black();

    // The grounds the design names by hex.
    expect(light.colorScheme.surface, const Color(0xFFFFF8E8), reason: 'cream');
    expect(night.colorScheme.surface, const Color(0xFF17233D),
        reason: "the mark's navy");
    expect(black.colorScheme.surface, const Color(0xFF000000),
        reason: 'pure black, for OLED');
    expect(white.colorScheme.surface, isNot(light.colorScheme.surface),
        reason: 'White exists precisely because the cream drops out');

    expect(light.brightness, Brightness.light);
    expect(white.brightness, Brightness.light);
    expect(night.brightness, Brightness.dark);
    expect(black.brightness, Brightness.dark);
  });

  testWidgets('gold holds on every ground; only the blue lifts',
      (tester) async {
    // Gold reads on cream, on navy and on black alike, so the primary does not
    // shift. The blue second accent does: at full strength it sits too close
    // to the navy ground to separate from it.
    for (final t in [
      MarioTheme.light(),
      MarioTheme.white(),
      MarioTheme.night(),
      MarioTheme.black(),
    ]) {
      expect(t.colorScheme.primary, MarioColors.gold);
    }
    expect(MarioTheme.light().colorScheme.secondary, MarioColors.blue);
    expect(MarioTheme.night().colorScheme.secondary, MarioColors.secondaryDark);
    expect(MarioColors.secondaryDark, isNot(MarioColors.blue));
  });

  testWidgets('each theme carries its own mode marker', (tester) async {
    final modes = {
      MarioThemeMode.light: MarioTheme.light(),
      MarioThemeMode.white: MarioTheme.white(),
      MarioThemeMode.night: MarioTheme.night(),
      MarioThemeMode.black: MarioTheme.black(),
    };
    for (final e in modes.entries) {
      expect(e.value.extension<MarioThemeMarker>()?.mode, e.key);
    }
  });

  testWidgets('only Black treats alpha as elevation', (tester) async {
    // Black paints no drop shadows — a shadow against #000 is invisible, so
    // the alpha step off the ground has to carry the depth instead.
    bool alpha(ThemeData t) =>
        t.extension<MarioThemeMarker>()!.usesAlphaElevation;
    expect(alpha(MarioTheme.black()), isTrue);
    expect(alpha(MarioTheme.light()), isFalse);
    expect(alpha(MarioTheme.white()), isFalse);
    expect(alpha(MarioTheme.night()), isFalse);
  });

  testWidgets('marioMode reports the ground it is under', (tester) async {
    late MarioThemeMode seen;
    await tester.pumpWidget(MaterialApp(
      theme: MarioTheme.black(),
      home: Builder(builder: (c) {
        seen = marioMode(c);
        return const SizedBox();
      }),
    ));
    expect(seen, MarioThemeMode.black);
  });

  testWidgets('marioMode falls back to Light with no marker installed',
      (tester) async {
    // A bare MaterialApp installs no MarioThemeMarker — a widget test that
    // does not name a theme, say. Light is the documented default.
    late MarioThemeMode seen;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        seen = marioMode(c);
        return const SizedBox();
      }),
    ));
    expect(seen, MarioThemeMode.light);
  });

  testWidgets('text keeps the display/body split across every ground',
      (tester) async {
    for (final t in [
      MarioTheme.light(),
      MarioTheme.white(),
      MarioTheme.night(),
      MarioTheme.black(),
    ]) {
      // The design's ramp: 42 / 32 / 25 for the display sizes.
      expect(t.textTheme.displayLarge?.fontSize, 42);
      expect(t.textTheme.displayMedium?.fontSize, 32);
      expect(t.textTheme.displaySmall?.fontSize, 25);
      // Body copy is 15/1.55, not Material's 14.
      expect(t.textTheme.bodyMedium?.fontSize, 15);
      // Ink matches the ground's on-colour.
      expect(t.textTheme.bodyMedium?.color, t.colorScheme.onSurface);
    }
  });

  testWidgets('small controls are pills', (tester) async {
    final t = MarioTheme.light();
    final shape = t.filledButtonTheme.style?.shape?.resolve({})
        as RoundedRectangleBorder?;
    expect(shape?.borderRadius, BorderRadius.circular(MarioRadius.pill));
    expect(MarioRadius.pill, 999.0);
  });
}
