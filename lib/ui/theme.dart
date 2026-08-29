/// MarioTheme — the four grounds of the redesign, built on the mark's palette.
///
///   Light       cream ground, translucent chrome, solid paper. The default.
///   White       for bright rooms and printing; the cream drops out.
///   Calm night  the mark's navy, full bleed. Lower contrast than Black.
///   Black       pure #000 with white-alpha glass and no shadows. For OLED.
///
/// All four share one layout, one type system and one set of shapes — only the
/// ground changes. Type is Caprasimo (display) over Figtree (body); small
/// controls are pills, paper and dialogs stay soft.
///
/// The primary is gold on every ground — it is light enough to read on navy
/// and on black without shifting. Only the blue second accent lifts a ramp
/// step on the dark grounds, where the full-strength blue sits too close to
/// the navy ink to separate from it.
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

class MarioTheme {
  const MarioTheme._();

  static ThemeData light() => _build(
        mode: MarioThemeMode.light,
        brightness: Brightness.light,
        primary: MarioColors.primary,
        secondary: MarioColors.secondary,
        onAccent: MarioColors.onPrimary,
        surface: MarioColors.surface,
        chrome: MarioColors.surfaceVariant,
        paper: MarioColors.surfaceElevated,
        onSurface: MarioColors.onSurface,
        onSurfaceMuted: MarioColors.onSurfaceMuted,
        border: MarioColors.border,
      );

  static ThemeData white() => _build(
        mode: MarioThemeMode.white,
        brightness: Brightness.light,
        primary: MarioColors.primary,
        secondary: MarioColors.secondary,
        onAccent: MarioColors.onPrimary,
        surface: MarioColors.surfaceWhite,
        chrome: MarioColors.surfaceVariantWhite,
        paper: MarioColors.surfaceElevatedWhite,
        onSurface: MarioColors.onSurfaceWhite,
        onSurfaceMuted: MarioColors.onSurfaceMutedWhite,
        border: MarioColors.borderWhite,
      );

  static ThemeData night() => _build(
        mode: MarioThemeMode.night,
        brightness: Brightness.dark,
        primary: MarioColors.primaryDark,
        secondary: MarioColors.secondaryDark,
        onAccent: MarioColors.onPrimary,
        surface: MarioColors.surfaceDark,
        chrome: MarioColors.surfaceVariantDark,
        paper: MarioColors.surfaceElevatedDark,
        onSurface: MarioColors.onSurfaceDark,
        onSurfaceMuted: MarioColors.onSurfaceMutedDark,
        border: MarioColors.borderDark,
      );

  static ThemeData black() => _build(
        mode: MarioThemeMode.black,
        brightness: Brightness.dark,
        primary: MarioColors.primaryDark,
        secondary: MarioColors.secondaryDark,
        onAccent: MarioColors.onPrimary,
        surface: MarioColors.surfaceBlack,
        chrome: MarioColors.surfaceVariantBlack,
        paper: MarioColors.surfaceElevatedBlack,
        onSurface: MarioColors.onSurfaceBlack,
        onSurfaceMuted: MarioColors.onSurfaceMutedBlack,
        border: MarioColors.borderBlack,
      );

  /// One builder for all four, so a change to shape or type lands everywhere
  /// at once and the grounds cannot drift apart.
  static ThemeData _build({
    required MarioThemeMode mode,
    required Brightness brightness,
    required Color primary,
    required Color secondary,
    required Color onAccent,
    required Color surface,
    required Color chrome,
    required Color paper,
    required Color onSurface,
    required Color onSurfaceMuted,
    required Color border,
  }) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onAccent,
      secondary: secondary,
      onSecondary: MarioColors.neutral100,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceMuted,
      surfaceContainerHighest: chrome,
      surfaceContainerHigh: paper,
      outline: border,
      outlineVariant: border,
      error: brightness == Brightness.dark
          ? MarioColors.accent300
          : MarioColors.accent700,
      onError: brightness == Brightness.dark
          ? MarioColors.navy
          : MarioColors.neutral100,
    );

    final textTheme = _textTheme(base.textTheme, onSurface);

    // Pill everything small; the design puts buttons in the display face.
    final buttonShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MarioRadius.pill));
    final buttonLabel = GoogleFonts.caprasimo(fontSize: 14, height: 1.2);
    const buttonPadding = EdgeInsets.symmetric(
        horizontal: MarioSpace.x4, vertical: MarioSpace.x2);

    return base.copyWith(
      colorScheme: scheme,
      extensions: [MarioThemeMarker(mode: mode)],
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      dividerColor: border,
      textTheme: textTheme,
      iconTheme: IconThemeData(color: onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.caprasimo(color: onSurface, fontSize: 21),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onAccent,
          elevation: 0,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonLabel,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onAccent,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonLabel,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          padding: buttonPadding,
          shape: buttonShape,
          side: BorderSide(color: border),
          textStyle: buttonLabel,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: MarioSpace.x2),
          shape: buttonShape,
          textStyle: buttonLabel,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: chrome,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MarioRadius.pill),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MarioRadius.pill),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MarioRadius.pill),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        hintStyle: GoogleFonts.figtree(fontSize: 14, color: onSurfaceMuted),
      ),
      cardTheme: CardThemeData(
        color: paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarioRadius.card),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: chrome,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarioRadius.card),
        ),
        titleTextStyle: GoogleFonts.caprasimo(color: onSurface, fontSize: 20),
        contentTextStyle:
            GoogleFonts.figtree(color: onSurface, fontSize: 14, height: 1.55),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: chrome,
        side: BorderSide(color: border),
        labelStyle: GoogleFonts.figtree(
            fontSize: 11, fontWeight: FontWeight.w600, color: onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarioRadius.pill),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : Colors.transparent),
        checkColor: WidgetStateProperty.all(onAccent),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarioRadius.sm * 0.75),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : border),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? onAccent : paper),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : chrome),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: onSurface,
          borderRadius: BorderRadius.circular(MarioRadius.sm),
        ),
        textStyle: GoogleFonts.figtree(fontSize: 12, color: surface),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: paper,
        contentTextStyle: GoogleFonts.figtree(fontSize: 14, color: onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarioRadius.md),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Figtree for reading, Caprasimo for the display sizes.
  ///
  /// The ramp is the design's: 42 / 32 / 25 / 20 / 16 / 13, with the smallest
  /// step set in caps and tracked out — it is a label, not a heading.
  static TextTheme _textTheme(TextTheme base, Color color) {
    final body = GoogleFonts.figtreeTextTheme(base).apply(
      bodyColor: color,
      displayColor: color,
    );
    TextStyle display(double size) =>
        GoogleFonts.caprasimo(color: color, fontSize: size, height: 1.12);

    return body.copyWith(
      displayLarge: display(42),
      displayMedium: display(32),
      displaySmall: display(25),
      headlineMedium: display(20),
      headlineSmall: display(17),
      titleLarge: display(16),
      bodyLarge: GoogleFonts.figtree(color: color, fontSize: 16, height: 1.6),
      bodyMedium: GoogleFonts.figtree(color: color, fontSize: 15, height: 1.55),
      bodySmall: GoogleFonts.figtree(color: color, fontSize: 13, height: 1.5),
      labelLarge: GoogleFonts.figtree(
          color: color, fontSize: 14, fontWeight: FontWeight.w600),
      labelSmall: GoogleFonts.figtree(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.08 * 11,
      ),
    );
  }
}

/// Carries the active [MarioThemeMode] so widgets can branch on the ground
/// without comparing colours — Light and White are both `Brightness.light`,
/// and Night and Black are both dark, so brightness alone cannot tell them
/// apart. Black in particular needs to know it has no shadows to draw with.
class MarioThemeMarker extends ThemeExtension<MarioThemeMarker> {
  const MarioThemeMarker({required this.mode});

  final MarioThemeMode mode;

  /// Black uses an alpha step off #000 as its elevation; a drop shadow is
  /// invisible there, so shadow-based elevation has to be skipped.
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
