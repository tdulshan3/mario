/// Which look this build draws, and the scope that gives the macOS one to
/// everything below the app.
///
/// The native desktop builds (Linux, Windows, macOS) draw Apple's macOS 27
/// kit through the vendored `apple_ui` package: a window with a sidebar, a
/// unified toolbar, an inspector, sheets and alerts. The web keeps the
/// Material "Simple" UI for now. Widget tests run as Android unless they
/// override `debugDefaultTargetPlatformOverride`, so the existing tests keep
/// exercising the Material path.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// True on the native desktop builds, which draw the macOS look.
///
/// A getter rather than a constant so a test can flip it with
/// `debugDefaultTargetPlatformOverride`.
bool get useMacLook {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.windows ||
    TargetPlatform.macOS =>
      true,
    _ => false,
  };
}

/// The macOS appearance for a stored theme choice.
///
/// macOS has two appearances and an Auto that follows the system, so the
/// four grounds fold onto them: White joins Light and Black joins Dark. The
/// stored value is left alone, so the web build still shows the ground that
/// was picked there.
ThemeMode macThemeModeFor(MarioThemeMode mode) => switch (mode) {
      MarioThemeMode.system => ThemeMode.system,
      MarioThemeMode.light || MarioThemeMode.white => ThemeMode.light,
      MarioThemeMode.night || MarioThemeMode.black => ThemeMode.dark,
    };

/// Puts [AppleTheme] (macOS look) under the app, following the Material
/// theme's brightness so both systems always agree on Light or Dark.
///
/// Used as `MaterialApp.builder`: the Material theme still has to exist —
/// AppFlowy's editor, its menus and a few dialogs are Material widgets — and
/// it is built from the same macOS tokens (see `mac_theme.dart`).
class MacLookScope extends StatelessWidget {
  const MacLookScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = AppleThemeData(
      look: AppleLook.macos,
      brightness: Theme.of(context).brightness,
    );
    return AppleTheme(
      data: data,
      child: Builder(
        builder: (context) => DefaultTextStyle(
          style: MacTypography.of(context).body,
          child: child,
        ),
      ),
    );
  }
}
