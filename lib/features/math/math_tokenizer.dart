/// MathTokenizer — pure unicode replacement for inline math shortcuts.
///
/// Looks at the trailing text before the cursor and returns a [MathToken] when
/// the user typed something we should auto-correct (Greek letter, comparison
/// operator, super/subscript, sqrt, etc.). The shortcut handler triggers this
/// every time the user presses Space.
library;

class MathToken {
  /// Index in the source text where the original token starts.
  final int start;

  /// Number of source characters to delete.
  final int length;

  /// Replacement string to insert at [start].
  final String replacement;

  const MathToken({
    required this.start,
    required this.length,
    required this.replacement,
  });
}

class MathTokenizer {
  const MathTokenizer._();

  static const Map<String, String> _greek = {
    'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ',
    'epsilon': 'ε', 'zeta': 'ζ', 'eta': 'η', 'theta': 'θ',
    'iota': 'ι', 'kappa': 'κ', 'lambda': 'λ', 'mu': 'μ',
    'nu': 'ν', 'xi': 'ξ', 'omicron': 'ο', 'pi': 'π',
    'rho': 'ρ', 'sigma': 'σ', 'tau': 'τ', 'upsilon': 'υ',
    'phi': 'φ', 'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
  };

  static const Map<String, String> _wordOps = {
    'inf': '∞', 'sum': '∑', 'int': '∫', 'pm': '±',
    'cdot': '·', 'times': '×', 'div': '÷',
    'forall': '∀', 'exists': '∃', 'neg': '¬',
    'in': '∈', 'notin': '∉', 'subset': '⊂', 'supset': '⊃',
  };

  /// Multi-character symbol operators sorted longest-first to ensure the
  /// longest valid match wins (e.g. `<->` before `<-`).
  static const List<MapEntry<String, String>> _symbolOps = [
    MapEntry('<->', '↔'),
    MapEntry('->', '→'),
    MapEntry('<-', '←'),
    MapEntry('>=', '≥'),
    MapEntry('<=', '≤'),
    MapEntry('!=', '≠'),
    MapEntry('~=', '≈'),
  ];

  static const Map<String, String> _superscript = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
    'n': 'ⁿ', 'i': 'ⁱ',
  };

  static const Map<String, String> _subscript = {
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
    '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
    '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
  };

  static final RegExp _wordRe = RegExp(r'([a-zA-Z]+)$');
  static final RegExp _supRe = RegExp(r'\^([0-9+\-=()ni])$');
  static final RegExp _subRe = RegExp(r'_([0-9+\-=()])$');

  /// Find a replacement for the trailing token before [cursor] in [text].
  /// Returns null when nothing matches.
  static MathToken? tryTokenize(String text, int cursor) {
    if (cursor <= 0 || cursor > text.length) return null;
    final before = text.substring(0, cursor);

    final supMatch = _supRe.firstMatch(before);
    if (supMatch != null) {
      final ch = supMatch.group(1)!;
      final mapped = _superscript[ch];
      if (mapped != null) {
        return MathToken(
          start: supMatch.start,
          length: supMatch.end - supMatch.start,
          replacement: mapped,
        );
      }
    }

    final subMatch = _subRe.firstMatch(before);
    if (subMatch != null) {
      final ch = subMatch.group(1)!;
      final mapped = _subscript[ch];
      if (mapped != null) {
        return MathToken(
          start: subMatch.start,
          length: subMatch.end - subMatch.start,
          replacement: mapped,
        );
      }
    }

    for (final entry in _symbolOps) {
      if (before.endsWith(entry.key)) {
        return MathToken(
          start: before.length - entry.key.length,
          length: entry.key.length,
          replacement: entry.value,
        );
      }
    }

    final wordMatch = _wordRe.firstMatch(before);
    if (wordMatch != null) {
      final word = wordMatch.group(1)!;
      final lower = word.toLowerCase();
      final greek = _greek[lower];
      if (greek != null) {
        return MathToken(
          start: wordMatch.start,
          length: word.length,
          replacement: greek,
        );
      }
      final op = _wordOps[lower];
      if (op != null) {
        return MathToken(
          start: wordMatch.start,
          length: word.length,
          replacement: op,
        );
      }
    }

    return null;
  }
}
