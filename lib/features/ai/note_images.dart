/// Getting the pictures in a note to the model.
///
/// A page can carry a photographed slide, a diagram, a screenshot of a formula
/// — often the densest content on it. Two routes get that to a model, and the
/// right one depends on the backend:
///
///  * **Vision.** Send the image itself. Best, but only where the server
///    accepts image parts *and* the loaded model can see; a text-only model
///    given a picture either errors or answers confidently about nothing.
///  * **OCR.** Run the text out of it on this machine and send that. Works with
///    every backend, works offline, and is often enough — a slide is mostly
///    words. Mario already OCRs images when the block is on screen; this fills
///    in the ones that were never looked at.
///
/// Both are used together where possible: the OCR text goes in the prompt as
/// context even when the image is attached, because a model reading a blurry
/// photo does better with the text beside it than without.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/services/ai/json_coercion.dart';
import '../../core/services/ai/llm_types.dart';
import '../../core/services/asset_sync_service.dart';
import '../../core/services/ocr_service.dart';
import '../editor/blocks/mario_image_block.dart';

/// One picture in a note, resolved as far as it could be.
class NoteImage {
  const NoteImage({
    required this.blockId,
    this.path,
    this.bytes,
    this.mimeType = 'image/png',
    this.ocrLines = const [],
  });

  final String blockId;

  /// Local path, once resolved. Null when the file is not on this device and
  /// could not be fetched.
  final String? path;

  /// Loaded only when the image is actually going to be sent.
  final Uint8List? bytes;

  final String mimeType;

  /// Text found in the picture, whether it was already stored on the block or
  /// read just now.
  final List<String> ocrLines;

  bool get hasText => ocrLines.any((l) => l.trim().isNotEmpty);
  bool get canSend => bytes != null && bytes!.isNotEmpty;

  LlmImage? toLlmImage() =>
      canSend ? LlmImage(bytes: bytes!, mimeType: mimeType) : null;
}

class NoteImageReader {
  NoteImageReader(this._assets, this._ocr);

  final AssetSyncService _assets;
  final OcrService _ocr;

  /// How many images one request may carry.
  ///
  /// Each is a few hundred KB of base64 and a large slice of the context
  /// window; a page of twenty screenshots would blow past both. The first few
  /// are almost always the relevant ones.
  static const maxImagesPerRequest = 4;

  /// Skip anything above this. Base64 inflates by a third, and a phone photo
  /// straight off a camera is several megabytes before that — enough to stall
  /// a local model for minutes on prefill alone.
  static const maxImageBytes = 3 * 1024 * 1024;

  /// Finds the images in [document] and resolves what it can.
  ///
  /// [loadBytes] controls whether the files are actually read — false is the
  /// cheap path for a text-only backend, which needs the OCR text but not the
  /// pixels.
  Future<List<NoteImage>> read(
    afe.Document document, {
    bool loadBytes = true,
    bool runOcr = true,
  }) async {
    final out = <NoteImage>[];
    for (final node in _imageNodes(document.root)) {
      out.add(await _resolve(node, loadBytes: loadBytes, runOcr: runOcr));
    }
    return out;
  }

  Future<NoteImage> _resolve(
    afe.Node node, {
    required bool loadBytes,
    required bool runOcr,
  }) async {
    final attrs = node.attributes;
    var lines = asStringList(attrs[MarioImageKeys.ocrLines])
        .where((l) => l.trim().isNotEmpty)
        .toList();

    final path = await _localPath(attrs);
    if (path == null) {
      return NoteImage(blockId: node.id, ocrLines: lines);
    }

    // Fill in text for an image nobody has scrolled to yet. The block itself
    // OCRs on render, so this only ever runs for images below the fold.
    if (lines.isEmpty && runOcr && _ocr.isAvailable) {
      try {
        lines = (await _ocr.extractText(path))
            .where((l) => l.trim().isNotEmpty)
            .toList();
      } catch (_) {
        // OCR is a bonus, never a blocker.
      }
    }

    Uint8List? bytes;
    if (loadBytes && !kIsWeb) {
      try {
        final file = File(path);
        final length = await file.length();
        if (length > 0 && length <= maxImageBytes) {
          bytes = await file.readAsBytes();
        }
      } catch (_) {
        // Deleted between resolving and reading.
      }
    }

    return NoteImage(
      blockId: node.id,
      path: path,
      bytes: bytes,
      mimeType: mimeTypeForPath(path),
      ocrLines: lines,
    );
  }

  /// The image on this machine, fetching it from Drive if only the id is known.
  Future<String?> _localPath(Map<String, dynamic> attrs) async {
    final url = asString(attrs[MarioImageKeys.url]);
    if (url != null && url.isNotEmpty && !kIsWeb) {
      if (await File(url).exists()) return url;
    }
    final driveId = asString(attrs[MarioImageKeys.driveId]);
    if (driveId == null || driveId.isEmpty) return null;
    // Already downloaded by another device's insert, or fetch it now.
    final cached = _assets.cachedPath(driveId);
    if (cached != null) return cached;
    try {
      return await _assets.ensureLocal(driveId);
    } catch (_) {
      return null;
    }
  }

  Iterable<afe.Node> _imageNodes(afe.Node root) sync* {
    for (final child in root.children) {
      if (child.type == MarioImageKeys.type) yield child;
      yield* _imageNodes(child);
    }
  }
}

/// Picks the images worth attaching to one request.
///
/// Prefers pictures with *no* OCR text: a diagram or a photo the text pipeline
/// could make nothing of is exactly where a model's eyes add something, whereas
/// a screenshot of a paragraph is already fully represented by its OCR.
List<LlmImage> selectImagesToSend(
  List<NoteImage> images, {
  int limit = NoteImageReader.maxImagesPerRequest,
}) {
  final sendable = images.where((i) => i.canSend).toList()
    ..sort((a, b) {
      if (a.hasText == b.hasText) return 0;
      return a.hasText ? 1 : -1;
    });
  return [
    for (final image in sendable.take(limit)) image.toLlmImage()!,
  ];
}

/// Renders what OCR found, for the prompt.
///
/// Labelled by block id so the agent can refer to the picture it came from, and
/// marked as detected text rather than the user's prose — OCR output is noisy,
/// and a model should weigh "Tl'ie rnitochondria" accordingly.
String renderImageTextForPrompt(List<NoteImage> images) {
  final withText = images.where((i) => i.hasText).toList();
  if (withText.isEmpty) return '';
  final buf = StringBuffer('Text detected in the images on this page:\n');
  for (final image in withText) {
    buf.writeln('[id:${image.blockId}]');
    for (final line in image.ocrLines) {
      buf.writeln('  $line');
    }
  }
  return buf.toString();
}

/// The MIME type for a path, from its extension.
///
/// Guessed rather than sniffed because every backend requires the type
/// declared up front and none of them re-check it. PNG is the safe default:
/// it is the one every provider accepts.
String mimeTypeForPath(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'heic' || 'heif' => 'image/heic',
    _ => 'image/png',
  };
}
