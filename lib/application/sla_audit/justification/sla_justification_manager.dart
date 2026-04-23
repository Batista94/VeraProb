import 'package:uuid/uuid.dart';

// ignore_for_file: deprecated_member_use_from_same_package
// Rationale: `expireStaleJustifications` still uses `updateStatusAtomic` +
// `appendAuditLog` for batch expiration. Migration to a dedicated
// `expireJustificationsWithAuditLog` RPC is tracked as a post-v2.1 task.

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/authorization_exception.dart';
import 'package:veraprob/domain/sla_audit/concurrency_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_audit_log.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/sla_justification_repository.dart';
import 'contextual_signature_analyzer.dart';
import 'evidence_integrity_verifier.dart';
import 'evidence_validation_service.dart';
import 'submit_sla_justification_command.dart';
import 'xss_input_sanitizer.dart';

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
///   were provided for every evidence file. After persistence, the server
///   re-computes SHA-256 via streaming to detect post-submission tampering.
///
/// **Authority Sovereignty:** `approveJustification` and `rejectJustification`
/// enforce RBAC internally via [RbacService]. The Manager does NOT trust that
/// the caller validated authority externally.
///
/// **Race Condition Guard:** All review operations use `updateStatusAtomic`
/// (a `WHERE status='PENDING'` atomic clause at the DB level). If 0 rows are
/// updated, a [ConcurrencyException] is thrown — indicating that another
/// concurrent process already changed the status.
///
/// **Anti-Double Dipping:** `submitJustification` checks for an existing
/// justification for the vehicle+occurrence anchor before persisting a new one.
///
/// **OOM Prevention:** `expireStaleJustifications` uses cursor-based pagination
/// (`findExpiredPendingPaged`) with a hard `maxIterations` safety guard.
///
/// Every status transition generates a [JustificationAuditLog] entry with
/// full actor attribution (userId, callerRole, previousStatus, newStatus,
/// timestamp).
class SLAJustificationManager {
  final TenantValidationService _tenantValidator;
  final SLAJustificationRepository _repository;
  final RbacService _rbac;
  final IDateTimeProvider _clock;
  final EvidenceIntegrityVerifier _evidenceVerifier;
  final XssInputSanitizer _sanitizer;
  final ContextualSignatureAnalyzer _fileInspector;
  final EvidenceLinkChecker _linkChecker;

  /// Configurable expiration window. Default: 24 hours after the event.
  final Duration expirationWindow;

  /// Page size for the cursor-based batch expiration loop.
  static const int _expirePageSize = 500;

  /// Maximum loop iterations for batch expiration — safety guard against
  /// infinite loops caused by pathological DB state or cursor bugs.
  static const int _maxExpireIterations = 10000;

  /// Callback to verify that a vehicle event exists in the history.
  /// Forensic anchor: [vehicleId] + [occurrenceTimestamp] link back to the original history.
  /// Returns `true` if a state transition was recorded for [vehicleId]
  /// at [occurrenceTimestamp]. This decouples the Manager from the Normalizer's
  /// internal storage, satisfying Clean Architecture layer bounds.
  final Future<bool> Function({
    required String vehicleId,
    required DateTime occurrenceTimestamp,
    required String organizationId,
  })
  eventExistsChecker;

  SLAJustificationManager({
    required TenantValidationService tenantValidator,
    required SLAJustificationRepository repository,
    required RbacService rbac,
    required IDateTimeProvider clock,
    required EvidenceIntegrityVerifier evidenceVerifier,
    required XssInputSanitizer sanitizer,
    required ContextualSignatureAnalyzer fileInspector,
    required EvidenceLinkChecker linkChecker,
    required this.eventExistsChecker,
    this.expirationWindow = const Duration(hours: 24),
  }) : _tenantValidator = tenantValidator,
       _repository = repository,
       _rbac = rbac,
       _clock = clock,
       _evidenceVerifier = evidenceVerifier,
       _sanitizer = sanitizer,
       _fileInspector = fileInspector,
       _linkChecker = linkChecker;

  /// Submits a new SLA justification for a vehicle infraction event.
  ///
  /// Enforces:
  /// - CX05-INV-20: Event must exist in vehicle history.
  /// - CX05-INV-22: Must be within [expirationWindow] of the event.
  /// - CX05-INV-23: Evidence hash count must match evidence URL count; hashes
  ///   must be valid 64-char hex strings.
  /// - Anti-double dipping: Rejects if a justification for the same
  ///   vehicle+event anchor already exists.
  /// - Server-side hash re-verification: After persistence, recomputes SHA-256
  ///   via streaming and auto-rejects if any hash diverges (tamper detection).
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

    // ── Step 3: XSS Protection (Red Team ID 4) ───────────────────────────
    final sanitizedDescription = _sanitizer.sanitizeText(command.description);

    // ── Step 4: Description validation (min 10 chars) ────────────────────
    if (sanitizedDescription.trim().length < 10) {
      throw const DomainException(
        'Description must be at least 10 characters.',
      );
    }

    // ── Step 5: CX05-INV-23 (Evidence Sealing — format validation) ───────
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

    // ── Step 6: Binary Sampling & Magic Bytes (Fix 4/5 — Jump Sampling N=7) ─
    // File size is fetched internally via authenticated HEAD (Zero-Trust INV-18).
    await _fileInspector.validateEvidence(command.evidenceUrls);

    final now = _clock.nowUtc();

    // ── Step 7: CX05-INV-22 (Expiration Window) ─────────────────────────
    final elapsed = now.difference(command.occurrenceTimestamp);
    if (elapsed > expirationWindow) {
      throw DomainException(
        'Justification window expired: event occurred '
        '${elapsed.inHours}h ago, limit is '
        '${expirationWindow.inHours}h (CX05-INV-22).',
      );
    }

    // ── Step 8: CX05-INV-20 (Linkage Integrity) ─────────────────────────
    final eventExists = await eventExistsChecker(
      vehicleId: command.vehicleId,
      occurrenceTimestamp: command.occurrenceTimestamp,
      organizationId: command.organizationId,
    );
    if (!eventExists) {
      throw const DomainException(
        'No matching event found for this vehicle and timestamp '
        '(CX05-INV-20).',
      );
    }

    // ── Step 9: Anti-Double Dipping ──────────────────────────────────────
    final existing = await _repository.findByVehicleAndEvent(
      vehicleId: command.vehicleId,
      occurrenceTimestamp: command.occurrenceTimestamp,
      organizationId: command.organizationId,
    );
    if (existing != null) {
      throw DomainException(
        'A justification for vehicle "${command.vehicleId}" at this '
        'timestamp already exists (id: ${existing.id}).',
      );
    }

    // ── Step 10: Create justification ────────────────────────────────────
    final id = const Uuid().v4();
    final justification = SLAJustification(
      id: id,
      organizationId: command.organizationId,
      vehicleId: command.vehicleId,
      occurrenceTimestamp: command.occurrenceTimestamp,
      category: category,
      description: sanitizedDescription, // Use sanitized version
      evidenceUrls: List.unmodifiable(command.evidenceUrls),
      evidenceHashes: List.unmodifiable(command.evidenceHashes),
      status: JustificationStatus.pending,
      createdAt: now,
      reviewerId: null,
      resolutionNotes: null,
    );
    await _repository.create(justification);

    // ── Step 11: CX05-INV-23 (Server-side hash re-verification) ──────────
    // Re-compute SHA-256 from raw bytes after persistence to detect any
    // tampering between client upload and DB record creation.
    final mismatches = await _evidenceVerifier.verifyAll(
      evidenceUrls: command.evidenceUrls,
      declaredHashes: command.evidenceHashes,
    );
    if (mismatches.isNotEmpty) {
      // Auto-reject: evidence tampered post-submission.
      // Uses updateStatusWithAuditLog (atomic RPC) to atomically update status,
      // append the system audit log, and schedule evidence deletion.
      await _repository.updateStatusWithAuditLog(
        id: id,
        organizationId: command.organizationId,
        expectedCurrentStatus: JustificationStatus.pending,
        newStatus: JustificationStatus.rejected,
        reviewerId: null,
        resolutionNotes:
            'Auto-rejected: server-side hash re-verification failed for '
            'evidence index(es) $mismatches (CX05-INV-23).',
        reviewedAtUtc: now,
        callerRole: 'SYSTEM',
        evidenceUrls: command.evidenceUrls,
      );
      throw DomainException(
        'Evidence integrity check failed: hashes do not match for '
        'index(es) $mismatches (CX05-INV-23).',
      );
    }

    // ── Step 12: Audit Trail — initial PENDING log ───────────────────────
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
  /// **Race Condition Guard:** Uses [updateStatusWithAuditLog] with atomic
  /// transaction. If 0 is returned, throws [ConcurrencyException] — another
  /// concurrent process already acted on this justification.
  ///
  /// **Red Team ID 2 (Atomicity):** Status update + audit log + deletion queue
  /// in a single transaction. No "ghost deletions" possible.
  ///
  /// **Red Team ID 4 (XSS):** Sanitizes resolutionNotes before persistence.
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

    final now = _clock.nowUtc();

    // ── XSS Protection (Red Team ID 4) ───────────────────────────────────
    final sanitizedNotes = resolutionNotes != null
        ? _sanitizer.sanitizeText(resolutionNotes)
        : null;

    // ── Atomic Transaction (Red Team ID 2) ───────────────────────────────
    // Fetch evidence URLs for deletion queue
    final justification = await _repository.findById(
      id: justificationId,
      organizationId: organizationId,
    );
    if (justification == null) {
      throw DomainException('Justification "$justificationId" not found.');
    }

    // Fix 5: Evidence Availability Gate — cannot seal verdict over missing files
    await _assertEvidenceAvailable(justification.evidenceUrls);

    final rowsAffected = await _repository.updateStatusWithAuditLog(
      id: justificationId,
      organizationId: organizationId,
      expectedCurrentStatus: JustificationStatus.pending,
      newStatus: JustificationStatus.approved,
      reviewerId: reviewerId,
      resolutionNotes: sanitizedNotes,
      reviewedAtUtc: now,
      callerRole: callerRole.name,
      evidenceUrls: justification.evidenceUrls,
    );

    if (rowsAffected == 0) {
      throw ConcurrencyException(
        'Justification "$justificationId" was already modified by a '
        'concurrent operation. Reload and retry.',
      );
    }

    // Reload to get the post-update entity
    final updated = await _repository.findById(
      id: justificationId,
      organizationId: organizationId,
    );
    if (updated == null) {
      throw DomainException(
        'Justification "$justificationId" not found after atomic update.',
      );
    }

    return updated;
  }

  /// Rejects a pending justification. Gestor exclusive (Dashboard).
  ///
  /// **Authority Sovereignty:** Validates [callerRole] internally via
  /// [RbacService.can] with [UserPermission.canReviewJustifications].
  /// Does NOT trust external caller validation.
  ///
  /// **Race Condition Guard:** Uses [updateStatusWithAuditLog] with atomic
  /// transaction. If 0 is returned, throws [ConcurrencyException].
  ///
  /// **Red Team ID 2 (Atomicity):** Status update + audit log + deletion queue
  /// in a single transaction. Evidence scheduled for removal after 7-day grace.
  ///
  /// **Red Team ID 4 (XSS):** Sanitizes resolutionNotes before persistence.
  ///
  /// **Red Team ID 6 (Storage Leak):** Rejected justifications schedule evidence
  /// for deletion via `evidence_deletion_queue`.
  Future<SLAJustification> rejectJustification({
    required String justificationId,
    required String organizationId,
    required String reviewerId,
    required UserRole callerRole,
    required String resolutionNotes,
  }) async {
    // ── RBAC Guard — Authority Sovereignty ────────────────────────────────
    _assertReviewAuthority(callerRole);

    // ── XSS Protection (Red Team ID 4) ───────────────────────────────────
    final sanitizedNotes = _sanitizer.sanitizeText(resolutionNotes);

    if (sanitizedNotes.trim().length < 10) {
      throw const DomainException(
        'Resolution notes must be at least 10 characters.',
      );
    }

    final now = _clock.nowUtc();

    // ── Atomic Transaction (Red Team ID 2 + ID 6) ────────────────────────
    // Fetch evidence URLs for deletion queue
    final justification = await _repository.findById(
      id: justificationId,
      organizationId: organizationId,
    );
    if (justification == null) {
      throw DomainException('Justification "$justificationId" not found.');
    }

    // Fix 5: Evidence Availability Gate — cannot seal verdict over missing files
    await _assertEvidenceAvailable(justification.evidenceUrls);

    final rowsAffected = await _repository.updateStatusWithAuditLog(
      id: justificationId,
      organizationId: organizationId,
      expectedCurrentStatus: JustificationStatus.pending,
      newStatus: JustificationStatus.rejected,
      reviewerId: reviewerId,
      resolutionNotes: sanitizedNotes,
      reviewedAtUtc: now,
      callerRole: callerRole.name,
      evidenceUrls: justification.evidenceUrls,
    );

    if (rowsAffected == 0) {
      throw ConcurrencyException(
        'Justification "$justificationId" was already modified by a '
        'concurrent operation. Reload and retry.',
      );
    }

    // Reload to get the post-update entity
    final updated = await _repository.findById(
      id: justificationId,
      organizationId: organizationId,
    );
    if (updated == null) {
      throw DomainException(
        'Justification "$justificationId" not found after atomic update.',
      );
    }

    return updated;
  }

  /// Batch-expires all pending justifications older than [expirationWindow].
  ///
  /// CX05-INV-22: Called by a scheduled job or evaluated lazily on access.
  /// Each expiration generates an audit log entry with `userId = 'SYSTEM'`
  /// and `callerRole = 'SYSTEM'`.
  ///
  /// **OOM Prevention:** Processes records in pages of [_expirePageSize] using
  /// cursor-based pagination ([findExpiredPendingPaged]). A hard cap of
  /// [_maxExpireIterations] prevents infinite loops in pathological DB states.
  ///
  /// **Race Condition Guard:** Each expiration uses [updateStatusAtomic]. If
  /// a record was concurrently approved/rejected between fetch and update,
  /// 0 rows are affected and the record is silently skipped (correct — it is
  /// no longer PENDING).
  Future<int> expireStaleJustifications({
    required String organizationId,
  }) async {
    final now = _clock.nowUtc();
    final cutoff = now.subtract(expirationWindow);

    var totalExpired = 0;
    String? cursor;

    for (var iteration = 0; iteration < _maxExpireIterations; iteration++) {
      final page = await _repository.findExpiredPendingPaged(
        cutoffUtc: cutoff,
        organizationId: organizationId,
        limit: _expirePageSize,
        afterId: cursor,
      );

      if (page.isEmpty) break;

      for (final j in page) {
        final rows = await _repository.updateStatusAtomic(
          id: j.id,
          organizationId: organizationId,
          expectedCurrentStatus: JustificationStatus.pending,
          newStatus: JustificationStatus.expired,
          reviewerId: null,
          resolutionNotes:
              'Auto-expired: submission window elapsed (CX05-INV-22).',
          reviewedAtUtc: now,
        );

        if (rows > 0) {
          totalExpired++;
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
      }

      cursor = page.last.id;

      // If the page was smaller than the limit, we've reached the last page.
      if (page.length < _expirePageSize) break;
    }

    return totalExpired;
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

  /// Validates that a string contains only hexadecimal characters.
  static bool _isHexString(String s) {
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);
  }

  /// Checks all evidence URLs in parallel (not sequentially).
  ///
  /// **Performance:** 10 photos → 1 round-trip latency, not 10× sequential.
  /// All HEAD requests fly concurrently via [Future.wait]; we only block once
  /// for the slowest response, not for the sum of all responses.
  Future<void> _assertEvidenceAvailable(List<String> evidenceUrls) async {
    final results = await Future.wait(evidenceUrls.map(_linkChecker.checkLink));

    final missing = [
      for (var i = 0; i < results.length; i++)
        if (results[i].status == EvidenceLinkStatus.missing) evidenceUrls[i],
    ];

    if (missing.isNotEmpty) {
      throw DomainException(
        'Cannot seal verdict: Evidence missing from storage '
        '(${missing.length} URL(s) unreachable). CX05-Fix-5.',
      );
    }
  }
}
