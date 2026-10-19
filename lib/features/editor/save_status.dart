/// Where the open page's content stands with Drive, and the line that says so.
///
/// Its own library so the page actions of both looks can print it without
/// importing the whole editor screen.
library;

enum SaveStatus { idle, dirty, saving, saved, error }

/// The save line both looks print beside the page actions.
///
/// The real save state, not a promise. `idle` means nothing has been typed
/// since the page was loaded from Drive, so there is genuinely nothing
/// outstanding either way. Images not yet on Drive and outbox changes the
/// server has not heard about are appended: "Saved" is true here, and not yet
/// anywhere else.
String saveStatusLabel({
  required SaveStatus status,
  required DateTime? lastSavedAt,
  required int pendingImages,
  required int pendingChanges,
}) {
  var saveLabel = switch (status) {
    SaveStatus.idle => lastSavedAt == null ? 'No changes' : 'Saved',
    SaveStatus.dirty => 'Unsaved',
    SaveStatus.saving => 'Saving…',
    SaveStatus.saved => 'Saved',
    SaveStatus.error => 'Save failed',
  };
  if (pendingImages > 0 && status != SaveStatus.error) {
    saveLabel = '$saveLabel · $pendingImages '
        'image${pendingImages == 1 ? '' : 's'} not synced';
  }
  if (pendingChanges > 0) {
    saveLabel = '$saveLabel · $pendingChanges '
        'change${pendingChanges == 1 ? '' : 's'} waiting to sync';
  }
  return saveLabel;
}
