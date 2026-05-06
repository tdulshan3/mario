/// MarioTheme — light + dark ThemeData using Inter (body) + Space Grotesk (display).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

class MarioTheme {
  const MarioTheme._();

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
        surfaceContainerHighest: MarioColors.surfaceVariant,
        outline: MarioColors.border,
        error: Color(0xFFB3261E),
        onError: Colors.white,
      ),
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
        surfaceContainerHighest: MarioColors.surfaceVariantDark,
        outline: MarioColors.borderDark,
        error: Color(0xFFF2B8B5),
        onError: Color(0xFF1A1A1A),
      ),
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
