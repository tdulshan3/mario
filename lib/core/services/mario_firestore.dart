/// MarioFirestore — minimal Firestore facade backed by either cloud_firestore (web)
/// or firedart (Linux). SyncService is the only consumer; the surface area is
/// deliberately small.
library;

class MarioDoc {
  /// Last path segment, e.g. "abc123" for "notebooks/abc123".
  final String id;

  /// Full collection-rooted path, e.g. "notebooks/abc123/sections/xyz".
  final String path;

  /// Parsed field map for the document.
  final Map<String, dynamic> data;

  const MarioDoc({required this.id, required this.path, required this.data});
}

class MarioFilter {
  final String field;
  final Object? isEqualTo;
  final Object? arrayContains;

  const MarioFilter.eq(this.field, Object value)
      : isEqualTo = value,
        arrayContains = null;

  const MarioFilter.contains(this.field, Object value)
      : isEqualTo = null,
        arrayContains = value;
}

abstract class MarioFirestore {
  /// Stream of all docs in [collectionPath] matching [where] and [orderBy].
  Stream<List<MarioDoc>> watchCollection(
    String collectionPath, {
    MarioFilter? where,
    String? orderBy,
    bool descending = false,
  });

  /// One-shot fetch of a collection (used for cascade deletes).
  Future<List<MarioDoc>> fetchCollection(
    String collectionPath, {
    MarioFilter? where,
  });

  /// Append a doc; returns its generated id.
  Future<String> add(String collectionPath, Map<String, dynamic> data);

  /// Set with optional merge semantics.
  Future<void> set(String docPath, Map<String, dynamic> data,
      {bool merge = false});

  /// Patch existing fields.
  Future<void> update(String docPath, Map<String, dynamic> data);

  /// Delete a single doc (subcollections are not auto-deleted).
  Future<void> delete(String docPath);

  /// Append [items] to an array field, deduplicating server-side when possible.
  Future<void> arrayUnion(String docPath, String field, List<Object?> items);
}
