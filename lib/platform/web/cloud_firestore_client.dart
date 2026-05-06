/// CloudFirestoreClient — MarioFirestore backed by FlutterFire on web/native.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/mario_firestore.dart';

class CloudFirestoreClient implements MarioFirestore {
  CloudFirestoreClient(this._db);
  final FirebaseFirestore _db;

  Query<Map<String, dynamic>> _applyFilter(
      Query<Map<String, dynamic>> q, MarioFilter? f) {
    if (f == null) return q;
    if (f.isEqualTo != null) return q.where(f.field, isEqualTo: f.isEqualTo);
    if (f.arrayContains != null) {
      return q.where(f.field, arrayContains: f.arrayContains);
    }
    return q;
  }

  Query<Map<String, dynamic>> _applyOrder(
      Query<Map<String, dynamic>> q, String? field, bool descending) {
    if (field == null) return q;
    return q.orderBy(field, descending: descending);
  }

  MarioDoc _wrap(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      MarioDoc(id: d.id, path: d.reference.path, data: d.data());

  MarioDoc _wrapDoc(DocumentSnapshot<Map<String, dynamic>> d) => MarioDoc(
      id: d.id, path: d.reference.path, data: d.data() ?? const {});

  @override
  Stream<List<MarioDoc>> watchCollection(
    String collectionPath, {
    MarioFilter? where,
    String? orderBy,
    bool descending = false,
  }) {
    Query<Map<String, dynamic>> q = _db.collection(collectionPath);
    q = _applyFilter(q, where);
    q = _applyOrder(q, orderBy, descending);
    return q
        .snapshots()
        .map((s) => s.docs.map(_wrap).toList(growable: false));
  }

  @override
  Future<List<MarioDoc>> fetchCollection(String collectionPath,
      {MarioFilter? where}) async {
    Query<Map<String, dynamic>> q = _db.collection(collectionPath);
    q = _applyFilter(q, where);
    final snap = await q.get();
    return snap.docs.map(_wrap).toList(growable: false);
  }

  @override
  Future<String> add(String collectionPath, Map<String, dynamic> data) async {
    final ref = await _db.collection(collectionPath).add(data);
    return ref.id;
  }

  @override
  Future<void> set(String docPath, Map<String, dynamic> data,
      {bool merge = false}) =>
      _db.doc(docPath).set(data, SetOptions(merge: merge));

  @override
  Future<void> update(String docPath, Map<String, dynamic> data) =>
      _db.doc(docPath).update(data);

  @override
  Future<void> delete(String docPath) => _db.doc(docPath).delete();

  @override
  Future<void> arrayUnion(
          String docPath, String field, List<Object?> items) =>
      _db.doc(docPath).set({field: FieldValue.arrayUnion(items)},
          SetOptions(merge: true));

  /// Convenience for share_dialog when it wants the raw doc once.
  Future<MarioDoc> getDoc(String path) async =>
      _wrapDoc(await _db.doc(path).get());
}
