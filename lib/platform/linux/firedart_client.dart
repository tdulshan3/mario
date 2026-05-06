/// FiredartClient — MarioFirestore on top of the pure-Dart firedart package.
///
/// Reactivity model
/// ────────────────
/// firedart only exposes a true server-push `.stream` for *unfiltered*
/// collections. Anything with a `where` or `orderBy` falls back to a single
/// `.get()` call, which means inserts/updates from this same client wouldn't
/// be visible to running watchers without help.
///
/// We keep a per-collection broadcast trigger. Every mutation [add], [set],
/// [update], [delete], [arrayUnion] pings the trigger for the affected
/// collection; running watchers re-fetch on each ping. This gives us
/// single-client reactivity (your own changes show up immediately). True
/// cross-client realtime would need Firestore's Listen RPC, which firedart
/// doesn't surface for filtered queries.
library;

import 'dart:async';

import 'package:firedart/firedart.dart' as fd;

import '../../core/services/mario_firestore.dart';

class FiredartClient implements MarioFirestore {
  FiredartClient(this._db);
  final fd.Firestore _db;

  final Map<String, StreamController<void>> _triggers = {};

  StreamController<void> _triggerFor(String collectionPath) =>
      _triggers.putIfAbsent(
        collectionPath,
        () => StreamController<void>.broadcast(),
      );

  void _ping(String collectionPath) {
    final t = _triggers[collectionPath];
    if (t != null && !t.isClosed) t.add(null);
  }

  /// `notebooks/abc/sections/xyz` → `notebooks/abc/sections`. Used to ping
  /// the parent collection's watchers after a doc-level mutation.
  String _parentCollection(String docPath) {
    final i = docPath.lastIndexOf('/');
    return i < 0 ? docPath : docPath.substring(0, i);
  }

  fd.QueryReference _query(String collectionPath, MarioFilter? filter,
      {String? orderBy, bool descending = false}) {
    final coll = _db.collection(collectionPath);
    fd.QueryReference q = filter == null
        ? coll.orderBy(orderBy ?? '__name__', descending: descending)
        : (filter.isEqualTo != null
            ? coll.where(filter.field, isEqualTo: filter.isEqualTo)
            : coll.where(filter.field, arrayContains: filter.arrayContains));
    if (filter != null && orderBy != null) {
      q = q.orderBy(orderBy, descending: descending);
    }
    return q;
  }

  MarioDoc _wrap(fd.Document d) =>
      MarioDoc(id: d.id, path: d.path, data: d.map);

  Future<List<MarioDoc>> _fetchOnce(String collectionPath, MarioFilter? filter,
      {String? orderBy, bool descending = false}) async {
    final q = _query(collectionPath, filter,
        orderBy: orderBy, descending: descending);
    final docs = await q.get();
    return docs.map(_wrap).toList(growable: false);
  }

  @override
  Stream<List<MarioDoc>> watchCollection(
    String collectionPath, {
    MarioFilter? where,
    String? orderBy,
    bool descending = false,
  }) async* {
    if (where == null && orderBy == null) {
      // Unfiltered collections get true server-push reactivity from firedart.
      yield* _db
          .collection(collectionPath)
          .stream
          .map((docs) => docs.map(_wrap).toList(growable: false));
      return;
    }

    // Filtered/ordered queries: initial fetch + re-fetch on every local
    // mutation that pings this collection.
    yield await _fetchOnce(collectionPath, where,
        orderBy: orderBy, descending: descending);
    await for (final _ in _triggerFor(collectionPath).stream) {
      yield await _fetchOnce(collectionPath, where,
          orderBy: orderBy, descending: descending);
    }
  }

  @override
  Future<List<MarioDoc>> fetchCollection(String collectionPath,
      {MarioFilter? where}) async {
    if (where == null) {
      final page = await _db.collection(collectionPath).get();
      return page.map(_wrap).toList(growable: false);
    }
    return _fetchOnce(collectionPath, where);
  }

  @override
  Future<String> add(String collectionPath, Map<String, dynamic> data) async {
    final doc = await _db.collection(collectionPath).add(data);
    _ping(collectionPath);
    return doc.id;
  }

  @override
  Future<void> set(String docPath, Map<String, dynamic> data,
      {bool merge = false}) async {
    final ref = _db.document(docPath);
    if (merge) {
      try {
        final existing = await ref.get();
        await ref.update({...existing.map, ...data});
        _ping(_parentCollection(docPath));
        return;
      } catch (_) {
        // doc didn't exist — fall through to create.
      }
    }
    await ref.set(data);
    _ping(_parentCollection(docPath));
  }

  @override
  Future<void> update(String docPath, Map<String, dynamic> data) async {
    await _db.document(docPath).update(data);
    _ping(_parentCollection(docPath));
  }

  @override
  Future<void> delete(String docPath) async {
    await _db.document(docPath).delete();
    _ping(_parentCollection(docPath));
  }

  @override
  Future<void> arrayUnion(
      String docPath, String field, List<Object?> items) async {
    final ref = _db.document(docPath);
    Map<String, dynamic> existing = {};
    try {
      existing = (await ref.get()).map;
    } catch (_) {}
    final current = (existing[field] as List?) ?? const [];
    final next = <Object?>[
      ...current,
      ...items.where((i) => !current.contains(i)),
    ];
    await ref.update({...existing, field: next});
    _ping(_parentCollection(docPath));
  }
}
