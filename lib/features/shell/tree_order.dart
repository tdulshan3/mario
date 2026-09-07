/// The arithmetic of dragging a row to a new place in the sidebar.
///
/// Pure, so the sidebar's drag-and-drop can be tested without a widget tree:
/// given the ids in their current order, which id was dragged and which it
/// was dropped beside, produce the new order — and, against the orders the
/// rows carry today, the writes that make it so. Orders are renumbered from
/// zero along the whole list rather than nudged, so a list that has been
/// dragged about for months never runs out of gaps or grows duplicates.
library;

/// [ids] with [draggedId] moved to sit before or after [targetId].
///
/// Dropping a row on itself, or beside an id that is not in the list, is
/// no change.
List<String> reorderedIds(
  List<String> ids,
  String draggedId,
  String targetId, {
  required bool before,
}) {
  if (draggedId == targetId) return ids;
  final out = [...ids]..remove(draggedId);
  var index = out.indexOf(targetId);
  if (index < 0) return ids;
  if (!before) index++;
  out.insert(index, draggedId);
  return out;
}

/// [ids] with [id] appended — a row dropped into a list, at the end.
List<String> appendedIds(List<String> ids, String id) => [
      ...ids.where((x) => x != id),
      id,
    ];

/// The rows whose stored order no longer matches their place in [order]:
/// id → the order to write. Rows already in place are left alone, which is
/// most of them for most drags.
Map<String, int> ordersToWrite(List<String> order, Map<String, int> current) {
  final out = <String, int>{};
  for (var i = 0; i < order.length; i++) {
    if (current[order[i]] != i) out[order[i]] = i;
  }
  return out;
}
