/// Regression test for the PDF export "tofu" bug: characters outside Latin-1
/// (smart quotes, dashes, arrows, math operators, …) used to render as
/// missing-glyph boxes because the `pdf` package defaulted to the built-in
/// Helvetica Type1 font. The fix bundles Noto Sans + symbol/math fallbacks and
/// applies them as the document theme. This test proves those characters now
/// resolve to real glyphs in the bundled fonts and that a PDF still renders.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mirrors the asset list wired into PdfExporter._theme().
  const fontAssets = [
    'assets/fonts/NotoSans-Regular.ttf',
    'assets/fonts/NotoSans-Bold.ttf',
    'assets/fonts/NotoSans-Italic.ttf',
    'assets/fonts/NotoSans-BoldItalic.ttf',
    'assets/fonts/NotoSansSymbols-Regular.ttf',
    'assets/fonts/NotoSansSymbols2-Regular.ttf',
    'assets/fonts/NotoSansMath-Regular.ttf',
  ];

  // Characters that fall outside Helvetica's Latin-1 coverage — i.e. the ones
  // that used to show up as a box with a cross.
  const sample = {
    'right single quote': '’',
    'left double quote': '“',
    'em dash': '—',
    'ellipsis': '…',
    'rightwards arrow': '→',
    'not equal': '≠',
    'less-than-or-equal': '≤',
    'n-ary summation': '∑',
    'square root': '√',
    'infinity': '∞',
    'greek pi': 'π',
    'cyrillic De': 'Д',
    'check mark': '✓',
    'bullet': '•',
  };

  test('bundled fonts provide a glyph for every previously-tofu character',
      () async {
    // Union of all glyph maps across the bundled faces (the package picks a
    // fallback per-glyph, so coverage in *any* face is enough).
    final supported = <int>{};
    for (final asset in fontAssets) {
      final data = await rootBundle.load(asset);
      final parser = TtfParser(data);
      parser.charToGlyphIndexMap.forEach((char, glyph) {
        if (glyph != 0) supported.add(char); // glyph 0 == .notdef (tofu)
      });
    }

    final missing = <String>[];
    sample.forEach((name, char) {
      if (!supported.contains(char.runes.first)) missing.add('$name ($char)');
    });
    expect(missing, isEmpty,
        reason: 'No bundled font covers: ${missing.join(', ')}');
  });

  test('renders a non-empty PDF containing the unicode sample', () async {
    Future<pw.Font> load(String a) async => pw.Font.ttf(await rootBundle.load(a));
    final theme = pw.ThemeData.withFont(
      base: await load(fontAssets[0]),
      bold: await load(fontAssets[1]),
      italic: await load(fontAssets[2]),
      boldItalic: await load(fontAssets[3]),
      fontFallback: [
        await load(fontAssets[4]),
        await load(fontAssets[5]),
        await load(fontAssets[6]),
      ],
    );

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.Page(
        build: (_) => pw.Text(sample.values.join(' ')),
      ),
    );
    final bytes = await doc.save();

    expect(bytes, isNotEmpty);
    // Valid PDFs begin with the "%PDF" magic bytes.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
