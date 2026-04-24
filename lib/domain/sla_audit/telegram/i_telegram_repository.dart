import 'compliance_check_result.dart';
import 'telegram_binding_token.dart';
import 'telegram_evidence_link.dart';
import 'telegram_evidence_upload.dart';

/// Persistence contract for Telegram bot integration.
///
/// INV-1: All operations are scoped to [organizationId].
/// INV-7: No DELETE or UPDATE — only INSERT and SELECT.
abstract class ITelegramRepository {
  /// Creates and persists a new binding token.
  Future<TelegramBindingToken> createBindingToken(TelegramBindingToken token);

  /// Returns the most recently created token for [driverId] (may be expired).
  Future<TelegramBindingToken?> findLatestTokenForDriver({
    required String driverId,
    required String organizationId,
  });

  /// Returns true if [driverId] has an active Telegram chat binding.
  Future<bool> hasActiveBinding({
    required String driverId,
    required String organizationId,
  });

  /// Returns orphan evidence uploads (requires_manual_link=true, no reconciliation link).
  /// Used by the reconciliation screen for auditor triage.
  Future<List<TelegramEvidenceUpload>> findOrphanEvidences({
    required String organizationId,
  });

  /// Creates an append-only link between an evidence upload and an execution set.
  /// [source] defaults to 'reconciliation' for auditor-initiated links (INV-7).
  /// Use 'reconciliation_shortcut' for 1-click quick reconciliation.
  Future<TelegramEvidenceLink> linkEvidenceToExecution({
    required String evidenceUploadId,
    required String executionSetId,
    required String organizationId,
    required String userId,
    String source = 'reconciliation',
  });

  /// Returns the compliance status for a driver's active trip.
  /// Calls get_trip_compliance_status RPC (INV-1: org-scoped).
  Future<ComplianceCheckResult> getComplianceStatus({
    required String organizationId,
    required String driverId,
  });

  /// Returns compliance status for multiple SETs in one RPC call (INV-16: batch).
  /// Used by the dashboard to avoid N+1 calls per sanction card.
  Future<Map<String, ComplianceCheckResult>> getBatchComplianceStatus({
    required String organizationId,
    required List<String> setIds,
  });

  /// Returns forensic negligence data: how many times the driver checked /status
  /// for a given SET and whether they had pending items at query time.
  Future<
    ({
      int queryCount,
      DateTime? lastQueriedAt,
      bool hadPendingItems,
      int forcedCompletions,
    })
  >
  getDriverStatusQueryCount({
    required String organizationId,
    required String driverId,
    required String setId,
  });
}
