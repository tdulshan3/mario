/// System tray for Linux and Windows — yellow square icon with M, context
/// menu (Open / Quit). Windows wants an `.ico`; one is written around the
/// same PNG, since an ICO may carry PNG-compressed images.
library;

import 'dart:io';
import 'dart:typed_data';
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
    final file =
        File('${dir.path}/mario_tray.${Platform.isWindows ? 'ico' : 'png'}');
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
    final paragraph = pb.build()
      ..layout(const ui.ParagraphConstraints(width: size));
    canvas.drawParagraph(paragraph, const Offset(0, 8));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return null;
    final png = bytes.buffer.asUint8List();
    await file.writeAsBytes(Platform.isWindows ? _icoAround(png) : png);
    return file.path;
  } catch (_) {
    return null;
  }
}

/// An ICO container holding one PNG image: a 6-byte header, one 16-byte
/// directory entry, then the PNG bytes verbatim. Windows has read PNG
/// entries in ICO files since Vista.
Uint8List _icoAround(Uint8List png, {int size = 64}) {
  final out = BytesBuilder();
  void u16(int v) => out.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) =>
      out.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  u16(0); // reserved
  u16(1); // type: icon
  u16(1); // one image
  out.add([size & 0xff, size & 0xff, 0, 0]); // width, height, colours, reserved
  u16(1); // colour planes
  u16(32); // bits per pixel
  u32(png.length);
  u32(6 + 16); // offset of the image data
  out.add(png);
  return out.toBytes();
}
