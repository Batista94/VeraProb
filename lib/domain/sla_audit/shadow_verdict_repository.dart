import 'shadow_verdict.dart';

/// Port (abstract repository) for the Shadow Verdict Validation System.
///
/// **Architecture guarantees:**
/// - [save] is idempotent on (organization_id, set_id, contract_id) — the engine
///   can re-run without duplicating entries (INV-11).
/// - [syncManualVerdicts] is the ONLY method that mutates divergence/manual fields.
///   Engine-produced fields are immutable at the DB level (INV-7).
/// - All queries are tenant-scoped via [organizationId] (INV-1).
/// - No delete operation exists (INV-7 — append-only ledger).
abstract class ShadowVerdictRepository {
  /// Persists a shadow verdict.
  ///
  /// Idempotent: a second call with the same (organization_id, set_id, contract_id)
  /// is silently ignored — the engine cannot overwrite its own shadow verdict.
  Future<void> save(ShadowVerdict verdict);

  /// Returns shadow verdicts for an org in the given UTC date range, newest first.
  Future<List<ShadowVerdict>> findByOrganization({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
    int limit = 100,
  });

  /// Returns only divergent entries (false_positive + false_negative) for drill-down.
  Future<List<ShadowVerdict>> findDivergent({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
  });

  /// Syncs human decisions from [sanction_review_queue] into shadow verdicts.
  ///
  /// For each shadow verdict with [ShadowDivergenceType.pendingManual], looks up
  /// the matching sanction queue entry by (organization_id, set_id, contract_id).
  /// If the entry's status is 'applied' or 'rejected', updates the shadow verdict's
  /// manual fields and recomputes [ShadowDivergenceType].
  ///
  /// Returns the count of shadow verdicts updated.
  Future<int> syncManualVerdicts({required String organizationId});
}
