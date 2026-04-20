/// Forensic Audit Signature: CX-05-v3.0 / Throttle
/// Security Guard: INV-1, INV-16, INV-18 Compliance Verified
/// Authorized By: VeraProb QA Security + Architect
///
/// Domain port for server-authoritative forensic throttle control.
///
/// **Why a port (not inline Supabase call):** Security primitives must live
/// behind a domain abstraction so the application handler stays independent
/// of the transport (INV-13). The infrastructure adapter invokes Postgres
/// RPCs that enforce JWT-claim tenancy fail-fast (INV-1) and persist backoff
/// state in a RLS-protected table (INV-2) — the client cannot bypass throttle
/// by restarting the app or calling REST directly.
library;

import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Gateway for forensic-failure throttle enforcement and recording.
///
/// Contract:
/// - [assertAllowed] throws [ThrottleBlockedException] when the caller is
///   still within a backoff window for their `(user_id, organization_id)`.
/// - [recordFailure] increments consecutive failures and extends the
///   `next_allowed_at` horizon using exponential backoff (server-computed).
/// - [recordSuccess] resets the counter to zero.
///
/// Implementations MUST enforce `organizationId` matches the authenticated
/// JWT claim (INV-1 fail-fast).
abstract class ForensicThrottleGateway {
  /// Verifies the caller is not currently throttled. Throws
  /// [ThrottleBlockedException] with the remaining wait time if blocked.
  Future<void> assertAllowed({required String organizationId});

  /// Records a forensic-integrity failure and advances the backoff window.
  Future<void> recordFailure({required String organizationId});

  /// Clears the failure counter for the caller after a successful submission.
  Future<void> recordSuccess({required String organizationId});
}

/// Raised by [ForensicThrottleGateway.assertAllowed] when the caller is
/// still within their backoff window.
///
/// [waitSeconds] is the remaining server-computed cooldown and should be
/// surfaced verbatim to the UI so the user sees a concrete retry time.
class ThrottleBlockedException extends DomainException {
  final int waitSeconds;

  const ThrottleBlockedException(this.waitSeconds)
    : super('Forensic throttle active. Retry after cooldown.');
}
