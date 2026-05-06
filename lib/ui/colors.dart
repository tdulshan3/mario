/// Mario color tokens — yellow primary on neutral surfaces, light + dark.
import 'package:flutter/material.dart';

class MarioColors {
  const MarioColors._();

  // Brand
  static const primary = Color(0xFFFFDE7A);
  static const primaryPressed = Color(0xFFD4A800);

  // Light
  static const surface = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFF5F5F0);
  static const onSurface = Color(0xFF1A1A1A);
  static const onSurfaceMuted = Color(0xFF6B6B6B);
  static const border = Color(0xFFE0E0DA);

  // Dark
  static const surfaceDark = Color(0xFF1E1E1E);
  static const surfaceVariantDark = Color(0xFF161616);
  static const onSurfaceDark = Color(0xFFF0EFE8);
  static const onSurfaceMutedDark = Color(0xFF9A9A95);
  static const borderDark = Color(0xFF2A2A2A);

  // Notebook label palette (6 presets)
  static const labelRed = Color(0xFFE57373);
  static const labelOrange = Color(0xFFFFB74D);
  static const labelYellow = Color(0xFFFFDE7A);
  static const labelGreen = Color(0xFF81C784);
  static const labelTeal = Color(0xFF4DB6AC);
  static const labelPurple = Color(0xFFBA68C8);

  static const List<Color> labelPalette = [
    labelRed,
    labelOrange,
    labelYellow,
    labelGreen,
    labelTeal,
    labelPurple,
  ];
}
