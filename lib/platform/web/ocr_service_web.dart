/// Web OcrService — graceful stub. Could route to a Cloud Vision Cloud Function later.
import '../../core/services/ocr_service.dart';

class OcrServiceWeb implements OcrService {
  @override
  bool get isAvailable => false;

  @override
  Future<List<String>> extractText(String imagePath) async => const [];
}
