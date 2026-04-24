import '../concurrency_exception.dart';
import 'justification_audit_log.dart';
import 'justification_status.dart';
import 'sla_justification.dart';

/// Abstract repository interface for SLA justification operations (CX-05).
///
/// Implementations: InMemory (tests), Supabase (production).
/// All operations enforce tenant isolation (INV-1) via [organizationId].
abstract class SLAJustificationRepository {
  // ── CRUD ───────────────────────────────────────────────────────────────────

  /// Persists a new SLA justification. Returns the created entity.
  Future<SLAJustification> create(SLAJustification justification);

  /// Loads a single justification by [id], scoped to [organizationId] (INV-1).
  /// Returns null when not found or outside tenant scope.
  Future<SLAJustification?> findById({
    required String id,
    required String organizationId,
  });

  /// Checks if a justification already exists for the given forensic anchor.
  /// Used by CX05-INV-20 (Linkage Integrity) to prevent duplicate submissions
  /// for the same vehicle + event combination.
  Future<SLAJustification?> findByVehicleAndEvent({
    required String vehicleId,
    required DateTime occurrenceTimestamp,
    required String organizationId,
  });

  /// Updates only the review fields (status, reviewer, resolution notes).
  Future<SLAJustification> updateStatus({
    required String id,
    required String organizationId,
    required JustificationStatus status,
    required String? reviewerId,
    required String? resolutionNotes,
    required DateTime reviewedAtUtc,
  });

  /// Returns all PENDING justifications older than [cutoffUtc].
  /// Used by the batch expiration job (CX05-INV-22).
  ///
  /// **Deprecated in favour of [findExpiredPendingPaged].** Kept for backwards
  /// compatibility with existing test fixtures that have not yet been migrated.
  Future<List<SLAJustification>> findExpiredPlanned({
    required DateTime cutoffUtc,
    required String organizationId,
  });

  /// Returns a page of PENDING justifications older than [cutoffUtc].
  ///
  /// Uses cursor-based pagination to prevent OOM on large datasets.
  /// Pass [afterId] (the last `id` from the previous page) to advance.
  /// [limit] controls page size — default 500 records per page.
  /// Returns an empty list when no more records remain.
  Future<List<SLAJustification>> findExpiredPendingPaged({
    required DateTime cutoffUtc,
    required String organizationId,
    required int limit,
    String? afterId,
  });

  /// Atomically updates [id]'s status from [expectedCurrentStatus] to
  /// [newStatus] using a `WHERE status = <expected>` clause.
  ///
  /// Returns the number of rows affected:
  /// - `1` — success, status was as expected and updated.
  /// - `0` — concurrent modification detected: another process already changed
  ///   the status before this call arrived. Callers must throw
  ///   [ConcurrencyException] when they receive `0`.
  ///
  /// This prevents the TOCTOU race condition where two concurrent approvals
  /// both read `status = PENDING` and both succeed.
  @Deprecated(
    'Use updateStatusWithAuditLog for atomic operations. '
    'Separate calls create race conditions (Red Team ID 2).',
  )
  Future<int> updateStatusAtomic({
    required String id,
    required String organizationId,
    required JustificationStatus expectedCurrentStatus,
    required JustificationStatus newStatus,
    required String? reviewerId,
    required String? resolutionNotes,
    required DateTime reviewedAtUtc,
  });

  // ── Audit Trail ────────────────────────────────────────────────────────────

  /// Appends an immutable audit log entry for a status transition.
  /// Append-only — no update or delete (INV-3).
  @Deprecated(
    'Use updateStatusWithAuditLog for atomic operations. '
    'Separate calls create race conditions (Red Team ID 2).',
  )
  Future<void> appendAuditLog(JustificationAuditLog log);

  // ── Atomic Operations (Red Team v2.1) ──────────────────────────────────────

  /// Atomically updates status + appends audit log + schedules evidence deletion.
  ///
  /// **Red Team v2.1 Remediation (ID 2):** Replaces separate `updateStatusAtomic`
  /// + `appendAuditLog` calls with a single transactional RPC.
  ///
  /// Returns the number of rows affected:
  /// - `1` — success (status updated, audit logged, deletion scheduled if needed)
  /// - `0` — concurrency conflict (entire transaction rolled back, no partial state)
  ///
  /// **Forensic Guarantee:** If this method returns 0, NO audit log entry exists
  /// and NO deletion queue entry was created. The justification status is unchanged.
  ///
  /// **Evidence Lifecycle:** If [newStatus] is REJECTED or EXPIRED, all URLs in
  /// [evidenceUrls] are scheduled for deletion after 7 days. If the status update
  /// fails due to concurrency, no deletion is scheduled (prevents "ghost deletions").
  Future<int> updateStatusWithAuditLog({
    required String id,
    required String organizationId,
    required JustificationStatus expectedCurrentStatus,
    required JustificationStatus newStatus,
    required String? reviewerId,
    required String? resolutionNotes,
    required DateTime reviewedAtUtc,
    required String callerRole,
    required List<String> evidenceUrls,
  });
}
