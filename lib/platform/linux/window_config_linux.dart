/// Linux window setup — title "Mario", min 800x600, system tray-aware.
library;

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'tray_linux.dart';

Future<void> configureLinuxWindow() async {
  await windowManager.ensureInitialized();
  const opts = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(800, 600),
    center: true,
    title: 'Mario',
    // The system's own title bar and window buttons. The macOS look draws
    // everything below it, but on Linux and Windows the frame stays native.
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(opts, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await setupLinuxTray();
}
