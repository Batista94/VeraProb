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
    required DateTime eventTimestamp,
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
  Future<List<SLAJustification>> findExpiredPending({
    required DateTime cutoffUtc,
    required String organizationId,
  });

  // ── Audit Trail ────────────────────────────────────────────────────────────

  /// Appends an immutable audit log entry for a status transition.
  /// Append-only — no update or delete (INV-3).
  Future<void> appendAuditLog(JustificationAuditLog log);
}
