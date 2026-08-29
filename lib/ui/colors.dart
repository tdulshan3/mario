/// Mario colour tokens — the "Organic" system, retuned to the Mario mark.
///
/// The mark is the palette: a navy ground, a cream page, a gold spine and a
/// coral bookmark. Everything below is derived from those four hues.
///
///   navy   #17233d  ink, and the ground of the night themes
///   cream  #fff8e8  the default ground
///   gold   #f2c14e  the secondary accent — sections, highlights, avatars
///   coral  #f05a47  the primary accent — actions, selection, focus
///
/// Three tonal ramps (neutral / accent / accent2) run 100→900 on one shared
/// lightness scale, so the same step of any role matches the others in visual
/// value. Reach for a ramp step when you need a specific tone; reach for a
/// role (surface, onSurface, border…) when you mean "whatever this theme uses".
///
/// Four themes sit on these tokens — Light, White, Night and Black. The role
/// fields are per-theme and mostly exist so `theme.dart` reads clearly; widgets
/// should prefer `Theme.of(context).colorScheme.*` so the active theme flows
/// through automatically.
library;

import 'package:flutter/material.dart';

class MarioColors {
  const MarioColors._();

  // ── The mark ────────────────────────────────────────────────────────────
  static const navy = Color(0xFF17233D);
  static const cream = Color(0xFFFFF8E8);
  static const gold = Color(0xFFF2C14E);

  /// The mark's bookmark ribbon. Retired from the interface — it survives here
  /// because it is still part of the mark, and as a notebook label colour.
  static const coral = Color(0xFFF05A47);

  /// Not on the mark: the second accent, drawn from the same navy family as
  /// the ink so it sits with the palette rather than competing with the gold.
  static const blue = Color(0xFF2F5FB5);

  // ── Neutral ramp (cream → navy) ─────────────────────────────────────────
  static const neutral100 = Color(0xFFFFFCF3);
  static const neutral200 = Color(0xFFFFF3DD);
  static const neutral300 = Color(0xFFEEE2C8);
  static const neutral400 = Color(0xFFCDC4B1);
  static const neutral500 = Color(0xFFA6A396);
  static const neutral600 = Color(0xFF7D7F7D);
  static const neutral700 = Color(0xFF565D64);
  static const neutral800 = Color(0xFF333E51);
  static const neutral900 = Color(0xFF17233D);

  // ── Accent ramp — gold. The primary accent. ─────────────────────────────
  static const accent100 = Color(0xFFFFF8E0);
  static const accent200 = Color(0xFFFDEEBD);
  static const accent300 = Color(0xFFF8DD8F);
  static const accent400 = Color(0xFFF2C14E);
  static const accent500 = Color(0xFFDDA72F);
  static const accent600 = Color(0xFFB98620);
  static const accent700 = Color(0xFF8F6717);
  static const accent800 = Color(0xFF664912);
  static const accent900 = Color(0xFF412E0D);

  // ── Accent-2 ramp — navy blue. The secondary accent. ───────────────────
  static const accent2100 = Color(0xFFEEF3FD);
  static const accent2200 = Color(0xFFD8E4FA);
  static const accent2300 = Color(0xFFB4C9F2);
  static const accent2400 = Color(0xFF7FA3E3);
  static const accent2500 = Color(0xFF4D7CCF);
  static const accent2600 = Color(0xFF2F5FB5);
  static const accent2700 = Color(0xFF234891);
  static const accent2800 = Color(0xFF1A3468);
  static const accent2900 = Color(0xFF122343);

  // ── Brand roles ─────────────────────────────────────────────────────────
  /// The primary accent — actions, selection, focus, the send button.
  ///
  /// Gold is a LIGHT colour, so what sits on it is the navy ink, never the
  /// ground. The stylesheet says exactly that: `.btn-primary { color:
  /// var(--color-text) }` overriding the system's default of the background.
  static const primary = accent400;
  static const primaryPressed = accent600;

  /// What reads on [primary]. Navy, on every ground — gold does not darken
  /// enough on the dark themes to carry light text.
  static const onPrimary = navy;

  /// The secondary accent — section markers, highlights, quiet emphasis.
  static const secondary = blue;
  static const secondaryPressed = accent2700;

  // ── Light — the default. Cream ground, translucent chrome, solid paper ──
  static const surface = cream;
  static const surfaceVariant = Color(0xFFF7ECD4);
  static const surfaceElevated = neutral100;
  static const onSurface = navy;
  static const onSurfaceMuted = neutral600;
  static const border = neutral300;

  // ── White — for bright rooms and printing. The cream drops out ──────────
  static const surfaceWhite = Color(0xFFFFFEFA);
  static const surfaceVariantWhite = neutral100;
  static const surfaceElevatedWhite = Color(0xFFFFFFFF);
  static const onSurfaceWhite = navy;
  static const onSurfaceMutedWhite = neutral600;
  static const borderWhite = neutral200;

  // ── Calm night — the mark's navy, full bleed. Easier to sit in than Black
  static const surfaceDark = navy;
  static const surfaceVariantDark = Color(0xFF1D2A45);
  static const surfaceElevatedDark = neutral800;
  static const onSurfaceDark = neutral100;
  static const onSurfaceMutedDark = neutral400;
  static const borderDark = Color(0xFF2C3850);

  /// Gold already reads on navy and on black, so the primary does NOT shift
  /// on the dark grounds — the design uses the same `accent-400` there. Only
  /// the blue lifts, because `blue` itself is too close to the navy ground.
  static const primaryDark = accent400;
  static const secondaryDark = accent2400;

  // ── Black — pure black, white-alpha glass, no shadows. Best on OLED ─────
  //
  // The alpha step off black IS the elevation here; there are no drop shadows
  // to read against #000, so each surface is a slightly stronger white veil.
  static const surfaceBlack = Color(0xFF000000);
  static const surfaceVariantBlack = Color(0xFF0E0E0E);
  static const surfaceElevatedBlack = Color(0xFF141414);
  static const onSurfaceBlack = neutral100;
  static const onSurfaceMutedBlack = neutral500;
  static const borderBlack = Color(0xFF242424);

  // ── Notebook label palette ──────────────────────────────────────────────
  // Six hues that hold up on cream and on navy. Coral and gold are the two
  // from the mark; the rest are tuned to the same warmth so a notebook list
  // reads as one set rather than a default swatch grid.
  static const labelRed = coral;
  static const labelOrange = Color(0xFFE08A4B);
  static const labelYellow = Color(0xFFD9A62E);
  static const labelGreen = Color(0xFF7FA86B);
  static const labelTeal = Color(0xFF4E9E96);
  static const labelPurple = Color(0xFF9B7BB8);

  static const List<Color> labelPalette = [
    labelRed,
    labelOrange,
    labelYellow,
    labelGreen,
    labelTeal,
    labelPurple,
  ];
}

/// Shape and rhythm tokens from the design system.
///
/// The scale is 4.4px — an odd-looking base that comes from the type ramp, not
/// from rounding to 4. Keeping the real numbers means spacing stays in step
/// with the fonts instead of drifting a fraction at every step.
class MarioSpace {
  const MarioSpace._();

  static const x1 = 4.4;
  static const x2 = 8.8;
  static const x3 = 13.2;
  static const x4 = 17.6;
  static const x6 = 26.4;
  static const x8 = 35.2;
}

/// Corner radii. Small controls go fully pill; panels and paper stay soft.
class MarioRadius {
  const MarioRadius._();

  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 28.0;

  /// Buttons, inputs, tags and segmented controls are pills in this system.
  static const pill = 999.0;

  /// Cards and dialogs sit a touch softer than [lg].
  static const card = 32.2;
}
