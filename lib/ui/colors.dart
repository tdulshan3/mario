/// Mario color tokens for three themes:
///   - Light: warm-neutral paper white with a refined amber accent
///   - Dark:  deep neutrals, same amber accent
///   - Book:  calm sepia / cream paper, warm-brown ink (reading-focused)
///
/// Static fields preserved for code that still does `isDark ? X : Y`. New
/// code should prefer `Theme.of(context).colorScheme.*` so the active theme's
/// palette flows through automatically (including Book).
library;

import 'package:flutter/material.dart';

class MarioColors {
  const MarioColors._();

  // ── Brand ───────────────────────────────────────────────────────────────
  // Refined amber — slightly more saturated than the original yellow so
  // selection chips read clearly on both white and sepia backgrounds.
  static const primary = Color(0xFFF2C94C);
  static const primaryPressed = Color(0xFFC99B1F);

  // ── Light ───────────────────────────────────────────────────────────────
  static const surface = Color(0xFFFCFCFB);          // very subtle warm white
  static const surfaceVariant = Color(0xFFF4F2EE);   // sidebar / panel bg
  static const surfaceElevated = Color(0xFFFFFFFF);  // editor paper, cards
  static const onSurface = Color(0xFF1B1A18);
  static const onSurfaceMuted = Color(0xFF6B6862);
  static const border = Color(0xFFE5E3DD);

  // ── Dark ────────────────────────────────────────────────────────────────
  static const surfaceDark = Color(0xFF1A1A1A);
  static const surfaceVariantDark = Color(0xFF141414);
  static const surfaceElevatedDark = Color(0xFF242424);
  static const onSurfaceDark = Color(0xFFE8E6E2);
  static const onSurfaceMutedDark = Color(0xFF9B9892);
  static const borderDark = Color(0xFF2A2A28);

  // ── Book (sepia, calm reading mode) ─────────────────────────────────────
  // Inspired by aged paper + warm library lighting. Editor paper is a hair
  // lighter than the sidebar so the writing surface still feels primary.
  static const surfaceBook = Color(0xFFF7EFDF);          // cream paper
  static const surfaceVariantBook = Color(0xFFEDE3CB);   // tan sidebar
  static const surfaceElevatedBook = Color(0xFFFCF5E5);  // light page
  static const onSurfaceBook = Color(0xFF3D2E1F);        // warm dark brown ink
  static const onSurfaceMutedBook = Color(0xFF806A4F);   // medium sepia
  static const borderBook = Color(0xFFD9C9A8);           // warm tan
  static const primaryBook = Color(0xFFB97A30);          // warm amber accent
  static const primaryPressedBook = Color(0xFF8B5A1F);   // deeper amber

  // ── Notebook label palette ──────────────────────────────────────────────
  // Slightly desaturated so they sit well on the sepia surface too.
  static const labelRed = Color(0xFFE07A6E);
  static const labelOrange = Color(0xFFE89B4D);
  static const labelYellow = Color(0xFFE6B844);
  static const labelGreen = Color(0xFF7BB582);
  static const labelTeal = Color(0xFF52A89A);
  static const labelPurple = Color(0xFFA876B8);

  static const List<Color> labelPalette = [
    labelRed,
    labelOrange,
    labelYellow,
    labelGreen,
    labelTeal,
    labelPurple,
  ];
}
