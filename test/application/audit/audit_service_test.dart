import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/audit/in_memory_audit_service.dart';
import '../../mocks/fake_date_time_provider.dart';

void main() {
  group('InMemoryAuditService', () {
    late InMemoryAuditService auditService;
    late FakeDateTimeProvider fakeClock;

    setUp(() {
      fakeClock = FakeDateTimeProvider(DateTime(2026, 4, 8, 10, 0, 0));
      auditService = InMemoryAuditService(fakeClock);
    });

    test('logAction records securely and chronologically', () async {
      await auditService.logAction(
        organizationId: 'org1',
        operatorId: 'op1',
        actionType: 'RESOLVE_ALERT',
        entityId: 'e1',
        oldValue: 'PENDING',
        newValue: 'RESOLVED',
        reason: 'Test action',
      );

      final logs = await auditService.getLogsForEntity('e1');
      expect(logs.length, 1);
      final log = logs.first;

      expect(log.operatorId, 'op1');
      expect(log.actionType, 'RESOLVE_ALERT');
      expect(log.entityId, 'e1');
      expect(log.oldValue, 'PENDING');
      expect(log.newValue, 'RESOLVED');
      expect(log.reason, 'Test action');
    });

    test('getLogsForEntity filters properly and sorts latest first', () async {
      await auditService.logAction(
        organizationId: 'org1',
        operatorId: 'op1',
        actionType: 'A1',
        entityId: 'e1',
      );
      fakeClock.advance(
        const Duration(minutes: 1),
      ); // Force deterministic time gap
      await auditService.logAction(
        organizationId: 'org1',
        operatorId: 'op1',
        actionType: 'A2',
        entityId: 'e1',
      );

      await auditService.logAction(
        organizationId: 'org1',
        operatorId: 'op1',
        actionType: 'A3',
        entityId: 'e2',
      );

      final e1Logs = await auditService.getLogsForEntity('e1');
      expect(e1Logs.length, 2);
      expect(e1Logs.first.actionType, 'A2'); // Latest first
      expect(e1Logs.last.actionType, 'A1');

      final e2Logs = await auditService.getLogsForEntity('e2');
      expect(e2Logs.length, 1);
    });

    test('getRecentLogs limits by parameters', () async {
      for (int i = 0; i < 10; i++) {
        await auditService.logAction(
          organizationId: 'org1',
          operatorId: 'op1',
          actionType: 'A$i',
          entityId: 'e1',
        );
      }

      final recent = await auditService.getRecentLogs(limit: 5);
      expect(recent.length, 5);
    });
  });
}
