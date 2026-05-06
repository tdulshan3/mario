/// safeApply — wraps editorState.apply so block embeds don't crash with
/// "node was used after dispose" when their async callbacks (OCR, math,
/// drawing, audio) complete after the user has navigated away.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;

/// Build a transaction with [builder] and apply it, but bail if the editor
/// has already been torn down. Returns true on success.
Future<bool> safeApply(
  afe.EditorState editorState,
  void Function(afe.Transaction tx) builder,
) async {
  if (editorState.isDisposed) return false;
  try {
    final tx = editorState.transaction;
    builder(tx);
    if (editorState.isDisposed) return false;
    await editorState.apply(tx);
    return true;
  } catch (_) {
    // The editor was disposed mid-apply (race between dispose and our await).
    // Drop the change silently — the user has moved on and our changes would
    // never have been visible anyway.
    return false;
  }
}
