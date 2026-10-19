/// The window frame around the macOS look.
///
/// Linux and Windows keep their system title bar and window buttons
/// (`TitleBarStyle.normal` in `window_config_linux.dart`), so the look draws
/// no traffic lights there and leaves moving the window to the system.
///
/// macOS draws its own lights over a transparent title bar
/// (`macos/Runner/MainFlutterWindow.swift`), so there the window keeps their
/// room free and lets the empty parts of its toolbar move the window.
library;

import 'package:apple_ui/apple_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

bool get _isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// On macOS, the room for the system's traffic lights. Null everywhere else,
/// where the system title bar carries the window buttons.
Widget? macWindowLights() => _isMacOS ? const MacWindowControls.space() : null;

/// Lets the empty parts of a title bar move the window on macOS, whose
/// content runs under the transparent title bar. Elsewhere the system title
/// bar does that, and this is just [child].
///
/// Pan only. window_manager's `DragToMoveArea` also listens for a double
/// tap, and a double-tap recogniser holds every single click in the bar for
/// the double-tap timeout — so each toolbar button would answer a beat late.
class MacWindowDragArea extends StatelessWidget {
  const MacWindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!_isMacOS) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: child,
    );
  }
}
