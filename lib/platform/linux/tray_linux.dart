/// Linux system tray — yellow square icon with M, context menu (Open / Quit).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class _MarioTrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() => windowManager.show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();
}

final _MarioTrayListener _listener = _MarioTrayListener();

Future<void> setupLinuxTray() async {
  trayManager.addListener(_listener);
  try {
    final iconPath = await _ensureTrayIcon();
    if (iconPath != null) {
      await trayManager.setIcon(iconPath);
    }
    await trayManager.setToolTip('Mario');
    await trayManager.setContextMenu(Menu(
      items: [
        MenuItem(
          key: 'open',
          label: 'Open Mario',
          onClick: (_) => windowManager.show(),
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: 'Quit',
          onClick: (_) => exit(0),
        ),
      ],
    ));
  } catch (_) {
    // Tray is best-effort — losing it shouldn't crash the app.
  }
}

Future<String?> _ensureTrayIcon() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/mario_tray.png');
    if (await file.exists()) return file.path;

    const size = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
    final paint = Paint()..color = const Color(0xFFFFDE7A);
    final rrect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, size, size),
      const Radius.circular(12),
    );
    canvas.drawRRect(rrect, paint);

    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontWeight: FontWeight.w700,
      fontSize: 40,
      textAlign: TextAlign.center,
    ))
      ..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)))
      ..addText('M');
    final paragraph = pb.build()..layout(const ui.ParagraphConstraints(width: size));
    canvas.drawParagraph(paragraph, const Offset(0, 8));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return null;
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file.path;
  } catch (_) {
    return null;
  }
}
