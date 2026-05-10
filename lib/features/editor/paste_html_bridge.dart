/// Cross-file bridge for pasted raw HTML documents.
///
/// AppFlowy's `htmlToDocument` understands a small subset of HTML (paragraph,
/// heading, list, quote, image, table) — pasting a full styled document
/// (DOCTYPE + custom CSS + scripts) loses everything except the bare text
/// structure. To preserve fidelity in the preview pane, the smart-paste
/// handler stashes the original HTML here, and the preview pane prefers it
/// over `documentToHTML` output when it's set.
///
/// Single global notifier — the editor only renders one page at a time, and
/// the screen clears the value on page mount.
library;

import 'package:flutter/foundation.dart';

/// `null` = no override; preview falls back to documentToHTML(doc).
/// Non-null = render this raw HTML in the preview pane verbatim.
final ValueNotifier<String?> rawHtmlOverride = ValueNotifier<String?>(null);
