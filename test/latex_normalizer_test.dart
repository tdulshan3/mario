import 'package:flutter_test/flutter_test.dart';
import 'package:mario/features/math/latex_normalizer.dart';

void main() {
  test('keeps renderer-ready LaTeX unchanged', () {
    expect(normalizeLatexFormula(r'\frac{a}{b}'), r'\frac{a}{b}');
    expect(normalizeLatexFormula(r'\text{Price: \$5}'), r'\text{Price: \$5}');
  });

  test('removes common inline and display math wrappers', () {
    expect(normalizeLatexFormula(r'$$E = mc^2$$'), r'E = mc^2');
    expect(normalizeLatexFormula(r'$x + 1$'), r'x + 1');
    expect(normalizeLatexFormula(r'\[x + 1\]'), r'x + 1');
    expect(normalizeLatexFormula(r'\(x + 1\)'), r'x + 1');
  });

  test('removes a fenced and wrapped model response', () {
    expect(
      normalizeLatexFormula('```latex\n\$\$\\sum_{i=1}^n i\$\$\n```'),
      r'\sum_{i=1}^n i',
    );
  });

  test('does not strip unmatched delimiters', () {
    expect(normalizeLatexFormula(r'$$x + 1'), r'$$x + 1');
  });
}
