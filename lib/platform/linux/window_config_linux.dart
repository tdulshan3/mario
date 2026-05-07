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
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(opts, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await setupLinuxTray();
}
