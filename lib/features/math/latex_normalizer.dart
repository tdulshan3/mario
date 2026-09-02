/// Returns the formula body expected by `Math.tex`.
///
/// `Math.tex` is already in math mode, while people and language models often
/// paste Markdown display-math wrappers such as `$$...$$` or `\[...\]`. Passing
/// those wrappers through makes the dollar sign look like a nested math-mode
/// command and produces "Can't use function '$' in math mode".
String normalizeLatexFormula(String source) {
  var formula = source.trim();

  // Peel repeatedly because model output is commonly both fenced and wrapped:
  // ```latex\n$$E = mc^2$$\n```.
  while (formula.isNotEmpty) {
    final before = formula;
    formula = _withoutCodeFence(formula);
    formula = _withoutMathDelimiters(formula);
    if (formula == before) break;
  }

  return formula;
}

String _withoutCodeFence(String source) {
  final match = RegExp(
    r'^```(?:latex|tex|math)?[ \t]*\r?\n([\s\S]*?)\r?\n```$',
    caseSensitive: false,
  ).firstMatch(source);
  if (match != null) return match.group(1)!.trim();

  final tildeMatch = RegExp(
    r'^~~~(?:latex|tex|math)?[ \t]*\r?\n([\s\S]*?)\r?\n~~~$',
    caseSensitive: false,
  ).firstMatch(source);
  return tildeMatch?.group(1)?.trim() ?? source;
}

String _withoutMathDelimiters(String source) {
  const pairs = <(String, String)>[
    (r'$$', r'$$'),
    (r'\[', r'\]'),
    (r'\(', r'\)'),
    (r'$', r'$'),
  ];

  for (final (opening, closing) in pairs) {
    if (source.length > opening.length + closing.length &&
        source.startsWith(opening) &&
        source.endsWith(closing)) {
      return source
          .substring(opening.length, source.length - closing.length)
          .trim();
    }
  }
  return source;
}
