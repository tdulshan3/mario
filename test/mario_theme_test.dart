/// The four grounds of the Simple remodel hold their spec.
///
/// These are the values the design names explicitly — the near-white page,
/// the cream White, Calm night's grey, pure black — so a drift here is a
/// drift away from the design, not a matter of taste. The Light/White and
/// Night/Black pairs also share a Brightness, which is exactly why the mode
/// marker has to exist: brightness alone cannot tell either pair apart.
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

    // The grounds the design names by hex. Light is the near-white page;
    // White is one cream ground; Calm night is a neutral grey with no blue in
    // it; Black is pure #000.
    expect(light.colorScheme.surface, const Color(0xFFFAF9F7),
        reason: 'the near-white ground');
    expect(white.colorScheme.surface, const Color(0xFFFFF8E0),
        reason: 'the cream ground');
    expect(night.colorScheme.surface, const Color(0xFF2F2F2F),
        reason: 'the neutral grey');
    expect(black.colorScheme.surface, const Color(0xFF000000),
        reason: 'pure black, for OLED');

    expect(light.brightness, Brightness.light);
    expect(white.brightness, Brightness.light);
    expect(night.brightness, Brightness.dark);
    expect(black.brightness, Brightness.dark);
  });

  testWidgets('each ground sets the page against the chrome its own way',
      (tester) async {
    MarioTokens tok(ThemeData t) => t.extension<MarioTokens>()!;

    // Light steps side < bg < paper, so the page lifts off the chrome.
    final light = tok(MarioTheme.light());
    expect(light.side, isNot(light.bg));
    expect(light.paper, isNot(light.bg));

    // White and Black are one flat ground; hairlines do the separating.
    for (final t in [MarioTheme.white(), MarioTheme.black()]) {
      final flat = tok(t);
      expect(flat.side, flat.bg);
      expect(flat.paper, flat.bg);
    }

    // Calm night sinks the page below the chrome instead of lifting it.
    final night = tok(MarioTheme.night());
    expect(night.side, night.bg);
    expect(
        night.paper.computeLuminance(), lessThan(night.bg.computeLuminance()));
  });

  testWidgets('gold holds on every ground; the dark accents lift',
      (tester) async {
    // Gold reads on the near-white page, on navy and on black alike, so the
    // primary does not shift. Blue and slate do: at full strength they sit
    // too close to the navy ground to separate from it.
    for (final t in [
      MarioTheme.light(),
      MarioTheme.white(),
      MarioTheme.night(),
      MarioTheme.black(),
    ]) {
      expect(t.colorScheme.primary, MarioColors.gold);
    }

    expect(MarioAccent.gold.baseOn(dark: true), MarioAccent.gold.base);
    expect(MarioAccent.coral.baseOn(dark: true), MarioAccent.coral.base);
    expect(MarioAccent.blue.baseOn(dark: true), MarioAccent.blue.lifted);
    expect(MarioAccent.slate.baseOn(dark: true), MarioAccent.slate.lifted);
  });

  testWidgets('accent TEXT never uses the chrome tone on a light ground',
      (tester) async {
    // Gold on white is about 1.6:1. Every accent therefore ships a deep step
    // for text, and it must not be the base tone.
    for (final a in MarioAccent.values) {
      expect(a.textOn(dark: false), a.text);
      expect(a.textOn(dark: false), isNot(a.base),
          reason: '${a.name}: the base tone is chrome-contrast only');
      expect(a.textOn(dark: true), a.lifted);
    }
    expect(MarioTheme.light().colorScheme.secondary, MarioAccent.gold.text);
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
      expect(e.value.extension<MarioTokens>()?.mode, e.key);
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

  testWidgets('marioTokens falls back to Light with no extension installed',
      (tester) async {
    late MarioTokens seen;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        seen = marioTokens(c);
        return const SizedBox();
      }),
    ));
    expect(seen.bg, MarioColors.bg);
    expect(seen.accent, MarioAccent.gold);
    expect(seen.density, MarioDensity.balanced);
  });

  testWidgets('headings are the body face, not a display face', (tester) async {
    for (final t in [
      MarioTheme.light(),
      MarioTheme.white(),
      MarioTheme.night(),
      MarioTheme.black(),
    ]) {
      final tok = t.extension<MarioTokens>()!;

      // The remodel's ramp: 31 / 24 / 20, all set at w600 with a touch of
      // negative tracking rather than in a display face.
      expect(t.textTheme.displayLarge?.fontSize, 31);
      expect(t.textTheme.displayMedium?.fontSize, 24);
      expect(t.textTheme.displaySmall?.fontSize, 20);
      for (final s in [
        t.textTheme.displayLarge,
        t.textTheme.displayMedium,
        t.textTheme.displaySmall,
      ]) {
        expect(s?.fontWeight, FontWeight.w600);
        expect(s?.letterSpacing, lessThan(0));
      }

      // Page copy is 15/1.62 and AI copy 14.5, both in the body ink — a step
      // off the full ink the headings use.
      expect(t.textTheme.bodyLarge?.fontSize, 15);
      expect(t.textTheme.bodyMedium?.fontSize, 14.5);
      expect(t.textTheme.bodyLarge?.color, tok.body);
      expect(t.textTheme.displayLarge?.color, tok.ink);
    }
  });

  testWidgets('the pills are gone', (tester) async {
    // The remodel takes the pill radius out of every small control; 999
    // survives only for the two genuinely circular things (the avatar chip
    // and the toggle), which do not go through the button themes.
    final t = MarioTheme.light();
    final shape = t.filledButtonTheme.style?.shape?.resolve({})
        as RoundedRectangleBorder?;
    expect(shape?.borderRadius, BorderRadius.circular(MarioRadius.sm));
    expect(MarioRadius.sm, 6.0);
    expect(MarioRadius.lg, 10.0);
    expect(MarioRadius.card, MarioRadius.lg,
        reason: 'the old 32.2 card radius belonged to the round-card system');
    expect(MarioRadius.pill, 999.0);
  });

  testWidgets('density drives the row metrics', (tester) async {
    for (final d in MarioDensity.values) {
      final tok = MarioTheme.light(density: d).extension<MarioTokens>()!;
      expect(tok.row, d.row);
      expect(tok.rowFontSize, d.fontSize);
    }
    expect(MarioDensity.compact.row, 28);
    expect(MarioDensity.balanced.row, 32);
    expect(MarioDensity.roomy.row, 36);
  });

  testWidgets('the chosen accent reaches the theme', (tester) async {
    for (final a in MarioAccent.values) {
      final light = MarioTheme.light(accent: a);
      expect(light.colorScheme.primary, a.base);
      expect(light.colorScheme.secondary, a.text);

      final night = MarioTheme.night(accent: a);
      expect(night.colorScheme.primary, a.baseOn(dark: true));
      expect(night.colorScheme.secondary, a.lifted);
    }
  });
}
