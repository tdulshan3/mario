/// The Material theme of the desktop builds, made from the macOS 27 tokens.
///
/// The window, sidebar, toolbar, sheets and alerts are apple_ui widgets and
/// take their colours from [AppleTheme] directly. This theme is for what is
/// still Material underneath — AppFlowy's editor and its menus, and the
/// screens that read [MarioTokens] — so that they sit in the same window
/// without a second palette: macOS label colours for text, the window
/// background for the page, the separator for every hairline, system blue
/// for the accent, and the kit's 13 px type in Inter (SF Pro on macOS).
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/material.dart';

import '../colors.dart';
import '../theme.dart';

/// The desktop theme for one appearance.
ThemeData macMaterialTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? MacColors.dark : MacColors.light;
  final tokens = macTokens(brightness);
  final solidLine = Color.alphaBlend(c.separator, c.windowBg);
  final base = dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accentBlue,
    onPrimary: c.glyphOnAccent,
    secondary: tokens.accentText,
    onSecondary: c.glyphOnAccent,
    surface: c.windowBg,
    onSurface: c.labelPrimary,
    onSurfaceVariant: c.labelSecondary,
    surfaceContainerLowest: tokens.side,
    surfaceContainerLow: tokens.side,
    surfaceContainer: c.windowBg,
    surfaceContainerHigh: c.windowBg,
    surfaceContainerHighest: tokens.side,
    outline: solidLine,
    outlineVariant: solidLine,
    error: c.accentRed,
    onError: c.white,
  );

  TextStyle kit(MacTextSpec spec, Color color, {bool bold = false}) =>
      appleFont(size: spec.size).copyWith(
        fontSize: spec.size,
        height: spec.lineHeight / spec.size,
        fontWeight: bold ? spec.emphasizedWeight : spec.weight,
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
      );

  final textTheme = base.textTheme.copyWith(
    // The page title: MacEditor's borderless 22 px bold title.
    displayLarge: kit(MacTextSpecs.title1, c.labelPrimary, bold: true),
    displayMedium: kit(MacTextSpecs.title1, c.labelPrimary, bold: true),
    displaySmall: kit(MacTextSpecs.title2, c.labelPrimary, bold: true),
    headlineLarge: kit(MacTextSpecs.title2, c.labelPrimary, bold: true),
    headlineMedium: kit(MacTextSpecs.title2, c.labelPrimary, bold: true),
    headlineSmall: kit(MacTextSpecs.title3, c.labelPrimary, bold: true),
    titleLarge: kit(MacTextSpecs.title3, c.labelPrimary, bold: true),
    titleMedium: kit(MacTextSpecs.body, c.labelPrimary, bold: true),
    titleSmall: kit(MacTextSpecs.body, c.labelPrimary, bold: true),
    bodyLarge: kit(MacTextSpecs.body, c.labelPrimary),
    bodyMedium: kit(MacTextSpecs.body, c.labelPrimary),
    bodySmall: kit(MacTextSpecs.callout, c.labelSecondary),
    labelLarge: kit(MacTextSpecs.body, c.labelPrimary),
    labelMedium: kit(MacTextSpecs.subheadline, c.labelSecondary),
    labelSmall: kit(MacTextSpecs.subheadline, c.labelSecondary, bold: true),
  );
  final body = textTheme.bodyMedium!;

  // macOS controls: 6 px corners at the regular (24 px) size.
  final controlShape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  const controlPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 4);
  const controlSize = Size(0, 24);

  InputBorder field(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color, width: width),
      );

  // Menus and tooltips float, so they take the opaque end of the Ultra Thick
  // material: Material cannot blur behind a route the way MacMenu does.
  final menuFill = Color.alphaBlend(c.materialUltrathickFill, c.windowBg);

  return base.copyWith(
    colorScheme: scheme,
    extensions: [tokens, MarioThemeMarker(mode: tokens.mode)],
    scaffoldBackgroundColor: c.windowBg,
    canvasColor: c.windowBg,
    dividerColor: solidLine,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    iconTheme: IconThemeData(color: c.labelSecondary, size: 16),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.labelPrimary,
      selectionColor: c.accentBlue.withValues(alpha: 0.3),
    ),
    // No ripples or hover washes: macOS controls do not have them.
    splashFactory: NoSplash.splashFactory,
    hoverColor: Colors.transparent,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    focusColor: c.accentBlue.withValues(alpha: 0.25),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    appBarTheme: AppBarTheme(
      backgroundColor: c.windowBg,
      foregroundColor: c.labelPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: kit(MacTextSpecs.body, c.labelPrimary, bold: true),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accentBlue,
        foregroundColor: c.glyphOnAccent,
        minimumSize: controlSize,
        padding: controlPadding,
        shape: controlShape,
        textStyle: body,
        elevation: 0,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.accentBlue,
        foregroundColor: c.glyphOnAccent,
        minimumSize: controlSize,
        padding: controlPadding,
        shape: controlShape,
        textStyle: body,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.labelPrimary,
        backgroundColor: dark ? c.fillSecondary : c.white,
        minimumSize: controlSize,
        padding: controlPadding,
        shape: controlShape,
        side: BorderSide(color: solidLine),
        textStyle: body,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accentBlue,
        minimumSize: controlSize,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        shape: controlShape,
        textStyle: body,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.labelSecondary,
        minimumSize: const Size(24, 24),
        padding: const EdgeInsets.all(4),
        iconSize: 16,
        shape: controlShape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? c.fillQuaternary : c.white,
      border: field(solidLine),
      enabledBorder: field(solidLine),
      focusedBorder: field(c.accentBlue.withValues(alpha: 0.5), 3),
      errorBorder: field(c.accentRed),
      contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      hintStyle: body.copyWith(color: c.labelTertiary),
      labelStyle: body.copyWith(color: c.labelSecondary),
      isDense: true,
    ),
    cardTheme: CardThemeData(
      color: c.windowBg,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: solidLine),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.windowBg,
      elevation: 24,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: kit(MacTextSpecs.body, c.labelPrimary, bold: true),
      contentTextStyle: body,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: menuFill,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: solidLine, width: 0.5),
      ),
      textStyle: body,
      menuPadding: const EdgeInsets.symmetric(vertical: 5),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(menuFill),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: solidLine, width: 0.5),
        )),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: menuFill,
        border: Border.all(color: solidLine, width: 0.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      textStyle: kit(MacTextSpecs.subheadline, c.labelPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      waitDuration: const Duration(milliseconds: 800),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: menuFill,
      contentTextStyle: body,
      actionTextColor: c.accentBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.fillTertiary,
      side: BorderSide.none,
      labelStyle: kit(MacTextSpecs.subheadline, c.labelSecondary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? c.accentBlue : Colors.transparent),
      checkColor: WidgetStatePropertyAll(c.glyphOnAccent),
      side: BorderSide(color: c.labelTertiary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? c.accentBlue : c.labelTertiary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(c.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? c.accentBlue : c.fillPrimary),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.accentBlue,
      inactiveTrackColor: c.fillPrimary,
      thumbColor: c.white,
      trackHeight: 4,
      overlayShape: SliderComponentShape.noOverlay,
      tickMarkShape: SliderTickMarkShape.noTickMark,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accentBlue,
      linearTrackColor: c.fillSecondary,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.scrollbarThumb),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
    ),
    dividerTheme: DividerThemeData(color: solidLine, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      dense: true,
      titleTextStyle: body,
      subtitleTextStyle: kit(MacTextSpecs.subheadline, c.labelSecondary),
      iconColor: c.labelSecondary,
      selectedColor: c.labelPrimary,
      selectedTileColor: c.fillTertiary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );
}

/// [MarioTokens] for the macOS look: the label, separator and fill colours
/// of the kit in the slots the Material screens read.
MarioTokens macTokens(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? MacColors.dark : MacColors.light;
  return MarioTokens(
    // Light and Calm night are the two grounds whose `isDark` answers match
    // the appearance; nothing on the desktop reads the ground beyond that.
    mode: dark ? MarioThemeMode.night : MarioThemeMode.light,
    accent: MarioAccent.macBlue,
    density: MarioDensity.compact,
    ink: c.labelPrimary,
    sec: c.labelSecondary,
    mut: c.labelTertiary,
    bg: c.windowBg,
    // MacSidebar's own background (kit "BG", active window).
    side: dark ? const Color(0xFF151515) : const Color(0xFFE4E4E4),
    // A document on macOS is drawn on the window background; there is no
    // card under the page.
    paper: c.windowBg,
    body: c.labelPrimary,
    line: c.separator,
    fill: c.fillSecondary,
  );
}
