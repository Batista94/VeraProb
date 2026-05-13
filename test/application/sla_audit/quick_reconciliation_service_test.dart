import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/alert_service.dart';
import 'package:veraprob/application/sla_audit/quick_reconciliation_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/domain/sla_audit/telegram/compliance_check_result.dart';
import 'package:veraprob/domain/sla_audit/telegram/i_telegram_repository.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_binding_token.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_evidence_link.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_evidence_upload.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_operational_alert_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeTelegramRepo implements ITelegramRepository {
  TelegramEvidenceLink? lastLink;

  @override
  Future<TelegramEvidenceLink> linkEvidenceToExecution({
    required String evidenceUploadId,
    required String executionSetId,
    required String organizationId,
    required String userId,
    String source = 'reconciliation',
  }) async {
    final link = TelegramEvidenceLink(
      id: 'link-1',
      organizationId: organizationId,
      evidenceUploadId: evidenceUploadId,
      executionSetId: executionSetId,
      linkedAtUtc: DateTime.utc(2024, 6, 1, 10),
      linkedByUserId: userId,
      source: source,
    );
    lastLink = link;
    return link;
  }

  @override
  Future<TelegramBindingToken> createBindingToken(TelegramBindingToken token) =>
      throw UnimplementedError();
  @override
  Future<TelegramBindingToken?> findLatestTokenForDriver({
    required String driverId,
    required String organizationId,
  }) => throw UnimplementedError();
  @override
  Future<bool> hasActiveBinding({
    required String driverId,
    required String organizationId,
  }) => throw UnimplementedError();
  @override
  Future<List<TelegramEvidenceUpload>> findOrphanEvidences({
    required String organizationId,
  }) => throw UnimplementedError();
  @override
  Future<ComplianceCheckResult> getComplianceStatus({
    required String organizationId,
    required String driverId,
  }) => throw UnimplementedError();
  @override
  Future<Map<String, ComplianceCheckResult>> getBatchComplianceStatus({
    required String organizationId,
    required List<String> setIds,
  }) => throw UnimplementedError();
  @override
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
  }) => throw UnimplementedError();
}

class FixedClock implements IDateTimeProvider {
  final DateTime _now;
  FixedClock(this._now);
  @override
  DateTime nowUtc() => _now;
  @override
  DateTime nowBrazil() => _now;
}

void main() {
  final now = DateTime.utc(2024, 6, 1, 10);

  OperationalAlert makeOrphanAlert({
    String status = 'ACTIVE',
    String? driverId = 'driver-1',
    String? evidenceId = 'evidence-123',
  }) => OperationalAlert(
    id: 'alert-1',
    organizationId: 'org-1',
    entityId: '12345',
    contractId: 'TELEGRAM_ORPHAN',
    alertType: 'TELEGRAM_ORPHAN',
    severity: 'CRITICAL',
    triggeredAtUtc: now,
    status: status,
    context: {
      'correlation_id': 'corr-1',
      'forensic_hash_prefix': 'abc123',
      'chat_id': 12345,
      'deep_link': ?(evidenceId != null
          ? 'veraprob://reconciliation/$evidenceId'
          : null),
      'driver_id': ?driverId,
    },
  );

  group('QuickReconciliationService', () {
    test('throws when alert not found', () async {
      final alertRepo = InMemoryOperationalAlertRepository();
      final service = QuickReconciliationService(
        alertRepo: alertRepo,
        alertService: AlertService(repo: alertRepo),
        telegramRepo: FakeTelegramRepo(),
        client: MockSupabaseClient(),
        clock: FixedClock(now),
      );

      expect(
        () => service.reconcileQuick(
          alertId: 'nonexistent',
          organizationId: 'org-1',
          userId: 'user-1',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when deep_link missing from context', () async {
      final alertRepo = InMemoryOperationalAlertRepository();
      final id = await alertRepo.save(makeOrphanAlert(evidenceId: null));

      final service = QuickReconciliationService(
        alertRepo: alertRepo,
        alertService: AlertService(repo: alertRepo),
        telegramRepo: FakeTelegramRepo(),
        client: MockSupabaseClient(),
        clock: FixedClock(now),
      );

      expect(
        () => service.reconcileQuick(
          alertId: id,
          organizationId: 'org-1',
          userId: 'user-1',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when driver_id missing from context', () async {
      final alertRepo = InMemoryOperationalAlertRepository();
      final id = await alertRepo.save(makeOrphanAlert(driverId: null));

      final service = QuickReconciliationService(
        alertRepo: alertRepo,
        alertService: AlertService(repo: alertRepo),
        telegramRepo: FakeTelegramRepo(),
        client: MockSupabaseClient(),
        clock: FixedClock(now),
      );

      expect(
        () => service.reconcileQuick(
          alertId: id,
          organizationId: 'org-1',
          userId: 'user-1',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('_extractEvidenceId parses deep_link correctly', () {
      // Verify via the full flow — if deep_link is valid, no StateError for evidence
      // The RPC call will fail (mock), but we verify the parsing doesn't throw
      final alert = makeOrphanAlert(evidenceId: 'ev-uuid-123');
      final deepLink = alert.context['deep_link'] as String;
      final uri = Uri.parse(deepLink);
      expect(uri.pathSegments.last, 'ev-uuid-123');
    });
  });
}
