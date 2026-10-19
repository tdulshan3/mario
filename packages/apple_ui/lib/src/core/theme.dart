import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'ios_tokens.dart';
import 'macos_tokens.dart';

/// Which Apple design the widgets draw.
/// [ios] = iPhone and iPad (iOS/iPadOS 27). [macos] = Mac desktop (macOS 27).
/// [AppleLook.auto] picks [macos] on desktop platforms (macOS, Windows, Linux) and [ios] on iOS, Android and the web.
enum AppleLook { ios, macos, auto }

/// Light, dark, or follow the system setting.
enum AppleThemeMode { system, light, dark }

/// Everything the widgets need to look right: look, appearance, accent colour, Dynamic Type, font.
/// Read it with `AppleTheme.of(context)`.
@immutable
class AppleThemeData {
  const AppleThemeData({
    required this.look,
    required this.brightness,
    this.accent,
    this.dynamicType,
    this.elevated = false,
  });

  /// [AppleLook.ios] or [AppleLook.macos] (never auto here: [AppleApp] resolves it).
  final AppleLook look;
  final Brightness brightness;

  /// The app tint colour. Null = system blue of the current look and appearance.
  final Color? accent;

  /// iOS text size (Dynamic Type). Null = follow the device text size setting.
  final IosDynamicType? dynamicType;

  /// Content presented above the app (sheets, popovers): [ios] returns the "Elevated" background colours, which
  /// differ from the base ones in Dark Mode. Sheets and popovers set it for their content; you don't.
  final bool elevated;

  bool get isDark => brightness == Brightness.dark;
  bool get isIos => look != AppleLook.macos;
  bool get isMac => look == AppleLook.macos;

  /// iOS/iPadOS colours for the current appearance.
  IosColors get ios {
    final base = isDark ? IosColors.dark : IosColors.light;
    return elevated ? base.elevated : base;
  }

  /// macOS colours for the current appearance.
  MacColors get mac => isDark ? MacColors.dark : MacColors.light;

  /// The tint (accent) colour actually used.
  Color get accentColor => accent ?? (isMac ? mac.accentBlue : ios.blue);

  AppleThemeData copyWith({
    AppleLook? look,
    Brightness? brightness,
    Color? accent,
    IosDynamicType? dynamicType,
    bool? elevated,
  }) =>
      AppleThemeData(
        look: look ?? this.look,
        brightness: brightness ?? this.brightness,
        accent: accent ?? this.accent,
        dynamicType: dynamicType ?? this.dynamicType,
        elevated: elevated ?? this.elevated,
      );

  @override
  bool operator ==(Object other) =>
      other is AppleThemeData &&
      other.look == look &&
      other.brightness == brightness &&
      other.accent == accent &&
      other.dynamicType == dynamicType &&
      other.elevated == elevated;

  @override
  int get hashCode => Object.hash(look, brightness, accent, dynamicType, elevated);
}

/// Provides [AppleThemeData] to the widgets below. [AppleApp] adds one for you.
class AppleTheme extends InheritedWidget {
  const AppleTheme({super.key, required this.data, required super.child});

  final AppleThemeData data;

  /// The nearest theme. Without an [AppleApp] above, a light iOS theme is assumed.
  static AppleThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<AppleTheme>();
    if (theme != null) return theme.data;
    return AppleThemeData(look: AppleLook.ios, brightness: MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light);
  }

  @override
  bool updateShouldNotify(AppleTheme oldWidget) => data != oldWidget.data;
}

/// Resolves [AppleLook.auto] for the current platform.
AppleLook resolveLook(AppleLook look) {
  if (look != AppleLook.auto) return look;
  if (kIsWeb) return AppleLook.ios;
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => AppleLook.macos,
    _ => AppleLook.ios,
  };
}

/// True on Apple platforms where the system font is SF Pro and may be used (not on the web).
bool get isAppleSystemFontAvailable =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

/// Shortcuts: `context.appleTheme`, `context.iosColors`, `context.macColors`, `context.accent`.
extension AppleThemeContext on BuildContext {
  AppleThemeData get appleTheme => AppleTheme.of(this);
  IosColors get iosColors => AppleTheme.of(this).ios;
  MacColors get macColors => AppleTheme.of(this).mac;
  Color get accent => AppleTheme.of(this).accentColor;
}
