/// Detecting previewable HTML in a normal model answer.
library;

/// Returns the first fenced HTML artifact, or a complete raw HTML document.
///
/// A random inline tag in prose is intentionally not treated as an artifact.
/// Models commonly explain `<div>` in ordinary answers; auto-running that as
/// a document would be surprising. A fenced block is an explicit artifact,
/// while an unfenced answer must itself start like a full document.
String? extractHtmlArtifact(String answer) {
  final fenced = RegExp(
    r'```(?:html|htm)\s*\n([\s\S]*?)```',
    caseSensitive: false,
  ).firstMatch(answer);
  final fromFence = fenced?.group(1)?.trim();
  if (fromFence != null && _hasHtmlElement(fromFence)) return fromFence;

  final raw = answer.trim();
  final lower = raw.toLowerCase();
  if ((lower.startsWith('<!doctype html') || lower.startsWith('<html')) &&
      _hasHtmlElement(raw)) {
    return raw;
  }
  return null;
}

bool _hasHtmlElement(String value) =>
    RegExp(r'<[a-z][^>]*>', caseSensitive: false).hasMatch(value);

/// Whether a prompt is asking for a browser-rendered result.
///
/// Used only as a prompt hint. Artifact extraction still requires actual HTML.
bool asksForHtmlArtifact(String prompt) {
  final p = prompt.toLowerCase();
  return p.contains('html') ||
      p.contains('web page') ||
      p.contains('webpage') ||
      p.contains('landing page') ||
      p.contains('website') ||
      p.contains('web app') ||
      p.contains('artifact');
}
