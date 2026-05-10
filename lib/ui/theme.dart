/// MarioTheme — three ThemeData factories (Light, Dark, Book) and a custom
/// [MarioThemeMode] enum that extends Flutter's system/light/dark with a
/// fourth "book" option.
///
/// All themes share Inter (body) + Space Grotesk (display), tightly-spaced
/// pill buttons, and rounded inputs. The Book theme swaps the underlying
/// surface palette for a sepia / cream paper feel — calmer for long reading
/// or writing sessions.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Theme selector — extends Flutter's [ThemeMode] with a [book] case.
enum MarioThemeMode {
  system,
  light,
  dark,
  book;

  /// Whether the Book theme is currently selected (regardless of system mode).
  bool get isBook => this == MarioThemeMode.book;
}

class MarioTheme {
  const MarioTheme._();

  /// Reading-focused sepia / cream palette. Identified at runtime by
  /// `Theme.of(context).extension<MarioThemeMarker>()?.isBook == true`.
  static ThemeData book() {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = _textTheme(base.textTheme, MarioColors.onSurfaceBook);
    return base.copyWith(
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: MarioColors.primaryBook,
        onPrimary: MarioColors.surfaceElevatedBook,
        secondary: MarioColors.primaryPressedBook,
        onSecondary: MarioColors.surfaceElevatedBook,
        surface: MarioColors.surfaceBook,
        onSurface: MarioColors.onSurfaceBook,
        onSurfaceVariant: MarioColors.onSurfaceMutedBook,
        surfaceContainerHighest: MarioColors.surfaceVariantBook,
        surfaceContainerHigh: MarioColors.surfaceElevatedBook,
        outline: MarioColors.borderBook,
        outlineVariant: MarioColors.borderBook,
        error: Color(0xFFA84C3D),
        onError: MarioColors.surfaceElevatedBook,
      ),
      extensions: const [MarioThemeMarker(isBook: true)],
      scaffoldBackgroundColor: MarioColors.surfaceBook,
      canvasColor: MarioColors.surfaceBook,
      dividerColor: MarioColors.borderBook,
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: MarioColors.onSurfaceBook),
      appBarTheme: AppBarTheme(
        backgroundColor: MarioColors.surfaceBook,
        foregroundColor: MarioColors.onSurfaceBook,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          color: MarioColors.onSurfaceBook,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MarioColors.primaryBook,
          foregroundColor: MarioColors.surfaceElevatedBook,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MarioColors.onSurfaceBook,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MarioColors.borderBook),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: MarioColors.primaryBook, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? MarioColors.primaryBook
                : Colors.transparent),
        checkColor:
            WidgetStateProperty.all(MarioColors.surfaceElevatedBook),
        side: const BorderSide(color: MarioColors.borderBook),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MarioColors.primaryBook,
      ),
      dividerTheme: const DividerThemeData(
        color: MarioColors.borderBook,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = _textTheme(base.textTheme, MarioColors.onSurface);
    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: MarioColors.primary,
        onPrimary: MarioColors.onSurface,
        secondary: MarioColors.primaryPressed,
        onSecondary: MarioColors.onSurface,
        surface: MarioColors.surface,
        onSurface: MarioColors.onSurface,
        onSurfaceVariant: MarioColors.onSurfaceMuted,
        surfaceContainerHighest: MarioColors.surfaceVariant,
        surfaceContainerHigh: MarioColors.surfaceElevated,
        outline: MarioColors.border,
        outlineVariant: MarioColors.border,
        error: Color(0xFFB3261E),
        onError: Colors.white,
      ),
      extensions: const [MarioThemeMarker(isBook: false)],
      scaffoldBackgroundColor: MarioColors.surface,
      canvasColor: MarioColors.surface,
      dividerColor: MarioColors.border,
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: MarioColors.onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: MarioColors.surface,
        foregroundColor: MarioColors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          color: MarioColors.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MarioColors.primary,
          foregroundColor: MarioColors.onSurface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MarioColors.onSurface,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MarioColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MarioColors.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? MarioColors.primary
                : Colors.transparent),
        checkColor: WidgetStateProperty.all(MarioColors.onSurface),
        side: const BorderSide(color: MarioColors.border),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MarioColors.primary,
      ),
      dividerTheme: const DividerThemeData(
        color: MarioColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = _textTheme(base.textTheme, MarioColors.onSurfaceDark);
    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: MarioColors.primary,
        onPrimary: Color(0xFF1A1A1A),
        secondary: MarioColors.primaryPressed,
        onSecondary: Color(0xFF1A1A1A),
        surface: MarioColors.surfaceDark,
        onSurface: MarioColors.onSurfaceDark,
        onSurfaceVariant: MarioColors.onSurfaceMutedDark,
        surfaceContainerHighest: MarioColors.surfaceVariantDark,
        surfaceContainerHigh: MarioColors.surfaceElevatedDark,
        outline: MarioColors.borderDark,
        outlineVariant: MarioColors.borderDark,
        error: Color(0xFFF2B8B5),
        onError: Color(0xFF1A1A1A),
      ),
      extensions: const [MarioThemeMarker(isBook: false)],
      scaffoldBackgroundColor: MarioColors.surfaceDark,
      canvasColor: MarioColors.surfaceDark,
      dividerColor: MarioColors.borderDark,
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: MarioColors.onSurfaceDark),
      appBarTheme: AppBarTheme(
        backgroundColor: MarioColors.surfaceDark,
        foregroundColor: MarioColors.onSurfaceDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          color: MarioColors.onSurfaceDark,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MarioColors.primary,
          foregroundColor: const Color(0xFF1A1A1A),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MarioColors.onSurfaceDark,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MarioColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: MarioColors.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? MarioColors.primary
                : Colors.transparent),
        checkColor: WidgetStateProperty.all(const Color(0xFF1A1A1A)),
        side: const BorderSide(color: MarioColors.borderDark),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: MarioColors.primary,
      ),
      dividerTheme: const DividerThemeData(
        color: MarioColors.borderDark,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, Color color) {
    final body = GoogleFonts.interTextTheme(base).apply(
      bodyColor: color,
      displayColor: color,
    );
    return body.copyWith(
      displayLarge: GoogleFonts.spaceGrotesk(
          color: color, fontSize: 32, fontWeight: FontWeight.w700),
      displayMedium: GoogleFonts.spaceGrotesk(
          color: color, fontSize: 26, fontWeight: FontWeight.w700),
      displaySmall: GoogleFonts.spaceGrotesk(
          color: color, fontSize: 22, fontWeight: FontWeight.w600),
      headlineMedium: GoogleFonts.spaceGrotesk(
          color: color, fontSize: 18, fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.spaceGrotesk(
          color: color, fontSize: 16, fontWeight: FontWeight.w600),
    );
  }
}

/// Tiny ThemeExtension that lets widgets check whether the Book palette is
/// active without comparing colors. Useful for the rare case where Book and
/// Light share the same `Brightness.light` but need different rendering.
class MarioThemeMarker extends ThemeExtension<MarioThemeMarker> {
  const MarioThemeMarker({required this.isBook});
  final bool isBook;

  @override
  MarioThemeMarker copyWith({bool? isBook}) =>
      MarioThemeMarker(isBook: isBook ?? this.isBook);

  @override
  MarioThemeMarker lerp(ThemeExtension<MarioThemeMarker>? other, double t) =>
      other is MarioThemeMarker ? other : this;
}

/// Convenience: true when the active theme is the Book palette.
bool isBookTheme(BuildContext context) =>
    Theme.of(context).extension<MarioThemeMarker>()?.isBook ?? false;
