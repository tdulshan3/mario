/// safeApply — wraps editorState.apply so block embeds don't crash with
/// "node was used after dispose" when their async callbacks (OCR, math,
/// drawing, audio) complete after the user has navigated away.
library;

import 'package:appflowy_editor/appflowy_editor.dart' as afe;

/// Build a transaction with [builder] and apply it, but bail if the editor
/// has already been torn down. Returns true on success.
///
/// Set [background] for a machine-generated attribute write that the user
/// didn't ask for — an OCR result landing, an image's Drive id arriving from a
/// finished upload. Those need two things a user edit doesn't:
///
///  * **Selection left alone.** `Transaction.updateNode` never fills in
///    `afterSelection`, and `apply` assigns it unconditionally, so a plain
///    apply sets `selection = null`. Fired while someone is mid-sentence, that
///    yanks their caret out of the paragraph they were typing in.
///  * **No undo entry.** Ctrl-Z should step back through the user's edits, not
///    through bookkeeping they never made.
Future<bool> safeApply(
  afe.EditorState editorState,
  void Function(afe.Transaction tx) builder, {
  bool background = false,
}) async {
  if (editorState.isDisposed) return false;
  try {
    final tx = editorState.transaction;
    builder(tx);
    if (editorState.isDisposed) return false;
    await editorState.apply(
      tx,
      options: afe.ApplyOptions(recordUndo: !background),
      withUpdateSelection: !background,
    );
    return true;
  } catch (_) {
    // The editor was disposed mid-apply (race between dispose and our await).
    // Drop the change silently — the user has moved on and our changes would
    // never have been visible anyway.
    return false;
  }
}
