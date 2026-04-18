/// Forensic Audit Signature: CX-05-v3.0 / Concurrency
/// Security Guard: INV-13 — UX-layer concurrency helper; authority for
/// throttling lives in [ForensicThrottleGateway] (server-side RPC).
///
/// FIFO-ordered semaphore that caps the number of in-flight async tasks.
///
/// **Scope:** UX smoothing only — prevents burst fan-out (e.g. 30 parallel
/// hash-verify requests on a batch evidence upload). NOT a security
/// boundary. A modified client can trivially skip this governor; rate-limit
/// enforcement must always happen server-side.
library;

import 'dart:async';
import 'dart:collection';

/// Typedef for the work delegated to [SmartConcurrencyGovernor.run].
typedef ConcurrencyTask<T> = Future<T> Function();

/// FIFO semaphore capping concurrent execution to [maxConcurrent] tasks.
///
/// Callers submit work via [run]; queued callers are released in arrival
/// order as slots free up. No timeouts, no back-pressure signalling — this
/// is a passive smoothing layer, not a rate-limiter.
class SmartConcurrencyGovernor {
  final int maxConcurrent;

  int _available;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  SmartConcurrencyGovernor({this.maxConcurrent = 10})
    : _available = maxConcurrent,
      assert(maxConcurrent > 0, 'maxConcurrent must be > 0');

  /// Returns the number of tasks currently queued waiting for a slot.
  int get queuedCount => _waiters.length;

  /// Returns the number of in-flight tasks holding a slot.
  int get inFlightCount => maxConcurrent - _available;

  /// Executes [task] under the concurrency cap, releasing the slot even if
  /// [task] throws. Errors propagate to the caller unchanged.
  Future<T> run<T>(ConcurrencyTask<T> task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_available > 0) {
      _available--;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    _available++;
  }
}
