/// Forensic Audit Signature: CX-05-v3.0 / Concurrency / State
/// Security Guard: INV-13 — UX-layer semaphore; NOT a security boundary.
///
/// Exposes a singleton [SmartConcurrencyGovernor] for hash-verify fan-out
/// smoothing. Throttle authority still lives server-side in
/// [ForensicThrottleGateway].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/concurrency/smart_concurrency_governor.dart';

/// Process-wide governor. Not auto-disposed — the slot budget must be shared
/// across every caller (evidence verifier, uploaders) to cap true concurrency.
final smartConcurrencyGovernorProvider = Provider<SmartConcurrencyGovernor>((
  ref,
) {
  return SmartConcurrencyGovernor();
});
