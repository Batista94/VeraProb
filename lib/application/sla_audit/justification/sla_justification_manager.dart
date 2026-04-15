import 'package:uuid/uuid.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/authorization_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_audit_log.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_repository.dart';
import 'submit_sla_justification_command.dart';

/// Central orchestrator for the SLA Justification Layer (CX-05).
///
/// Implements all forensic invariants:
/// - **CX05-INV-20 (Linkage Integrity):** Validates that the event exists
///   in vehicle history before accepting a justification.
/// - **CX05-INV-21 (State Immutability):** Approval NEVER alters the
///   `VehicleOperationalState`. Only toggles `isPenaltyActive` in SLA.
/// - **CX05-INV-22 (Expiration Window):** Rejects submissions outside
///   the configurable time window (default: 24 hours).
/// - **CX05-INV-23 (Evidence Sealing):** Validates that SHA-256 hashes
///   were provided for every evidence file. Hashes are pre-computed by the
///   client from raw file bytes before Supabase upload for performance.
///
/// **Authority Sovereignty:** `approveJustification` and `rejectJustification`
/// enforce RBAC internally via [RbacService]. The Manager does NOT trust that
/// the caller validated authority externally.
///
/// Every status transition generates a [JustificationAuditLog] entry with
/// full actor attribution (userId, callerRole, previousStatus, newStatus,
/// timestamp).
class SLAJustificationManager {
  final TenantValidationService _tenantValidator;
  final SLAJustificationRepository _repository;
  final RbacService _rbac;
  final IDateTimeProvider _clock;

  /// Configurable expiration window. Default: 24 hours after the event.
  final Duration expirationWindow;

  /// Callback to verify that a vehicle event exists in the history.
  /// Returns `true` if a state transition was recorded for [vehicleId]
  /// at [eventTimestamp]. This decouples the Manager from the Normalizer's
  /// internal storage, satisfying Clean Architecture layer bounds.
  final Future<bool> Function({
    required String vehicleId,
    required DateTime eventTimestamp,
    required String organizationId,
  })
  eventExistsChecker;

  SLAJustificationManager({
    required TenantValidationService tenantValidator,
    required SLAJustificationRepository repository,
    required RbacService rbac,
    required IDateTimeProvider clock,
    required this.eventExistsChecker,
    this.expirationWindow = const Duration(hours: 24),
  }) : _tenantValidator = tenantValidator,
       _repository = repository,
       _rbac = rbac,
       _clock = clock;

  /// Submits a new SLA justification for a vehicle infraction event.
  ///
  /// Enforces:
  /// - CX05-INV-20: Event must exist in vehicle history.
  /// - CX05-INV-22: Must be within [expirationWindow] of the event.
  /// - CX05-INV-23: Evidence hashes count must match evidence URLs count.
  /// - Description minimum 10 characters.
  Future<SLAJustification> submitJustification(
    SubmitSLAJustificationCommand command,
  ) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync ────────────────────────────
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // ── Step 2: Validate category ────────────────────────────────────────
    final SLAJustificationCategory category;
    try {
      category = SLAJustificationCategory.fromDb(command.category);
    } on ArgumentError {
      throw DomainException(
        'Invalid justification category: ${command.category}',
      );
    }

    // ── Step 3: Description validation (min 10 chars) ────────────────────
    if (command.description.trim().length < 10) {
      throw const DomainException(
        'Description must be at least 10 characters.',
      );
    }

    // ── Step 4: CX05-INV-23 (Evidence Sealing) ──────────────────────────
    if (command.evidenceHashes.isEmpty) {
      throw const DomainException(
        'Evidence required: at least one SHA-256 hash must be provided.',
      );
    }
    if (command.evidenceUrls.length != command.evidenceHashes.length) {
      throw const DomainException(
        'Evidence sealing error: URL count must match hash count (CX05-INV-23).',
      );
    }
    for (final hash in command.evidenceHashes) {
      if (hash.length != 64 || !_isHexString(hash)) {
        throw DomainException(
          'Invalid SHA-256 hash: "$hash". Must be 64 hex characters.',
        );
      }
    }

    final now = _clock.nowUtc();

    // ── Step 5: CX05-INV-22 (Expiration Window) ─────────────────────────
    final elapsed = now.difference(command.eventTimestamp);
    if (elapsed > expirationWindow) {
      throw DomainException(
        'Justification window expired: event occurred '
        '${elapsed.inHours}h ago, limit is '
        '${expirationWindow.inHours}h (CX05-INV-22).',
      );
    }

    // ── Step 6: CX05-INV-20 (Linkage Integrity) ─────────────────────────
    final eventExists = await eventExistsChecker(
      vehicleId: command.vehicleId,
      eventTimestamp: command.eventTimestamp,
      organizationId: command.organizationId,
    );
    if (!eventExists) {
      throw const DomainException(
        'No matching event found for this vehicle and timestamp '
        '(CX05-INV-20).',
      );
    }

    // ── Step 7: Create justification ─────────────────────────────────────
    final id = const Uuid().v4();
    final justification = SLAJustification(
      id: id,
      organizationId: command.organizationId,
      vehicleId: command.vehicleId,
      eventTimestamp: command.eventTimestamp,
      category: category,
      description: command.description,
      evidenceUrls: List.unmodifiable(command.evidenceUrls),
      evidenceHashes: List.unmodifiable(command.evidenceHashes),
      status: JustificationStatus.pending,
      createdAt: now,
      reviewerId: null,
      resolutionNotes: null,
    );
    await _repository.create(justification);

    // ── Step 8: Audit Trail — initial PENDING log ────────────────────────
    await _repository.appendAuditLog(
      JustificationAuditLog(
        id: const Uuid().v4(),
        justificationId: id,
        userId: command.callerUserId,
        callerRole: 'SUBMITTER',
        previousStatus: JustificationStatus.pending,
        newStatus: JustificationStatus.pending,
        timestamp: now,
      ),
    );

    return justification;
  }

  /// Approves a pending justification. Gestor exclusive (Dashboard).
  ///
  /// **Authority Sovereignty:** Validates [callerRole] internally via
  /// [RbacService.can] with [UserPermission.canReviewJustifications].
  /// Does NOT trust external caller validation.
  ///
  /// CX05-INV-21: This NEVER modifies `VehicleOperationalState`.
  /// The caller (SLA engine) reads the justification status to toggle
  /// `isPenaltyActive` — the physical event data remains immutable.
  Future<SLAJustification> approveJustification({
    required String justificationId,
    required String organizationId,
    required String reviewerId,
    required UserRole callerRole,
    required String? resolutionNotes,
  }) async {
    // ── RBAC Guard — Authority Sovereignty ────────────────────────────────
    _assertReviewAuthority(callerRole);

    final justification = await _loadPending(justificationId, organizationId);

    final now = _clock.nowUtc();
    final updated = await _repository.updateStatus(
      id: justificationId,
      organizationId: organizationId,
      status: JustificationStatus.approved,
      reviewerId: reviewerId,
      resolutionNotes: resolutionNotes,
      reviewedAtUtc: now,
    );

    await _repository.appendAuditLog(
      JustificationAuditLog(
        id: const Uuid().v4(),
        justificationId: justificationId,
        userId: reviewerId,
        callerRole: callerRole.name,
        previousStatus: justification.status,
        newStatus: JustificationStatus.approved,
        timestamp: now,
      ),
    );

    return updated;
  }

  /// Rejects a pending justification. Gestor exclusive (Dashboard).
  ///
  /// **Authority Sovereignty:** Validates [callerRole] internally via
  /// [RbacService.can] with [UserPermission.canReviewJustifications].
  /// Does NOT trust external caller validation.
  Future<SLAJustification> rejectJustification({
    required String justificationId,
    required String organizationId,
    required String reviewerId,
    required UserRole callerRole,
    required String resolutionNotes,
  }) async {
    // ── RBAC Guard — Authority Sovereignty ────────────────────────────────
    _assertReviewAuthority(callerRole);

    if (resolutionNotes.trim().length < 10) {
      throw const DomainException(
        'Resolution notes must be at least 10 characters.',
      );
    }

    final justification = await _loadPending(justificationId, organizationId);

    final now = _clock.nowUtc();
    final updated = await _repository.updateStatus(
      id: justificationId,
      organizationId: organizationId,
      status: JustificationStatus.rejected,
      reviewerId: reviewerId,
      resolutionNotes: resolutionNotes,
      reviewedAtUtc: now,
    );

    await _repository.appendAuditLog(
      JustificationAuditLog(
        id: const Uuid().v4(),
        justificationId: justificationId,
        userId: reviewerId,
        callerRole: callerRole.name,
        previousStatus: justification.status,
        newStatus: JustificationStatus.rejected,
        timestamp: now,
      ),
    );

    return updated;
  }

  /// Batch-expires all pending justifications older than [expirationWindow].
  ///
  /// CX05-INV-22: Called by a scheduled job or evaluated lazily on access.
  /// Each expiration generates an audit log entry with `userId = 'SYSTEM'`
  /// and `callerRole = 'SYSTEM'`.
  Future<int> expireStaleJustifications({
    required String organizationId,
  }) async {
    final now = _clock.nowUtc();
    final cutoff = now.subtract(expirationWindow);
    final stale = await _repository.findExpiredPending(
      cutoffUtc: cutoff,
      organizationId: organizationId,
    );

    for (final j in stale) {
      await _repository.updateStatus(
        id: j.id,
        organizationId: organizationId,
        status: JustificationStatus.expired,
        reviewerId: null,
        resolutionNotes:
            'Auto-expired: submission window elapsed (CX05-INV-22).',
        reviewedAtUtc: now,
      );

      await _repository.appendAuditLog(
        JustificationAuditLog(
          id: const Uuid().v4(),
          justificationId: j.id,
          userId: 'SYSTEM',
          callerRole: 'SYSTEM',
          previousStatus: JustificationStatus.pending,
          newStatus: JustificationStatus.expired,
          timestamp: now,
        ),
      );
    }

    return stale.length;
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  /// Internal RBAC guard for review operations.
  ///
  /// Throws [AuthorizationException] if the caller's role does not have
  /// [UserPermission.canReviewJustifications]. The Manager does NOT trust
  /// that the caller validated authority externally.
  void _assertReviewAuthority(UserRole callerRole) {
    if (!_rbac.can(callerRole, UserPermission.canReviewJustifications)) {
      throw AuthorizationException(
        'Role "${callerRole.name}" is not authorized to review justifications.',
        role: callerRole.name,
        requiredPermission: UserPermission.canReviewJustifications.name,
      );
    }
  }

  Future<SLAJustification> _loadPending(
    String justificationId,
    String organizationId,
  ) async {
    final j = await _repository.findById(
      id: justificationId,
      organizationId: organizationId,
    );
    if (j == null) {
      throw DomainException('Justification "$justificationId" not found.');
    }
    if (!j.isPending) {
      throw DomainException(
        'Justification "$justificationId" is already '
        '${j.status.dbValue}.',
      );
    }
    return j;
  }

  /// Validates that a string contains only hexadecimal characters.
  static bool _isHexString(String s) {
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);
  }
}
