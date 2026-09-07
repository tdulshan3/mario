/// Changes waiting for the server, replayed in order when it is reachable.
///
/// Every structural change — a page created, a section renamed, a notebook
/// deleted — is applied locally at once and written here. The outbox then
/// tries the server immediately; when that fails for a reason that can pass
/// (no network, no token, a rate limit) it keeps the change and retries on a
/// backoff, and when it fails for a reason that cannot (the document is
/// already gone, permission denied) it drops the change rather than blocking
/// everything queued behind it. Order matters: a rename cannot reach the
/// server before the create it renames, so the queue stops at the first
/// retryable failure and resumes from there.
///
/// The outbox knows nothing about notebooks. It stores [PendingOp]s and hands
/// them to a `perform` callback; what an op means is the caller's business.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ai/json_coercion.dart';
import 'sync_store.dart';

/// One change waiting for the server.
class PendingOp {
  PendingOp({
    required this.id,
    required this.kind,
    required this.args,
    DateTime? createdAt,
    this.attempts = 0,
    this.lastError,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String kind;
  final Map<String, dynamic> args;
  final DateTime createdAt;
  int attempts;
  String? lastError;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'args': args,
        'createdAt': createdAt.toIso8601String(),
        'attempts': attempts,
        if (lastError != null) 'lastError': lastError,
      };

  factory PendingOp.fromJson(Map<String, dynamic> m) => PendingOp(
        id: asStringOr(m['id']),
        kind: asStringOr(m['kind']),
        args: asMap(m['args']) ?? const {},
        createdAt: asDateTime(m['createdAt'], DateTime.now()),
        attempts: asInt(m['attempts']) ?? 0,
        lastError: asString(m['lastError']),
      );
}

/// What to do with an op the server refused.
enum OpFailure {
  /// Keep it and try again later — offline, signed out, rate limited.
  retry,

  /// Let it go — it can never succeed, and everything behind it is waiting.
  drop,
}

class SyncOutbox {
  SyncOutbox({
    required SyncStore store,
    required this.perform,
    required this.classify,
    this.name = 'outbox',
    this.opTimeout = const Duration(seconds: 30),
    this.backoffs = const [
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ],
  }) : _store = store;

  final SyncStore _store;
  final Future<void> Function(PendingOp op) perform;
  final OpFailure Function(Object error) classify;
  final String name;

  /// A server call that has not answered by then is treated as offline. Both
  /// backends can otherwise hang for good on a half-open connection.
  final Duration opTimeout;
  final List<Duration> backoffs;

  final List<PendingOp> _ops = [];

  /// How many changes are waiting, for the status line.
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  final _settled = StreamController<PendingOp>.broadcast();

  /// Each op that reached the server (or was dropped), as it happens.
  Stream<PendingOp> get settled => _settled.stream;

  Future<void>? _loading;
  bool _loaded = false;
  bool _draining = false;
  bool _disposed = false;
  Timer? _retry;
  int _strikes = 0;

  List<PendingOp> get ops => List.unmodifiable(_ops);
  bool get isEmpty => _ops.isEmpty;

  /// The queue as it was left last time. Loaded once, before any use.
  Future<void> load() => _loading ??= () async {
        final data = await _store.read(name);
        if (data != null) {
          _ops.addAll(asMapList(data['ops']).map(PendingOp.fromJson));
        }
        _loaded = true;
        pendingCount.value = _ops.length;
      }();

  Future<void> add(PendingOp op) async {
    await load();
    _ops.add(op);
    await _persist();
    drainSoon();
  }

  /// Edits the queue in place — to fold a rename into the create it renames,
  /// or drop a create that a delete has made pointless.
  Future<void> mutate(void Function(List<PendingOp> ops) change) async {
    await load();
    change(_ops);
    await _persist();
  }

  Future<void> _persist() async {
    // Never write an unloaded queue over a real one on disk.
    if (!_loaded) return;
    pendingCount.value = _ops.length;
    await _store.write(name, {
      'ops': [for (final o in _ops) o.toJson()]
    });
  }

  /// Tries the server on the next tick.
  void drainSoon() {
    if (_disposed) return;
    _retry?.cancel();
    _retry = Timer(Duration.zero, () => unawaited(drain()));
  }

  /// Sends what is queued, in order, until the queue is empty or an op has to
  /// wait. Safe to call at any time; a drain already running is left to it.
  Future<void> drain() async {
    if (_disposed || _draining) return;
    _draining = true;
    try {
      await load();
      while (_ops.isNotEmpty && !_disposed) {
        final op = _ops.first;
        try {
          await perform(op).timeout(opTimeout);
        } catch (e) {
          if (classify(e) == OpFailure.drop) {
            _ops.remove(op);
            await _persist();
            _settled.add(op);
            continue;
          }
          op.attempts++;
          op.lastError = '$e';
          await _persist();
          _scheduleRetry();
          return;
        }
        _ops.remove(op);
        _strikes = 0;
        await _persist();
        _settled.add(op);
      }
      _retry?.cancel();
    } finally {
      _draining = false;
    }
  }

  void _scheduleRetry() {
    if (_disposed) return;
    final wait = backoffs[_strikes.clamp(0, backoffs.length - 1)];
    _strikes++;
    _retry?.cancel();
    _retry = Timer(wait, () => unawaited(drain()));
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _settled.close();
    pendingCount.dispose();
  }
}
