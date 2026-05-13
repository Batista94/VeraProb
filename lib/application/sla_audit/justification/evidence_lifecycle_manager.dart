/// Forensic Audit Signature: CX-06-v2.0
/// Remediation: Red Team ID 6 (Evidence Lifecycle — Hot/Cold/Legal Hold + Orphan Purge)
/// Security Guard: INV-3, INV-9, INV-24 Compliance Verified
/// Authorized By: VeraProb QA Security Lead
///
/// Enterprise Evidence Lifecycle Manager.
/// Replaces the Janitor (EvidenceCleanupService) with a retention-aware,
/// compliance-first lifecycle pipeline:
///   Hot Storage  →  Cold Storage  (after 90 days inactivity)
///   Legal Hold   →  permanent hold (blocks ALL transitions, even after 5 years)
///
/// **INV-3 (Append-Only Ledger):** contentHash is NEVER mutated. The SHA-256
/// sealed at ingest travels with the evidence record forever.
/// **INV-24 (Service Role Gate):** only Service Role clients may trigger
/// batch archiving or orphan purging. Standard users receive IntegrityException.
///
/// **Physical Deletion Policy (INV-3):** Business evidence with a DB record
/// is NEVER physically deleted. The ONLY permissible physical deletion is for
/// technically-orphaned uploads — storage files that have no matching DB record
/// (interrupted mid-upload before the INSERT completed). These carry zero
/// forensic value because no business event was ever committed.
library;

import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Storage tier of a forensic evidence file.
enum EvidenceStorageStatus {
  /// File resides in primary (fast) Supabase Storage bucket.
  hot,

  /// File has been moved to cold-tier archive bucket after 90 days inactivity.
  cold,
}

/// Immutable snapshot of an evidence file's lifecycle state.
///
/// [contentHash] is the SHA-256 hex digest sealed at ingest (INV-9).
/// It MUST NOT change after creation — any mutation is a ledger violation.
class EvidenceLifecycleRecord {
  final String id;
  final String organizationId;
  final String contentHash;
  final String storagePath;
  final EvidenceStorageStatus status;
  final bool legalHold;
  final DateTime lastAccessedAtUtc;
  final DateTime uploadedAtUtc;

  const EvidenceLifecycleRecord({
    required this.id,
    required this.organizationId,
    required this.contentHash,
    required this.storagePath,
    required this.status,
    required this.legalHold,
    required this.lastAccessedAtUtc,
    required this.uploadedAtUtc,
  });
}

/// Result of a single archiving batch run.
class LifecycleTransitionResult {
  final int archived;
  final int skippedLegalHold;
  final int failed;

  const LifecycleTransitionResult({
    required this.archived,
    required this.skippedLegalHold,
    required this.failed,
  });
}

/// Result of an orphaned-upload purge run.
///
/// [purged] is the count of storage paths successfully deleted.
/// [failed] is the count that could not be deleted (network error, etc.).
/// Failures are counted — never silently swallowed — so the caller can alert.
class OrphanPurgeResult {
  final int purged;
  final int failed;

  const OrphanPurgeResult({required this.purged, required this.failed});
}

/// Application-layer port: database operations for evidence lifecycle.
///
/// Infrastructure implementations connect to Supabase (production) or
/// in-memory fixtures (tests). Application MUST NOT import Supabase
/// SDK directly — this interface is the C4 boundary (INV-13).
abstract class EvidenceLifecycleRepository {
  /// Returns records eligible for archiving: Hot status, no legalHold,
  /// and [lastAccessedAtUtc] before [inactiveBeforeUtc].
  Future<List<EvidenceLifecycleRecord>> findEligibleForArchiving({
    required String organizationId,
    required DateTime inactiveBeforeUtc,
    int limit = 100,
  });

  /// Transitions [evidenceId] to [EvidenceStorageStatus.cold] in the ledger.
  Future<void> transitionToCold({
    required String evidenceId,
    required String organizationId,
    required DateTime archivedAtUtc,
  });

  /// Reverts [evidenceId] to [EvidenceStorageStatus.hot].
  ///
  /// Called on archiving failure to guarantee idempotency: the next batch
  /// run will rediscover this record and retry.
  Future<void> rollbackToHot({
    required String evidenceId,
    required String organizationId,
  });

  /// Returns the lifecycle record for [evidenceId] regardless of storage status.
  ///
  /// **Availability guarantee (INV-3):** metadata (including [contentHash])
  /// MUST be queryable for audit even when the physical file is in cold tier.
  Future<EvidenceLifecycleRecord?> findById({
    required String evidenceId,
    required String organizationId,
  });
}

/// Application-layer port: cold storage operations.
abstract class EvidenceColdStoragePort {
  /// Moves the evidence file to cold-tier storage.
  Future<void> moveToColdStorage({required EvidenceLifecycleRecord record});

  /// Computes SHA-256 of the archived file in cold storage.
  ///
  /// Used to verify byte-identical transfer (INV-9, INV-15).
  Future<String> computeArchivedChecksum({
    required EvidenceLifecycleRecord record,
  });
}

/// Application-layer port: orphaned upload detection and targeted purge.
///
/// An "orphan" is a file that exists in storage but has no matching DB record.
/// This can only happen when a client upload completes but the subsequent
/// DB INSERT was interrupted (crash, network loss, transaction rollback).
///
/// **Scope of physical deletion (INV-3):** ONLY paths returned by
/// [findOrphanedPaths] may be physically deleted. Any file with a DB record —
/// even if the justification was rejected or has exceeded retention age —
/// MUST be handled by Cold Storage archiving, not deletion.
///
/// Infrastructure implementations MUST enforce org-scoped bucket access.
/// Cross-tenant path enumeration is prohibited (INV-22).
abstract class EvidenceOrphanDetectorPort {
  /// Returns storage paths in [organizationId]'s bucket scope that have no
  /// matching DB record (i.e., uploads interrupted before the DB INSERT committed).
  ///
  /// Implementations MUST scope the listing to [organizationId] to prevent
  /// cross-tenant path enumeration (INV-22).
  Future<List<String>> findOrphanedPaths({required String organizationId});

  /// Physically deletes the given [paths] from storage.
  ///
  /// [paths] MUST have been returned by [findOrphanedPaths] in the same run.
  /// Implementations MUST NOT accept arbitrary caller-provided paths without
  /// re-verifying orphan status to prevent race-condition deletion of
  /// a file whose DB record was inserted between detection and purge.
  Future<void> deletePaths({
    required List<String> paths,
    required String organizationId,
  });
}

/// Manages evidence transitions from Hot to Cold storage, enforces
/// 5-year legal retention, and purges technically-orphaned uploads (Red Team ID 6).
///
/// **Lifecycle rules:**
/// - 90 days without access → eligible for Cold archiving.
/// - [legalHold] = true → permanently blocked from any transition or deletion,
///   regardless of age (even past the 5-year mark).
/// - After archiving: SHA-256 of archived copy must match ledger hash (INV-9).
///   Mismatch → rollback to Hot + failed count incremented.
///
/// **Idempotency:** If archiving fails (network error, checksum mismatch),
/// the record is rolled back to Hot. The next scheduled run rediscovers
/// and retries it — no phantom state, no silent data loss (INV-10).
class EvidenceLifecycleManager {
  static const int hotStorageRetentionDays = 90;
  static const int legalRetentionYears = 5;

  /// INV-3: Business evidence is NEVER physically deleted.
  /// Only technically-orphaned uploads (no DB record) may be purged.
  static const String inv3PolicyStatement =
      'Evidence with a DB record follows Cold Storage archiving. '
      'Physical deletion is reserved for orphaned uploads only.';

  final EvidenceLifecycleRepository _repository;
  final EvidenceColdStoragePort _coldStorage;
  final IDateTimeProvider _clock;
  final bool _isServiceRole;

  const EvidenceLifecycleManager({
    required EvidenceLifecycleRepository repository,
    required EvidenceColdStoragePort coldStorage,
    required IDateTimeProvider clock,
    required bool isServiceRole,
  }) : _repository = repository,
       _coldStorage = coldStorage,
       _clock = clock,
       _isServiceRole = isServiceRole;

  /// Processes a batch of evidence eligible for Hot → Cold archiving.
  ///
  /// **INV-24:** throws [IntegrityException] if called without Service Role.
  /// **INV-3:** contentHash in ledger is never mutated.
  /// **Idempotency:** failures roll back to Hot; retry on next invocation.
  Future<LifecycleTransitionResult> processArchivingBatch({
    required String organizationId,
  }) async {
    if (!_isServiceRole) {
      throw const IntegrityException(
        'Archiving batch requires Service Role. Standard users cannot trigger lifecycle transitions.',
        field: 'isServiceRole',
      );
    }

    final cutoff = _clock.nowUtc().subtract(
      const Duration(days: hotStorageRetentionDays),
    );

    final eligible = await _repository.findEligibleForArchiving(
      organizationId: organizationId,
      inactiveBeforeUtc: cutoff,
    );

    var archived = 0;
    var skippedLegalHold = 0;
    var failed = 0;

    for (final record in eligible) {
      if (record.legalHold) {
        skippedLegalHold++;
        continue;
      }

      try {
        await _coldStorage.moveToColdStorage(record: record);

        final archivedHash = await _coldStorage.computeArchivedChecksum(
          record: record,
        );

        if (archivedHash != record.contentHash) {
          await _repository.rollbackToHot(
            evidenceId: record.id,
            organizationId: organizationId,
          );
          failed++;
          continue;
        }

        await _repository.transitionToCold(
          evidenceId: record.id,
          organizationId: organizationId,
          archivedAtUtc: _clock.nowUtc(),
        );

        archived++;
      } catch (_) {
        await _repository.rollbackToHot(
          evidenceId: record.id,
          organizationId: organizationId,
        );
        failed++;
      }
    }

    return LifecycleTransitionResult(
      archived: archived,
      skippedLegalHold: skippedLegalHold,
      failed: failed,
    );
  }

  /// Purges technically-orphaned uploads: files in storage with no matching
  /// DB record (interrupted mid-upload before DB INSERT committed).
  ///
  /// This is the ONLY case where physical deletion is permitted (INV-3).
  /// Business-rejected or retention-expired justifications go to Cold Storage,
  /// never to trash. See [inv3PolicyStatement].
  ///
  /// **INV-24:** throws [IntegrityException] if called without Service Role.
  /// **INV-22:** [orphanDetector] MUST scope its storage listing to
  /// [organizationId] — cross-tenant path enumeration is prohibited.
  /// **Idempotency:** if a path was already deleted in a prior run,
  /// [EvidenceOrphanDetectorPort.findOrphanedPaths] will not return it
  /// again, so re-running this method is safe and produces the same
  /// net result (zero-or-one deletion per path across all runs).
  /// **Failure counting:** each path that cannot be deleted increments
  /// [OrphanPurgeResult.failed] — no silent swallowing.
  Future<OrphanPurgeResult> purgeOrphanedUploads({
    required String organizationId,
    required EvidenceOrphanDetectorPort orphanDetector,
  }) async {
    if (!_isServiceRole) {
      throw const IntegrityException(
        'Orphan purge requires Service Role. Standard users cannot trigger physical deletion.',
        field: 'isServiceRole',
      );
    }

    final orphanedPaths = await orphanDetector.findOrphanedPaths(
      organizationId: organizationId,
    );

    var purged = 0;
    var failed = 0;

    for (final path in orphanedPaths) {
      try {
        await orphanDetector.deletePaths(
          paths: [path],
          organizationId: organizationId,
        );
        purged++;
      } catch (_) {
        // Increment failed — never silently swallow a deletion error (INV-10).
        // The next scheduled run will re-detect and retry.
        failed++;
      }
    }

    return OrphanPurgeResult(purged: purged, failed: failed);
  }
}
