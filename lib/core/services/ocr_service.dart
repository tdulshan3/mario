/// OcrService — abstract image-to-text. Linux uses tesseract subprocess; web is a stub.
abstract class OcrService {
  /// Returns extracted lines, or empty list if unavailable / no text found.
  Future<List<String>> extractText(String imagePath);

  /// Whether this platform implementation can perform OCR right now.
  bool get isAvailable;
}
