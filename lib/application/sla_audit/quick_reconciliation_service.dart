import 'package:veraprob/application/sla_audit/alert_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/domain/sla_audit/operational_alert_repository.dart';
import 'package:veraprob/domain/sla_audit/telegram/i_telegram_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One-click reconciliation: find latest SET → link evidence → resolve alert.
///
/// INV-1: All operations scoped to organizationId.
/// INV-3: telegram_evidence_links is append-only (INSERT only).
/// INV-7: No dynamic types.
class QuickReconciliationService {
  final OperationalAlertRepository _alertRepo;
  final AlertService _alertService;
  final ITelegramRepository _telegramRepo;
  final SupabaseClient _client;
  final IDateTimeProvider _clock;

  QuickReconciliationService({
    required OperationalAlertRepository alertRepo,
    required AlertService alertService,
    required ITelegramRepository telegramRepo,
    required SupabaseClient client,
    required IDateTimeProvider clock,
  }) : _alertRepo = alertRepo,
       _alertService = alertService,
       _telegramRepo = telegramRepo,
       _client = client,
       _clock = clock;

  /// Executes the hybrid Link + Resolve flow in one call.
  ///
  /// 1. Finds the alert and extracts evidence_upload_id + driver_id from context
  /// 2. Calls find_execution_for_telegram RPC to locate the latest SET
  /// 3. Inserts link in telegram_evidence_links (source='reconciliation_shortcut')
  /// 4. Acknowledges then resolves the alert
  ///
  /// Throws [StateError] if alert not found, missing context, or no SET found.
  Future<void> reconcileQuick({
    required String alertId,
    required String organizationId,
    required String userId,
  }) async {
    final alert = await _alertRepo.findById(alertId);
    if (alert == null) {
      throw StateError('Alert not found: $alertId');
    }

    final evidenceUploadId = _extractEvidenceId(alert);
    if (evidenceUploadId == null) {
      throw StateError(
        'Cannot extract evidence_upload_id from alert context. '
        'deep_link missing or malformed.',
      );
    }

    final driverId = alert.context['driver_id'] as String?;
    if (driverId == null) {
      throw StateError(
        'Alert $alertId has no driver_id in context. '
        'Cannot find matching execution.',
      );
    }

    // Use the alert trigger time as reference for the temporal heuristic
    final messageTs = alert.triggeredAtUtc.millisecondsSinceEpoch ~/ 1000;

    final setId =
        await _client.rpc(
              'find_execution_for_telegram',
              params: {
                'p_org_id': organizationId,
                'p_driver_id': driverId,
                'p_message_ts': messageTs,
              },
            )
            as String?;

    if (setId == null) {
      throw StateError(
        'No matching execution found for driver $driverId. '
        'Manual reconciliation required.',
      );
    }

    // Link evidence to execution (source='reconciliation_shortcut')
    await _telegramRepo.linkEvidenceToExecution(
      evidenceUploadId: evidenceUploadId,
      executionSetId: setId,
      organizationId: organizationId,
      userId: userId,
      source: 'reconciliation_shortcut',
    );

    // Lifecycle: ACTIVE → ACKNOWLEDGED → RESOLVED
    final now = _clock.nowUtc();
    await _alertService.acknowledge(
      alertId: alertId,
      userId: userId,
      atUtc: now,
    );
    await _alertService.resolve(alertId: alertId, atUtc: now);
  }

  /// Extracts evidence upload ID from the deep_link in alert context.
  /// Format: veraprob://reconciliation/{evidenceId}
  String? _extractEvidenceId(OperationalAlert alert) {
    final deepLink = alert.context['deep_link'] as String?;
    if (deepLink == null) return null;
    final uri = Uri.tryParse(deepLink);
    if (uri == null || uri.pathSegments.length < 2) return null;
    return uri.pathSegments.last;
  }
}
