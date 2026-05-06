/// Linux OcrService — runs `tesseract <path> stdout` and splits on newlines.
import 'dart:io';

import '../../core/services/ocr_service.dart';

class OcrServiceLinux implements OcrService {
  bool? _checked;

  @override
  bool get isAvailable {
    if (_checked != null) return _checked!;
    try {
      final r = Process.runSync('which', ['tesseract']);
      _checked = r.exitCode == 0;
    } catch (_) {
      _checked = false;
    }
    return _checked!;
  }

  @override
  Future<List<String>> extractText(String imagePath) async {
    if (!isAvailable) return const [];
    final r = await Process.run(
      'tesseract',
      [imagePath, 'stdout', '--oem', '3', '--psm', '3'],
    );
    if (r.exitCode != 0) return const [];
    return (r.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
  }
}
