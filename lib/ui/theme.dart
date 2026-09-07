/// MarioTheme — the four grounds of the Simple remodel.
///
///   Light       near-white ground, white paper, hairline chrome. The default.
///   White       the same, with the warmth taken out; for bright rooms.
///   Calm night  the mark's navy, full bleed.
///   Black       pure #000, for OLED.
///
/// All four share one layout, one type system and one set of shapes — only
/// the ground changes. What changed in the remodel is what *carries* the
/// layout: chrome is no longer a translucent veil floating over the ground,
/// it is a flat surface separated by a 1px rule. That single decision is why
/// the top bar fits in 43px, and why the four grounds now differ only in
/// their colour values rather than in how they are painted.
///
/// Type is Figtree throughout. Caprasimo survives at exactly one size, in
/// exactly one place — the 14px wordmark in the top-left — so it is not in
/// the text theme at all; see [MarioType.wordmark].
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Theme selector. [system] follows the OS, resolving to Light or Calm night.
enum MarioThemeMode {
  system,
  light,
  white,
  night,
  black;

  /// Whether this mode paints on a dark ground.
  bool get isDark => this == night || this == black;
}

/// The Simple design's tokens, resolved for the active ground.
///
/// Screens read these rather than picking constants off [MarioColors], so a
/// widget written once works on all four grounds. The [ColorScheme] is still
/// populated for Material's own widgets, but it has no slot for `side` versus
/// `paper`, and no slot at all for the accent's text tone — which is the
/// whole reason this exists.
class MarioTokens extends ThemeExtension<MarioTokens> {
  const MarioTokens({
    required this.mode,
    required this.accent,
    required this.density,
    required this.ink,
    required this.sec,
    required this.mut,
    required this.bg,
    required this.side,
    required this.paper,
    required this.body,
    required this.line,
    required this.fill,
  });

  final MarioThemeMode mode;
  final MarioAccent accent;
  final MarioDensity density;

  /// Headings, and the words a search matched.
  final Color ink;

  /// Secondary text — inactive tabs, sidebar rows, control labels.
  final Color sec;

  /// Muted text — placeholders, timestamps, meta, kickers.
  final Color mut;

  /// The app ground, behind the chrome.
  final Color bg;

  /// The sidebar.
  final Color side;

  /// The writing surface.
  final Color paper;

  /// Long-form copy. A touch off full [ink].
  final Color body;

  /// Every hairline in the interface.
  final Color line;

  /// The one subtle fill — search pill, avatar, segmented track.
  final Color fill;

  bool get isDark => mode.isDark;

  /// The accent's bar/icon tone for this ground.
  Color get accentBase => accent.baseOn(dark: isDark);

  /// The accent's text tone for this ground. The only accent tone that may
  /// carry a word.
  Color get accentText => accent.textOn(dark: isDark);

  /// Row height for lists and trees, from the density setting.
  double get row => density.row;

  /// The type size those rows are set in.
  double get rowFontSize => density.fontSize;

  /// A 1px [BorderSide] in the hairline tone.
  BorderSide get hairline => BorderSide(color: line, width: 1);

  @override
  MarioTokens copyWith({
    MarioThemeMode? mode,
    MarioAccent? accent,
    MarioDensity? density,
    Color? ink,
    Color? sec,
    Color? mut,
    Color? bg,
    Color? side,
    Color? paper,
    Color? body,
    Color? line,
    Color? fill,
  }) =>
      MarioTokens(
        mode: mode ?? this.mode,
        accent: accent ?? this.accent,
        density: density ?? this.density,
        ink: ink ?? this.ink,
        sec: sec ?? this.sec,
        mut: mut ?? this.mut,
        bg: bg ?? this.bg,
        side: side ?? this.side,
        paper: paper ?? this.paper,
        body: body ?? this.body,
        line: line ?? this.line,
        fill: fill ?? this.fill,
      );

  @override
  MarioTokens lerp(ThemeExtension<MarioTokens>? other, double t) {
    if (other is! MarioTokens) return this;
    // The discrete fields cannot be interpolated, so they snap at the
    // halfway point rather than being pinned to the outgoing theme — a
    // density change would otherwise not take effect until the animation
    // finished, making the whole transition look like it stuck.
    return MarioTokens(
      mode: t < 0.5 ? mode : other.mode,
      accent: t < 0.5 ? accent : other.accent,
      density: t < 0.5 ? density : other.density,
      ink: Color.lerp(ink, other.ink, t)!,
      sec: Color.lerp(sec, other.sec, t)!,
      mut: Color.lerp(mut, other.mut, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      side: Color.lerp(side, other.side, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      body: Color.lerp(body, other.body, t)!,
      line: Color.lerp(line, other.line, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
    );
  }
}

/// The active design tokens. Falls back to Light so a bare `MaterialApp` in a
/// widget test still renders.
MarioTokens marioTokens(BuildContext context) =>
    Theme.of(context).extension<MarioTokens>() ?? _lightTokens;

const _lightTokens = MarioTokens(
  mode: MarioThemeMode.light,
  accent: MarioAccent.gold,
  density: MarioDensity.balanced,
  ink: MarioColors.ink,
  sec: MarioColors.sec,
  mut: MarioColors.mut,
  bg: MarioColors.bg,
  side: MarioColors.side,
  paper: MarioColors.paper,
  body: MarioColors.body,
  line: MarioColors.line,
  fill: MarioColors.fill,
);

/// Type that sits outside the text theme.
class MarioType {
  const MarioType._();

  /// The wordmark, and the only Caprasimo left in the interface. The design
  /// sets it at 14/1.0 with a hair of tracking, beside a 20px mark.
  static TextStyle wordmark(Color color) => GoogleFonts.caprasimo(
        color: color,
        fontSize: 14,
        height: 1,
        letterSpacing: 0.01 * 14,
      );
}

class MarioTheme {
  const MarioTheme._();

  static ThemeData light({
    MarioAccent accent = MarioAccent.gold,
    MarioDensity density = MarioDensity.balanced,
  }) =>
      of(mode: MarioThemeMode.light, accent: accent, density: density);

  static ThemeData white({
    MarioAccent accent = MarioAccent.gold,
    MarioDensity density = MarioDensity.balanced,
  }) =>
      of(mode: MarioThemeMode.white, accent: accent, density: density);

  static ThemeData night({
    MarioAccent accent = MarioAccent.gold,
    MarioDensity density = MarioDensity.balanced,
  }) =>
      of(mode: MarioThemeMode.night, accent: accent, density: density);

  static ThemeData black({
    MarioAccent accent = MarioAccent.gold,
    MarioDensity density = MarioDensity.balanced,
  }) =>
      of(mode: MarioThemeMode.black, accent: accent, density: density);

  /// The four grounds, from one builder — so a change to shape or type lands
  /// everywhere at once and they cannot drift apart.
  static ThemeData of({
    required MarioThemeMode mode,
    MarioAccent accent = MarioAccent.gold,
    MarioDensity density = MarioDensity.balanced,
  }) {
    final resolved =
        mode == MarioThemeMode.system ? MarioThemeMode.light : mode;
    final tokens = _tokensFor(resolved, accent, density);
    return _build(tokens);
  }

  static MarioTokens _tokensFor(
    MarioThemeMode mode,
    MarioAccent accent,
    MarioDensity density,
  ) {
    switch (mode) {
      case MarioThemeMode.white:
        return MarioTokens(
          mode: mode,
          accent: accent,
          density: density,
          ink: MarioColors.inkWhite,
          sec: MarioColors.secWhite,
          mut: MarioColors.mutWhite,
          bg: MarioColors.bgWhite,
          side: MarioColors.sideWhite,
          paper: MarioColors.paperWhite,
          body: MarioColors.bodyWhite,
          line: MarioColors.line,
          fill: MarioColors.fill,
        );
      case MarioThemeMode.night:
        return MarioTokens(
          mode: mode,
          accent: accent,
          density: density,
          ink: MarioColors.inkNight,
          sec: MarioColors.secNight,
          mut: MarioColors.mutNight,
          bg: MarioColors.bgNight,
          side: MarioColors.sideNight,
          paper: MarioColors.paperNight,
          body: MarioColors.bodyNight,
          line: MarioColors.lineNight,
          fill: MarioColors.fillNight,
        );
      case MarioThemeMode.black:
        return MarioTokens(
          mode: mode,
          accent: accent,
          density: density,
          ink: MarioColors.inkBlack,
          sec: MarioColors.secBlack,
          mut: MarioColors.mutBlack,
          bg: MarioColors.bgBlack,
          side: MarioColors.sideBlack,
          paper: MarioColors.paperBlack,
          body: MarioColors.bodyBlack,
          line: MarioColors.lineBlack,
          fill: MarioColors.fillBlack,
        );
      case MarioThemeMode.light:
      case MarioThemeMode.system:
        return MarioTokens(
          mode: MarioThemeMode.light,
          accent: accent,
          density: density,
          ink: MarioColors.ink,
          sec: MarioColors.sec,
          mut: MarioColors.mut,
          bg: MarioColors.bg,
          side: MarioColors.side,
          paper: MarioColors.paper,
          body: MarioColors.body,
          line: MarioColors.line,
          fill: MarioColors.fill,
        );
    }
  }

  static ThemeData _build(MarioTokens t) {
    final brightness = t.isDark ? Brightness.dark : Brightness.light;
    final base = t.isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    // The hairline is an alpha over the ground; Material composites some of
    // its own chrome against an OPAQUE outline, where a 10% ink reads as
    // near-invisible. Flattening it once here keeps both paths matching.
    final solidLine = Color.alphaBlend(t.line, t.bg);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: t.accentBase,
      onPrimary: t.isDark ? MarioColors.navy : MarioColors.onPrimary,
      secondary: t.accentText,
      onSecondary: t.paper,
      surface: t.bg,
      onSurface: t.ink,
      onSurfaceVariant: t.sec,
      surfaceContainerLowest: t.side,
      surfaceContainerHighest: t.side,
      surfaceContainerHigh: t.paper,
      surfaceContainer: t.paper,
      outline: solidLine,
      outlineVariant: solidLine,
      error: t.isDark ? const Color(0xFFF58B7C) : const Color(0xFFB23A2C),
      onError: t.isDark ? MarioColors.navy : Colors.white,
    );

    final textTheme = _textTheme(base.textTheme, t);

    // Nothing is a pill any more. Small controls sit at 6px.
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MarioRadius.sm),
    );
    final buttonLabel = GoogleFonts.figtree(
      fontSize: 12.5,
      height: 1,
      fontWeight: FontWeight.w600,
    );
    const buttonPadding = EdgeInsets.symmetric(
        horizontal: MarioSpace.x3, vertical: MarioSpace.x2);

    InputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(MarioRadius.sm),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      colorScheme: scheme,
      extensions: [t, MarioThemeMarker(mode: t.mode)],
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      dividerColor: solidLine,
      textTheme: textTheme,
      iconTheme: IconThemeData(color: t.sec, size: 18),
      appBarTheme: AppBarTheme(
        backgroundColor: t.bg,
        foregroundColor: t.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.figtree(
          color: t.ink,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accentBase,
          foregroundColor: MarioColors.navy,
          elevation: 0,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonLabel,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accentBase,
          foregroundColor: MarioColors.navy,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonLabel,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.ink,
          padding: buttonPadding,
          shape: buttonShape,
          side: BorderSide(color: solidLine),
          textStyle: buttonLabel,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          // Text buttons are the design's inline actions ("Insert below",
          // "Ask again"), which are set in the deep accent, not the base.
          foregroundColor: t.accentText,
          padding: const EdgeInsets.symmetric(horizontal: MarioSpace.x2),
          shape: buttonShape,
          textStyle: buttonLabel,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.fill,
        border: inputBorder(Colors.transparent),
        enabledBorder: inputBorder(Colors.transparent),
        focusedBorder: inputBorder(t.accentBase, 1.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        hintStyle: GoogleFonts.figtree(fontSize: 12.5, color: t.mut),
        isDense: true,
      ),
      cardTheme: CardThemeData(
        color: t.paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarioRadius.lg),
          side: BorderSide(color: solidLine),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarioRadius.lg),
          side: BorderSide(color: solidLine),
        ),
        titleTextStyle: GoogleFonts.figtree(
          color: t.ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: GoogleFonts.figtree(
          color: t.body,
          fontSize: 13.5,
          height: 1.55,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.fill,
        side: BorderSide(color: solidLine),
        labelStyle: GoogleFonts.figtree(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: t.sec,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarioRadius.xs),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? t.accentBase
                : Colors.transparent),
        checkColor: WidgetStateProperty.all(MarioColors.navy),
        side: BorderSide(color: solidLine),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.accentBase : solidLine),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(t.paper),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.accentBase : t.fill),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? t.accentBase : solidLine),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: t.sec,
        inactiveTrackColor: solidLine,
        thumbColor: t.paper,
        trackHeight: 3,
        overlayShape: SliderComponentShape.noOverlay,
        // The artboard's slider is a plain two-tone track. Flutter draws a
        // tick per division on top of it by default, which reads as grit.
        tickMarkShape: SliderTickMarkShape.noTickMark,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accentBase),
      dividerTheme: DividerThemeData(color: solidLine, thickness: 1, space: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: t.ink,
          borderRadius: BorderRadius.circular(MarioRadius.sm),
        ),
        textStyle: GoogleFonts.figtree(fontSize: 11.5, color: t.bg),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.paper,
        contentTextStyle: GoogleFonts.figtree(fontSize: 13, color: t.ink),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarioRadius.md),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarioRadius.md),
          side: BorderSide(color: solidLine),
        ),
        textStyle: GoogleFonts.figtree(fontSize: 13, color: t.ink),
      ),
    );
  }

  /// Figtree, throughout.
  ///
  /// The ramp is the design's: 31 / 24 / 20 for headings — all set in the
  /// body face at w600 with a touch of negative tracking, not in the display
  /// face — then 15 for the page, 14.5 for AI copy and list titles, 13.5 for
  /// rows, 12.5 for meta, and 10.5 caps for kickers.
  static TextTheme _textTheme(TextTheme base, MarioTokens t) {
    final body = GoogleFonts.figtreeTextTheme(base).apply(
      bodyColor: t.ink,
      displayColor: t.ink,
    );

    TextStyle heading(double size) => GoogleFonts.figtree(
          color: t.ink,
          fontSize: size,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01 * size,
        );

    return body.copyWith(
      // The page title.
      displayLarge: heading(31),
      // "Recent" — the home heading.
      displayMedium: heading(24),
      // A settings pane heading.
      displaySmall: heading(20),
      headlineMedium: heading(18),
      headlineSmall: heading(16),
      titleLarge: heading(15),
      // A list-row title.
      titleMedium: GoogleFonts.figtree(
        color: t.ink,
        fontSize: 14.5,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: GoogleFonts.figtree(
        color: t.ink,
        fontSize: 13.5,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      // Page copy.
      bodyLarge: GoogleFonts.figtree(color: t.body, fontSize: 15, height: 1.62),
      // AI copy.
      bodyMedium:
          GoogleFonts.figtree(color: t.body, fontSize: 14.5, height: 1.6),
      bodySmall: GoogleFonts.figtree(color: t.sec, fontSize: 13, height: 1.5),
      // A sidebar or tree row.
      labelLarge: GoogleFonts.figtree(
        color: t.ink,
        fontSize: 13.5,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
      // Meta, timestamps, control labels.
      labelMedium:
          GoogleFonts.figtree(color: t.mut, fontSize: 12.5, height: 1.2),
      // The uppercase kicker.
      labelSmall: GoogleFonts.figtree(
        color: t.mut,
        fontSize: 10.5,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1 * 10.5,
      ),
    );
  }
}

/// Carries the active [MarioThemeMode] so widgets can branch on the ground
/// without comparing colours — Light and White are both `Brightness.light`,
/// and Night and Black are both dark, so brightness alone cannot tell them
/// apart.
class MarioThemeMarker extends ThemeExtension<MarioThemeMarker> {
  const MarioThemeMarker({required this.mode});

  final MarioThemeMode mode;

  /// Black paints on #000, where a drop shadow is invisible; depth there is
  /// the alpha step off the ground instead.
  bool get usesAlphaElevation => mode == MarioThemeMode.black;

  @override
  MarioThemeMarker copyWith({MarioThemeMode? mode}) =>
      MarioThemeMarker(mode: mode ?? this.mode);

  @override
  MarioThemeMarker lerp(ThemeExtension<MarioThemeMarker>? other, double t) =>
      other is MarioThemeMarker ? other : this;
}

/// The active ground. Falls back to Light when no marker is installed (a bare
/// `MaterialApp` in a widget test, say).
MarioThemeMode marioMode(BuildContext context) =>
    Theme.of(context).extension<MarioThemeMarker>()?.mode ??
    MarioThemeMode.light;

/// The rule a Markdown preview draws — under a level-1 heading, and as the
/// horizontal rule itself. VS Code paints both at 18% of the text colour, in
/// light and dark alike: a step quieter than a border, a step louder than a
/// hairline, and the same on every ground because it is derived from the ink.
Color markdownRuleColor(ColorScheme scheme) =>
    scheme.onSurface.withValues(alpha: 0.18);
