/// Getting the pictures in a note to a model.
///
/// The selection rule is the interesting part: with a limited budget, the
/// images worth *sending* are the ones OCR could make nothing of. A screenshot
/// of a paragraph is already fully represented by its text, whereas a diagram
/// or a photograph is exactly where a model's eyes add something the text
/// pipeline cannot.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/note_images.dart';

void main() {
  Uint8List bytes([int n = 16]) => Uint8List.fromList(List.filled(n, 1));

  NoteImage image({
    required String id,
    List<String> ocr = const [],
    bool loaded = true,
  }) =>
      NoteImage(
        blockId: id,
        path: '/tmp/$id.png',
        bytes: loaded ? bytes() : null,
        ocrLines: ocr,
      );

  group('selecting which images to send', () {
    test('prefers images OCR could make nothing of', () {
      // A diagram is where vision earns its tokens; a screenshot of text is
      // already fully represented in the prompt by its OCR. Told apart by
      // byte length, since the wire image carries no id.
      final screenshot = NoteImage(
        blockId: 'screenshot',
        bytes: bytes(10),
        ocrLines: const ['a paragraph of text'],
      );
      final diagram = NoteImage(blockId: 'diagram', bytes: bytes(99));

      final picked = selectImagesToSend([screenshot, diagram], limit: 1);
      expect(picked, hasLength(1));
      expect(picked.single.bytes.length, 99,
          reason: 'the diagram should win the single slot');

      // Order holds when both fit, so the textless one is read first.
      final both = selectImagesToSend([screenshot, diagram]);
      expect(both.map((i) => i.bytes.length), [99, 10]);
    });

    test('honours the limit', () {
      final picked = selectImagesToSend([
        for (var i = 0; i < 10; i++) image(id: 'i$i'),
      ], limit: 3);
      expect(picked, hasLength(3));
    });

    test('skips images whose bytes could not be loaded', () {
      // Not on this device and Drive was unreachable — the OCR text may still
      // be usable, but there is nothing to send.
      final picked = selectImagesToSend([
        image(id: 'missing', loaded: false),
        image(id: 'present'),
      ]);
      expect(picked, hasLength(1));
    });

    test('an image-free page sends nothing', () {
      expect(selectImagesToSend(const []), isEmpty);
    });
  });

  group('rendering detected text for the prompt', () {
    test('labels each block so the agent can refer to the picture', () {
      final rendered = renderImageTextForPrompt([
        image(id: 'abc123', ocr: ['F = ma', "Newton's second law"]),
      ]);
      expect(rendered, contains('[id:abc123]'));
      expect(rendered, contains('F = ma'));
    });

    test('marks it as detected text rather than typed prose', () {
      // OCR output is noisy; a model should weigh "Tl'ie rnitochondria"
      // differently from something the student typed.
      expect(
        renderImageTextForPrompt([image(id: 'a', ocr: ['x'])]),
        contains('detected'),
      );
    });

    test('says nothing when no image had readable text', () {
      expect(renderImageTextForPrompt([image(id: 'a')]), isEmpty);
      expect(renderImageTextForPrompt(const []), isEmpty);
    });
  });

  group('mime types', () {
    test('maps the formats a note actually contains', () {
      expect(mimeTypeForPath('/x/photo.jpg'), 'image/jpeg');
      expect(mimeTypeForPath('/x/photo.JPEG'), 'image/jpeg');
      expect(mimeTypeForPath('/x/shot.png'), 'image/png');
      expect(mimeTypeForPath('/x/anim.gif'), 'image/gif');
      expect(mimeTypeForPath('/x/pic.webp'), 'image/webp');
      expect(mimeTypeForPath('/x/phone.heic'), 'image/heic');
    });

    test('defaults to png, the type every provider accepts', () {
      expect(mimeTypeForPath('/x/noextension'), 'image/png');
      expect(mimeTypeForPath(''), 'image/png');
    });
  });

  group('NoteImage', () {
    test('knows whether it has usable text', () {
      expect(image(id: 'a', ocr: ['real text']).hasText, isTrue);
      expect(image(id: 'a', ocr: ['   ']).hasText, isFalse);
      expect(image(id: 'a').hasText, isFalse);
    });

    test('knows whether it can be sent', () {
      expect(image(id: 'a').canSend, isTrue);
      expect(image(id: 'a', loaded: false).canSend, isFalse);
    });

    test('converts to a wire image only when it has bytes', () {
      expect(image(id: 'a').toLlmImage(), isNotNull);
      expect(image(id: 'a', loaded: false).toLlmImage(), isNull);
    });

    test('reports the encoded cost, which is what the budget cares about', () {
      // base64 inflates by a third, and that is what crosses the wire.
      final img = NoteImage(blockId: 'a', bytes: bytes(300)).toLlmImage()!;
      expect(img.encodedBytes, greaterThan(300));
      expect(img.encodedBytes, lessThan(500));
    });
  });
}
