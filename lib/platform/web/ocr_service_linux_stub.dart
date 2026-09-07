/// Web stub for the Linux-only [OcrServiceLinux].
///
/// Same reason as `auth_service_linux_stub.dart`: the branch is unreachable
/// in a browser, but it still has to compile. Real web OCR, if it ever
/// arrives, belongs in [OcrServiceWeb].
library;

import '../../core/services/ocr_service.dart';

class OcrServiceLinux implements OcrService {
  @override
  bool get isAvailable => false;

  @override
  Future<List<String>> extractText(String imagePath) async => const [];
}
