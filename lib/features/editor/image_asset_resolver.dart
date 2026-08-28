/// resolveImageSources — rewrites the image `src`s in serialized output so
/// they point at files that exist on *this* machine.
///
/// AppFlowy's HTML and Markdown encoders both emit an image node's `url`
/// attribute verbatim, and that attribute is the absolute path on whichever
/// device inserted the picture. Sign in on a second machine and every exported
/// `<img>` / `![]()` points into a home directory that isn't there.
///
/// The image block itself doesn't have this problem — it resolves through
/// [AssetSyncService] and draws the local copy. This gives the serializing
/// paths (the HTML preview pane, Markdown export) the same resolution, applied
/// after encoding rather than by patching every encoder.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;

import '../../core/services/asset_sync_service.dart';
import 'blocks/mario_image_block.dart';

/// Maps each image node's written `url` to the path it actually resolves to on
/// this device, omitting the ones that already agree (the common case, on the
/// machine that inserted them).
///
/// Downloads missing assets when [fetchMissing] is set — right for an export
/// the user is waiting on, wrong for the live preview pane, which repaints on
/// every keystroke and must stay off the network.
Future<Map<String, String>> resolveImageSources(
  afe.Document document,
  AssetSyncService assets, {
  bool fetchMissing = false,
}) async {
  final nodes = <afe.Node>[];
  void collect(afe.Node n) {
    if (n.type == MarioImageKeys.type) nodes.add(n);
    for (final c in n.children) {
      collect(c);
    }
  }

  for (final n in document.root.children) {
    collect(n);
  }

  final out = <String, String>{};
  for (final n in nodes) {
    final url = n.attributes[MarioImageKeys.url];
    if (url is! String || url.isEmpty) continue;
    final id = n.attributes[MarioImageKeys.driveId];
    if (id is! String || id.isEmpty) continue;

    final local = assets.cachedPath(id) ??
        (fetchMissing ? await assets.ensureLocal(id) : null);
    if (local != null && local != url) out[url] = local;
  }
  return out;
}

/// Applies [substitutions] to the `src="…"` attributes of [html], leaving the
/// rest of the document alone. Scoped to the attribute rather than done as a
/// blind string replace so a path that also appears in the prose survives.
String rewriteHtmlImageSources(
    String html, Map<String, String> substitutions) {
  if (substitutions.isEmpty) return html;
  var out = html;
  substitutions.forEach((from, to) {
    out = out
        .replaceAll('src="$from"', 'src="${Uri.file(to)}"')
        .replaceAll("src='$from'", "src='${Uri.file(to)}'");
  });
  return out;
}

/// Applies [substitutions] to the `](…)` target of Markdown image links.
String rewriteMarkdownImageSources(
    String markdown, Map<String, String> substitutions) {
  if (substitutions.isEmpty) return markdown;
  var out = markdown;
  substitutions.forEach((from, to) {
    out = out.replaceAll(']($from)', ']($to)');
  });
  return out;
}
