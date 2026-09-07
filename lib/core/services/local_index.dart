/// The notebook tree as this device knows it: what the server last sent,
/// plus what the user has changed since that the server has not yet seen.
///
/// Every screen reads notebooks, sections and pages through three streams.
/// Those used to be the server's streams, bare — which on Linux means a
/// stream that throws the moment Firestore is unreachable, and a sidebar that
/// then shows nothing. Here each stream is three things merged:
///
///  * the **snapshot** — the last list the server sent for that key, kept on
///    disk, emitted at once so the tree is there before the network is, and
///    still there when the network is not;
///  * the **server** — subscribed underneath, re-subscribed on a timer after
///    an error, each emission replacing the snapshot;
///  * the **overlay** — pending creates shown, pending deletes hidden, pending
///    renames applied, until the server's own emission carries the change.
///
/// The overlay is what makes an offline create appear instantly and an
/// online one appear without a round trip; the snapshot is what makes the
/// app open to its notebooks on a train.
library;

import 'dart:async';
import 'dart:convert';

import '../models/note_page.dart';
import '../models/notebook.dart';
import '../models/section.dart';
import 'ai/json_coercion.dart';
import 'sync_store.dart';

/// What the overlay says about one document.
class _Pending<T> {
  _Pending(this.model) : deleted = model == null;

  /// The model to show, or null for "gone".
  final T? model;
  final bool deleted;

  /// When its change reached the server. The entry is kept a little longer,
  /// for the server's stream to catch up, then dropped regardless.
  DateTime? settledAt;
}

class LocalIndex {
  LocalIndex(this._store);

  final SyncStore _store;
  static const _file = 'index';

  /// Grace after a change reached the server before its overlay entry is
  /// dropped even if the server's stream has not repeated it back.
  Duration settleGrace = const Duration(seconds: 15);

  /// How long to wait before re-subscribing to a server stream that failed.
  Duration retryAfterError = const Duration(seconds: 20);

  final _snapshot = <String, List<Map<String, dynamic>>>{};
  Future<void>? _loading;
  bool _loaded = false;
  Timer? _persistTimer;
  bool _disposed = false;

  final _pendingNotebooks = <String, _Pending<Notebook>>{};
  final _pendingSections = <String, _Pending<Section>>{};
  final _pendingPages = <String, _Pending<NotePage>>{};
  final _changes = StreamController<void>.broadcast();

  static String notebooksKey(String uid) => 'notebooks:$uid';
  static String sectionsKey(String notebookId) => 'sections:$notebookId';
  static String pagesKey(String notebookId, String sectionId) =>
      'pages:$notebookId/$sectionId';

  Future<void> load() => _loading ??= () async {
        final data = await _store.read(_file);
        if (data != null) {
          final keys = asMap(data['keys']) ?? const {};
          for (final e in keys.entries) {
            _snapshot[e.key] = asMapList(e.value);
          }
        }
        _loaded = true;
      }();

  void _persistSoon() {
    if (!_loaded || _disposed) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_store.write(_file, {'keys': _snapshot}));
    });
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  // ---------------------------------------------------- what is known

  List<T> _decoded<T>(
    String key,
    T Function(String id, Map<String, dynamic> data) decode,
  ) =>
      [
        for (final m in _snapshot[key] ?? const <Map<String, dynamic>>[])
          decode(asStringOr(m['id']), m),
      ];

  /// The sections of a notebook, as shown: snapshot plus overlay.
  List<Section> knownSections(String notebookId) => _applySections(
      notebookId, _decoded(sectionsKey(notebookId), Section.fromMap));

  /// The pages of a section, as shown.
  List<NotePage> knownPages(String notebookId, String sectionId) => _applyPages(
      notebookId,
      sectionId,
      _decoded(pagesKey(notebookId, sectionId), NotePage.fromMap));

  /// Every page of a notebook this device has seen or made.
  List<NotePage> knownPagesOfNotebook(String notebookId) {
    final out = <String, NotePage>{};
    final prefix = 'pages:$notebookId/';
    for (final key in _snapshot.keys.where((k) => k.startsWith(prefix))) {
      for (final p in _decoded(key, NotePage.fromMap)) {
        out[p.id] = p;
      }
    }
    for (final e in _pendingPages.entries) {
      final m = e.value.model;
      if (e.value.deleted) {
        out.remove(e.key);
      } else if (m != null && m.notebookId == notebookId) {
        out[e.key] = m;
      }
    }
    return out.values.toList();
  }

  NotePage? knownPage(String notebookId, String pageId) =>
      knownPagesOfNotebook(notebookId).where((p) => p.id == pageId).firstOrNull;

  // ---------------------------------------------------- the overlay

  void putNotebook(Notebook nb) {
    _pendingNotebooks[nb.id] = _Pending(nb);
    _changed();
  }

  void removeNotebook(String id) {
    for (final s in knownSections(id)) {
      _pendingSections[s.id] = _Pending(null);
    }
    for (final p in knownPagesOfNotebook(id)) {
      _pendingPages[p.id] = _Pending(null);
    }
    _pendingNotebooks[id] = _Pending(null);
    _changed();
  }

  void putSection(Section s) {
    _pendingSections[s.id] = _Pending(s);
    _changed();
  }

  void removeSection(String notebookId, String sectionId) {
    for (final p in knownPages(notebookId, sectionId)) {
      _pendingPages[p.id] = _Pending(null);
    }
    _pendingSections[sectionId] = _Pending(null);
    _changed();
  }

  void putPage(NotePage p) {
    _pendingPages[p.id] = _Pending(p);
    _changed();
  }

  void removePage(String id) {
    _pendingPages[id] = _Pending(null);
    _changed();
  }

  /// A change for [docId] reached the server: its overlay entry now has a
  /// short life, in case the server's stream never repeats it.
  void settled(String docId) {
    final now = DateTime.now();
    _pendingNotebooks[docId]?.settledAt = now;
    _pendingSections[docId]?.settledAt = now;
    _pendingPages[docId]?.settledAt = now;
    _changed();
  }

  bool get hasPending =>
      _pendingNotebooks.isNotEmpty ||
      _pendingSections.isNotEmpty ||
      _pendingPages.isNotEmpty;

  void _expire<T>(Map<String, _Pending<T>> pending) {
    final now = DateTime.now();
    pending.removeWhere((_, p) =>
        p.settledAt != null && now.difference(p.settledAt!) > settleGrace);
  }

  /// Drops overlay entries the server now agrees with.
  void _reconcile<T>(
    Map<String, _Pending<T>> pending,
    List<T> server,
    String Function(T) idOf,
    Map<String, dynamic> Function(T) encode,
    bool Function(T) inScope,
  ) {
    final byId = {for (final s in server) idOf(s): s};
    pending.removeWhere((id, p) {
      final model = p.model;
      if (p.deleted) {
        // Gone from the server too — but only judge from a list it would
        // have been in.
        return !byId.containsKey(id) && p.settledAt != null;
      }
      if (model == null || !inScope(model)) return false;
      final theirs = byId[id];
      if (theirs == null) return false;
      return jsonEncode(encode(theirs)) == jsonEncode(encode(model));
    });
  }

  // ---------------------------------------------------- the lists

  List<Notebook> _applyNotebooks(String uid, List<Notebook> base) {
    _expire(_pendingNotebooks);
    final out = <String, Notebook>{for (final n in base) n.id: n};
    for (final e in _pendingNotebooks.entries) {
      final m = e.value.model;
      if (e.value.deleted) {
        out.remove(e.key);
      } else if (m != null &&
          (m.ownerId == uid || m.collaboratorUids.contains(uid))) {
        out[e.key] = m;
      }
    }
    return List.unmodifiable(out.values);
  }

  List<Section> _applySections(String notebookId, List<Section> base) {
    _expire(_pendingSections);
    final out = <String, Section>{for (final s in base) s.id: s};
    for (final e in _pendingSections.entries) {
      final m = e.value.model;
      if (e.value.deleted) {
        out.remove(e.key);
      } else if (m != null && m.notebookId == notebookId) {
        out[e.key] = m;
      }
    }
    final list = out.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return List.unmodifiable(list);
  }

  List<NotePage> _applyPages(
      String notebookId, String sectionId, List<NotePage> base) {
    _expire(_pendingPages);
    final out = <String, NotePage>{for (final p in base) p.id: p};
    for (final e in _pendingPages.entries) {
      final m = e.value.model;
      if (e.value.deleted) {
        out.remove(e.key);
      } else if (m != null &&
          m.notebookId == notebookId &&
          m.sectionId == sectionId) {
        out[e.key] = m;
      }
    }
    final list = out.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return List.unmodifiable(list);
  }

  // ---------------------------------------------------- the streams

  Stream<List<Notebook>> notebooks(
    String uid,
    Stream<List<Notebook>> Function() server,
  ) =>
      _watch<Notebook>(
        key: notebooksKey(uid),
        server: server,
        decode: Notebook.fromMap,
        encode: (n) => n.toMap(),
        idOf: (n) => n.id,
        apply: (base) => _applyNotebooks(uid, base),
        reconcile: (data) => _reconcile(_pendingNotebooks, data, (n) => n.id,
            (n) => n.toMap(), (n) => true),
      );

  Stream<List<Section>> sections(
    String notebookId,
    Stream<List<Section>> Function() server,
  ) =>
      _watch<Section>(
        key: sectionsKey(notebookId),
        server: server,
        decode: Section.fromMap,
        encode: (s) => s.toMap(),
        idOf: (s) => s.id,
        apply: (base) => _applySections(notebookId, base),
        reconcile: (data) => _reconcile(_pendingSections, data, (s) => s.id,
            (s) => s.toMap(), (s) => s.notebookId == notebookId),
      );

  Stream<List<NotePage>> pages(
    String notebookId,
    String sectionId,
    Stream<List<NotePage>> Function() server,
  ) =>
      _watch<NotePage>(
        key: pagesKey(notebookId, sectionId),
        server: server,
        decode: NotePage.fromMap,
        encode: (p) => p.toMap(),
        idOf: (p) => p.id,
        apply: (base) => _applyPages(notebookId, sectionId, base),
        reconcile: (data) => _reconcile(
            _pendingPages,
            data,
            (p) => p.id,
            (p) => p.toMap(),
            (p) => p.notebookId == notebookId && p.sectionId == sectionId),
      );

  Stream<List<T>> _watch<T>({
    required String key,
    required Stream<List<T>> Function() server,
    required T Function(String id, Map<String, dynamic> data) decode,
    required Map<String, dynamic> Function(T) encode,
    required String Function(T) idOf,
    required List<T> Function(List<T> base) apply,
    required void Function(List<T> serverData) reconcile,
  }) {
    late StreamController<List<T>> controller;
    StreamSubscription<List<T>>? sub;
    StreamSubscription<void>? changes;
    Timer? retry;
    List<T>? base;
    var cancelled = false;

    void emit() {
      final b = base;
      if (cancelled || b == null) return;
      controller.add(apply(b));
    }

    void subscribe() {
      if (cancelled || _disposed) return;
      sub = server().listen(
        (data) {
          base = data;
          _snapshot[key] = [
            for (final d in data) {'id': idOf(d), ...encode(d)},
          ];
          _persistSoon();
          reconcile(data);
          emit();
        },
        onError: (Object e, StackTrace st) {
          // Offline, or signed out. Keep serving what we have — the snapshot
          // if there is one, an empty list otherwise, so the screens settle
          // instead of waiting for ever — and try the server again later.
          sub?.cancel();
          sub = null;
          base ??= const [];
          emit();
          retry?.cancel();
          retry = Timer(retryAfterError, subscribe);
        },
        onDone: () {
          sub = null;
          if (cancelled || _disposed) return;
          retry?.cancel();
          retry = Timer(retryAfterError, subscribe);
        },
      );
    }

    controller = StreamController<List<T>>(
      onListen: () async {
        await load();
        if (cancelled) return;
        final cached = _snapshot[key];
        if (cached != null) {
          base = [for (final m in cached) decode(asStringOr(m['id']), m)];
          emit();
        }
        changes = _changes.stream.listen((_) => emit());
        subscribe();
      },
      onCancel: () {
        cancelled = true;
        sub?.cancel();
        changes?.cancel();
        retry?.cancel();
      },
    );
    return controller.stream;
  }

  void dispose() {
    _disposed = true;
    // A snapshot still waiting on the debounce is written now rather than
    // lost: the app closing is exactly when the last server answer matters.
    if (_persistTimer?.isActive ?? false) {
      _persistTimer!.cancel();
      if (_loaded) unawaited(_store.write(_file, {'keys': _snapshot}));
    }
    _persistTimer?.cancel();
    _changes.close();
  }
}
