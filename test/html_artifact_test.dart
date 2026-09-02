import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/ai/html_artifact.dart';
import 'package:mario/features/editor/html_preview.dart';

void main() {
  group('HTML artifact extraction', () {
    test('reads a fenced artifact out of a normal answer', () {
      const answer = 'Here is the result.\n\n```html\n'
          '<!doctype html><html><body><button>Go</button></body></html>\n'
          '```';
      expect(extractHtmlArtifact(answer), contains('<button>Go</button>'));
    });

    test('accepts a complete unfenced document', () {
      const html = '<!DOCTYPE html><html><body>Hello</body></html>';
      expect(extractHtmlArtifact(html), html);
    });

    test('does not run an incidental inline tag from prose', () {
      expect(extractHtmlArtifact('Use a <div> for this section.'), isNull);
    });

    test('recognises common artifact requests', () {
      expect(asksForHtmlArtifact('Build a responsive landing page'), isTrue);
      expect(asksForHtmlArtifact('Explain this paragraph'), isFalse);
    });
  });

  group('sandboxed preview document', () {
    test('keeps scripts interactive but removes powerful iframe privileges',
        () {
      final doc = prepareHtmlPreviewDocument(
        '<button onclick="go()">Go</button><script>function go(){}</script>',
        isDark: false,
        sandboxed: true,
      );

      expect(doc, contains('sandbox="allow-scripts allow-forms allow-modals"'));
      expect(doc, isNot(contains('allow-same-origin')));
      expect(doc, isNot(contains('allow-top-navigation')));
      expect(doc, contains("connect-src 'none'"));
      expect(doc, contains('&lt;script&gt;'));
    });

    test('leaves a trusted full document intact', () {
      const html = '<!doctype html><html><body>x</body></html>';
      expect(
        prepareHtmlPreviewDocument(html, isDark: false),
        html,
      );
    });
  });
}
