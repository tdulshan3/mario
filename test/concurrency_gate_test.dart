/// Unit tests for [ConcurrencyGate], which bounds how many Drive requests are
/// in flight at once. The cap is the whole point of the class, so these tests
/// drive it at microtask granularity rather than through the service.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mario/core/services/concurrency_gate.dart';

void main() {
  /// Runs [count] tasks through [gate], each blocking on its own completer,
  /// and reports the highest number admitted at any instant.
  ({List<Completer<void>> holds, List<Future<void>> runs, int Function() peak})
      harness(ConcurrencyGate gate, int count) {
    final holds = [for (var i = 0; i < count; i++) Completer<void>()];
    var peak = 0;
    final runs = [
      for (var i = 0; i < count; i++)
        gate.run(() async {
          if (gate.active > peak) peak = gate.active;
          await holds[i].future;
        })
    ];
    return (holds: holds, runs: runs, peak: () => peak);
  }

  test('admits up to the limit and queues the rest', () async {
    final gate = ConcurrencyGate(3);
    final h = harness(gate, 10);
    await Future<void>.delayed(Duration.zero);

    expect(h.peak(), 3);

    for (final c in h.holds) {
      c.complete();
    }
    await Future.wait(h.runs);
    expect(gate.active, 0);
  });

  test('a freed slot goes to one caller, not two', () async {
    // The race the class exists to survive: with a decrement-then-signal
    // release, a caller arriving in the turn between the decrement and the
    // woken waiter resuming takes the slot *and* the waiter takes one too,
    // briefly running limit+1 requests.
    final gate = ConcurrencyGate(2);
    final a = Completer<void>(), b = Completer<void>();
    final c = Completer<void>(), d = Completer<void>();
    var peak = 0;
    void mark() => peak = gate.active > peak ? gate.active : peak;

    final runs = <Future<void>>[
      gate.run(() async {
        mark();
        await a.future;
      }),
      gate.run(() async {
        mark();
        await b.future;
      }),
    ];
    await Future<void>.delayed(Duration.zero);
    runs.add(gate.run(() async {
      mark();
      await c.future;
    })); // queued waiter
    await Future<void>.delayed(Duration.zero);

    // Free a slot, and have a newcomer arrive in the very next microtask —
    // before the woken waiter has had a chance to resume.
    a.complete();
    scheduleMicrotask(() => runs.add(gate.run(() async {
          mark();
          await d.future;
        })));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(peak, lessThanOrEqualTo(2));

    for (final x in [b, c, d]) {
      x.complete();
    }
    await Future.wait(runs);
    expect(gate.active, 0);
  });

  test('a task that throws still releases its slot', () async {
    final gate = ConcurrencyGate(1);

    await expectLater(
      gate.run(() async => throw StateError('boom')),
      throwsStateError,
    );

    expect(gate.active, 0);
    expect(await gate.run(() async => 'ok'), 'ok');
  });

  test('waiters are admitted in arrival order', () async {
    final gate = ConcurrencyGate(1);
    final order = <int>[];
    final first = Completer<void>();

    final runs = <Future<void>>[
      gate.run(() async {
        order.add(0);
        await first.future;
      }),
    ];
    await Future<void>.delayed(Duration.zero);
    for (var i = 1; i <= 3; i++) {
      runs.add(gate.run(() async => order.add(i)));
    }

    first.complete();
    await Future.wait(runs);

    expect(order, [0, 1, 2, 3]);
  });
}
