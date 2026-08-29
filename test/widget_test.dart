/// The brand colours are the ones the mark is made of.
///
/// These four hues come straight off the Mario mark — a navy ground, a cream
/// page, a gold spine, a coral bookmark — and the whole "Organic" palette is
/// derived from them. Pinning them here means a retune of the ramps cannot
/// quietly drift the brand itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mario/ui/colors.dart';
import 'package:mario/ui/theme.dart';

void main() {
  test('the brand hues are the mark', () {
    expect(MarioColors.navy.toARGB32(), 0xFF17233D);
    expect(MarioColors.cream.toARGB32(), 0xFFFFF8E8);
    expect(MarioColors.gold.toARGB32(), 0xFFF2C14E);
    expect(MarioColors.coral.toARGB32(), 0xFFF05A47);
  });

  test('gold leads, blue supports, coral is retired', () {
    // The design retired the mark's coral from the interface: gold carries
    // actions and selection, and a navy blue that is NOT on the mark carries
    // the secondary emphasis. Coral survives only as a notebook label.
    expect(MarioColors.primary, MarioColors.gold);
    expect(MarioColors.secondary, MarioColors.blue);
    expect(MarioColors.primary, isNot(MarioColors.coral));
    expect(MarioColors.labelPalette, contains(MarioColors.coral));
  });

  // Building a theme resolves the web fonts, which only a widget-test binding
  // contains; a plain test() lets the async font error escape and fail after
  // the assertions have already passed.
  testWidgets('gold carries navy ink, never the ground', (tester) async {
    // Gold is light. The stylesheet overrides the system default of
    // background-coloured text precisely because cream on gold is unreadable.
    expect(MarioColors.onPrimary, MarioColors.navy);
    for (final t in [
      MarioTheme.light(),
      MarioTheme.white(),
      MarioTheme.night(),
      MarioTheme.black(),
    ]) {
      expect(t.colorScheme.onPrimary, MarioColors.navy);
    }
  });

  test('each ramp runs light to dark without repeating a step', () {
    void ascends(String name, List<Color> ramp) {
      final seen = <int>{};
      var previous = 1 << 30;
      for (final c in ramp) {
        final luminance = c.computeLuminance();
        final step = (luminance * 100000).round();
        expect(seen.add(step), isTrue, reason: '$name repeats a step');
        expect(step, lessThan(previous), reason: '$name is not monotonic');
        previous = step;
      }
    }

    ascends('neutral', const [
      MarioColors.neutral100,
      MarioColors.neutral200,
      MarioColors.neutral300,
      MarioColors.neutral400,
      MarioColors.neutral500,
      MarioColors.neutral600,
      MarioColors.neutral700,
      MarioColors.neutral800,
      MarioColors.neutral900,
    ]);
    ascends('accent', const [
      MarioColors.accent100,
      MarioColors.accent200,
      MarioColors.accent300,
      MarioColors.accent400,
      MarioColors.accent500,
      MarioColors.accent600,
      MarioColors.accent700,
      MarioColors.accent800,
      MarioColors.accent900,
    ]);
    ascends('accent2', const [
      MarioColors.accent2100,
      MarioColors.accent2200,
      MarioColors.accent2300,
      MarioColors.accent2400,
      MarioColors.accent2500,
      MarioColors.accent2600,
      MarioColors.accent2700,
      MarioColors.accent2800,
      MarioColors.accent2900,
    ]);
  });
}
