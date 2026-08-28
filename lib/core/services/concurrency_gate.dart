/// ConcurrencyGate — a counting semaphore for outbound requests.
///
/// Drive answers a burst of parallel requests with `403 userRateLimitExceeded`,
/// so a page holding forty uncached images must not open forty connections.
///
/// Its own file rather than a private class inside [AssetSyncService] because
/// the interesting behaviour is a microtask-level race that can't be provoked
/// through the service's public API — the caller has to arrive in the exact
/// turn between a slot being freed and a waiter resuming. Testing that needs
/// direct access.
library;

import 'dart:async';

class ConcurrencyGate {
  ConcurrencyGate(this.limit) : assert(limit > 0);

  final int limit;

  /// Slots in use: held by a running task, or already handed to a woken waiter.
  int _active = 0;
  final _waiting = <Completer<void>>[];

  /// Requests currently admitted. Exposed for tests.
  int get active => _active;

  /// Runs [task] once a slot is free. Queued callers are admitted in arrival
  /// order, and a task that throws still gives its slot up.
  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= limit) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future; // resumes already holding a slot
    } else {
      _active++;
    }
    try {
      return await task();
    } finally {
      // Hand the slot straight to the next waiter rather than releasing it and
      // letting that waiter re-acquire. Completing a waiter only *schedules*
      // it, so with a decrement-then-signal release a caller arriving in
      // between sees a free slot and takes it — and then the woken waiter
      // takes one too, running limit+1 requests at once. Which is precisely
      // the burst the limit exists to prevent.
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }
}
