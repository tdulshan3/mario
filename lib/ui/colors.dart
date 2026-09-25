/// Mario colour tokens — the "Simple" system.
///
/// The remodel drops the cream ground and the translucent chrome. What is
/// left is a near-white page, hairline rules, and one accent used sparingly:
/// a 2px bar under the live tab, a 2px bar beside the selected row, an icon
/// tint, and nothing else. Chrome is separated from the page by a LINE, not
/// by a fill — which is what lets the whole interface sit at 43px of top bar
/// instead of 64.
///
///   ink    #17233d  text, and the ground of the night theme
///   sec    #5a5f68  secondary text — labels, inactive tabs
///   mut    #8a8c90  muted text — placeholders, timestamps, meta
///   bg     #faf9f7  the app ground
///   side   #f5f4f1  the sidebar, a half-step down from the ground
///   paper  #ffffff  the writing surface, a half-step up
///   line   ink @ 10%  every hairline in the interface
///   fill   ink @ 5%   the one subtle fill — search pill, avatar, segments
///
/// The accent is user-chosen from four hues. Each ships as a PAIR: the base
/// tone is chrome-contrast only (gold on white is 1.6:1, nowhere near
/// readable), so accent-coloured *text* uses the deep step instead. Never
/// paint a label in the base tone — reach for [MarioAccent.text].
///
/// The three tonal ramps survive from the previous system because a great
/// deal of the app still reaches for a specific step. Roles are what screens
/// should use; ramp steps are for when you mean one exact tone.
library;

import 'package:flutter/material.dart';

class MarioColors {
  const MarioColors._();

  // ── The mark ────────────────────────────────────────────────────────────
  static const navy = Color(0xFF17233D);
  static const cream = Color(0xFFFFF8E8);
  static const gold = Color(0xFFF2C14E);

  /// The mark's bookmark ribbon. One of the four selectable accents, and
  /// still a notebook label colour.
  static const coral = Color(0xFFF05A47);

  /// Not on the mark: drawn from the same navy family as the ink so it sits
  /// with the palette rather than competing with the gold.
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

  // ── Accent ramp — gold ──────────────────────────────────────────────────
  static const accent100 = Color(0xFFFFF8E0);
  static const accent200 = Color(0xFFFDEEBD);
  static const accent300 = Color(0xFFF8DD8F);
  static const accent400 = Color(0xFFF2C14E);
  static const accent500 = Color(0xFFDDA72F);
  static const accent600 = Color(0xFFB98620);
  static const accent700 = Color(0xFF8F6717);
  static const accent800 = Color(0xFF664912);
  static const accent900 = Color(0xFF412E0D);

  // ── Accent-2 ramp — navy blue ───────────────────────────────────────────
  static const accent2100 = Color(0xFFEEF3FD);
  static const accent2200 = Color(0xFFD8E4FA);
  static const accent2300 = Color(0xFFB4C9F2);
  static const accent2400 = Color(0xFF7FA3E3);
  static const accent2500 = Color(0xFF4D7CCF);
  static const accent2600 = Color(0xFF2F5FB5);
  static const accent2700 = Color(0xFF234891);
  static const accent2800 = Color(0xFF1A3468);
  static const accent2900 = Color(0xFF122343);

  // ── Simple roles — Light. The default ground. ───────────────────────────
  static const ink = Color(0xFF17233D);
  static const sec = Color(0xFF5A5F68);
  static const mut = Color(0xFF8A8C90);
  static const bg = Color(0xFFFAF9F7);
  static const side = Color(0xFFF5F4F1);
  static const paper = Color(0xFFFFFFFF);

  /// Body copy sits a touch off the full ink — the design sets long-form
  /// paragraphs and AI answers in this, keeping full ink for headings and
  /// for the words a search actually matched.
  static const body = Color(0xFF242B3A);

  // ── Simple roles — White. One cream ground, chrome and page alike. ──────
  static const inkWhite = Color(0xFF17233D);
  static const secWhite = Color(0xFF5A5F68);
  static const mutWhite = Color(0xFF8A8C90);
  static const bgWhite = Color(0xFFFFF8E0);
  static const sideWhite = Color(0xFFFFF8E0);
  static const paperWhite = Color(0xFFFFF8E0);
  static const bodyWhite = Color(0xFF242B3A);

  // ── Simple roles — Calm night. Neutral grey, no blue in it. ─────────────
  //
  // The page sits darker than the chrome around it, so the writing surface
  // reads as a well rather than a sheet lifted off the ground.
  static const inkNight = Color(0xFFD0D0D0);
  static const secNight = Color(0xFFA0A0A0);
  static const mutNight = Color(0xFF767676);
  static const bgNight = Color(0xFF2F2F2F);
  static const sideNight = Color(0xFF2F2F2F);
  static const paperNight = Color(0xFF1F1F1F);
  static const bodyNight = Color(0xFFA0A0A0);

  // ── Simple roles — Black. Pure #000 everywhere, for OLED. ───────────────
  static const inkBlack = Color(0xFFD0D0D0);
  static const secBlack = Color(0xFFA0A0A0);
  static const mutBlack = Color(0xFF767676);
  static const bgBlack = Color(0xFF000000);
  static const sideBlack = Color(0xFF000000);
  static const paperBlack = Color(0xFF000000);
  static const bodyBlack = Color(0xFFA0A0A0);

  // ── Hairlines and the one subtle fill ───────────────────────────────────
  /// `--line` — every rule in the interface, at ink 10%.
  static const line = Color(0x1A17233D);

  /// `--fill` — search pill, avatar chip, segmented track, at ink 5%.
  static const fill = Color(0x0D17233D);

  /// On the dark grounds the same two roles are white-alpha: a darker rule
  /// over grey or black reads as a gap rather than as a line.
  static const lineNight = Color(0x1AFFFFFF);
  static const fillNight = Color(0x0FFFFFFF);
  static const lineBlack = Color(0x1FFFFFFF);
  static const fillBlack = Color(0x0FFFFFFF);

  // ── Brand roles ─────────────────────────────────────────────────────────
  /// The default accent. Gold is a LIGHT colour, so what sits on it is the
  /// navy ink, never the ground.
  static const primary = accent400;
  static const primaryPressed = accent600;
  static const onPrimary = navy;

  static const secondary = blue;
  static const secondaryPressed = accent2700;
  static const primaryDark = accent400;
  static const secondaryDark = accent2400;

  // ── Legacy surface roles ────────────────────────────────────────────────
  //
  // theme.dart maps these onto the ColorScheme for Material's own widgets.
  // Screens should prefer the Simple roles above, reached through
  // `marioTokens(context)`, which follow the active ground.
  static const surface = bg;
  static const surfaceVariant = side;
  static const surfaceElevated = paper;
  static const onSurface = ink;
  static const onSurfaceMuted = sec;
  static const border = Color(0xFFE6E4E0);

  static const surfaceWhite = bgWhite;
  static const surfaceVariantWhite = sideWhite;
  static const surfaceElevatedWhite = paperWhite;
  static const onSurfaceWhite = inkWhite;
  static const onSurfaceMutedWhite = secWhite;
  static const borderWhite = Color(0xFFEBEBEB);

  static const surfaceDark = bgNight;
  static const surfaceVariantDark = sideNight;
  static const surfaceElevatedDark = paperNight;
  static const onSurfaceDark = inkNight;
  static const onSurfaceMutedDark = secNight;
  static const borderDark = Color(0xFF2C3850);

  static const surfaceBlack = bgBlack;
  static const surfaceVariantBlack = sideBlack;
  static const surfaceElevatedBlack = paperBlack;
  static const onSurfaceBlack = inkBlack;
  static const onSurfaceMutedBlack = secBlack;
  static const borderBlack = Color(0xFF242424);

  // ── Notebook label palette ──────────────────────────────────────────────
  // Six hues that hold up on the near-white page and on navy. Coral and gold
  // are the two from the mark; the rest are tuned to the same warmth so a
  // notebook list reads as one set rather than a default swatch grid.
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

/// The four selectable accents.
///
/// Each carries three tones because one is not enough. [base] is the bar and
/// the icon — it only ever has to separate from chrome. [text] is the deep
/// step, the only one that may carry a *word* on a light ground. [lifted] is
/// what both become on navy and black, where the deep step disappears into
/// the ground.
enum MarioAccent {
  gold(Color(0xFFF2C14E), Color(0xFF8F6717), Color(0xFFF2C14E)),
  blue(Color(0xFF2F5FB5), Color(0xFF234891), Color(0xFF7FA3E3)),
  slate(Color(0xFF565D64), Color(0xFF333E51), Color(0xFFA8B0C0)),
  coral(Color(0xFFF05A47), Color(0xFFB23A2C), Color(0xFFF58B7C));

  const MarioAccent(this.base, this.text, this.lifted);

  /// Bars, icons, focus rings — anything that only needs to read against
  /// chrome rather than carry text.
  final Color base;

  /// Accent-coloured text on a LIGHT ground. The base tones are far too pale
  /// to set a word in.
  final Color text;

  /// Both roles on a DARK ground, where [text] would vanish into the navy.
  final Color lifted;

  /// The accent tone for text on the ground in play.
  Color textOn({required bool dark}) => dark ? lifted : text;

  /// The bar/icon tone for the ground in play. Only the two dark hues have
  /// to move — gold and coral already separate from navy and from black.
  Color baseOn({required bool dark}) {
    if (!dark) return base;
    return this == MarioAccent.blue || this == MarioAccent.slate
        ? lifted
        : base;
  }
}

/// How tightly the rows pack. The design ships this as a three-way choice;
/// it drives the height of every list row and the size of the text in it.
enum MarioDensity {
  compact(28, 13),
  balanced(32, 13.5),
  roomy(36, 14.5);

  const MarioDensity(this.row, this.fontSize);

  /// Row height, in logical pixels.
  final double row;

  /// The type size those rows are set in.
  final double fontSize;
}

/// Spacing scale.
///
/// A clean 4px base. The previous system ran on 4.4 — derived from the old
/// type ramp — but the Simple design lays out on whole pixels (12 / 14 / 16 /
/// 26 / 40 / 44), and a fractional base put every one of those a hair off.
class MarioSpace {
  const MarioSpace._();

  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
}

/// Corner radii.
///
/// The remodel takes the pills out. Small controls land at 5–7px and panels
/// at 10 — the design's own numbers. [pill] survives for the two things that
/// are genuinely circular: the avatar chip and the toggle.
class MarioRadius {
  const MarioRadius._();

  /// Segmented-control chips, settings rows.
  static const xs = 5.0;

  /// Search fields, the logo mark, small buttons.
  static const sm = 6.0;

  /// The ask composer, segmented-control tracks.
  static const md = 7.0;

  /// Dialogs, the command palette, cards.
  static const lg = 10.0;

  /// The avatar and the toggle. Nothing else.
  static const pill = 999.0;

  /// Kept as an alias of [lg]: the old value (32.2) belonged to the round
  /// card system the remodel replaced, and it is still named at a few sites.
  static const card = lg;
}
