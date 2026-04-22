import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/alert_service.dart';
import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/domain/sla_audit/operational_alert_repository.dart';

/// Fake in-memory repository for the AlertService tests.
class FakeAlertRepository implements OperationalAlertRepository {
  final Map<String, OperationalAlert> _store = {};

  void seed(OperationalAlert alert) => _store[alert.id] = alert;

  @override
  Future<String> save(OperationalAlert alert) async {
    _store[alert.id] = alert;
    return alert.id;
  }

  @override
  Future<List<OperationalAlert>> findActive(String organizationId) async =>
      _store.values
          .where(
            (a) => a.organizationId == organizationId && a.status == 'ACTIVE',
          )
          .toList();

  @override
  Future<List<OperationalAlert>> findByEntityId(String entityId) async =>
      _store.values.where((a) => a.entityId == entityId).toList();

  @override
  Future<OperationalAlert?> findById(String alertId) async => _store[alertId];

  @override
  Future<void> update(OperationalAlert alert) async => _store[alert.id] = alert;

  @override
  Future<void> markViewed(String alertId, String userId) async {}
}

void main() {
  final now = DateTime.utc(2024, 6, 1, 10);

  OperationalAlert makeAlert({String status = 'ACTIVE'}) => OperationalAlert(
    id: 'alert-1',
    organizationId: 'org-1',
    entityId: 'set-1',
    contractId: 'contract-1',
    alertType: 'NO_SHOW',
    severity: 'CRITICAL',
    triggeredAtUtc: now,
    status: status,
  );

  group('AlertService.acknowledge', () {
    test('throws StateError when alert not found', () async {
      final repo = FakeAlertRepository();
      final service = AlertService(repo: repo);

      expect(
        () => service.acknowledge(
          alertId: 'nonexistent',
          userId: 'user-1',
          atUtc: now,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when alert is not ACTIVE', () async {
      final repo = FakeAlertRepository();
      repo.seed(makeAlert(status: 'ACKNOWLEDGED'));
      final service = AlertService(repo: repo);

      expect(
        () => service.acknowledge(
          alertId: 'alert-1',
          userId: 'user-1',
          atUtc: now,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('acknowledges ACTIVE alert successfully', () async {
      final repo = FakeAlertRepository();
      repo.seed(makeAlert());
      final service = AlertService(repo: repo);

      await service.acknowledge(
        alertId: 'alert-1',
        userId: 'user-audit-1',
        atUtc: now,
      );

      final updated = await repo.findById('alert-1');
      expect(updated!.status, 'ACKNOWLEDGED');
      expect(updated.acknowledgedByUserId, 'user-audit-1');
    });
  });

  group('AlertService.resolve', () {
    test('throws StateError when alert not found', () async {
      final repo = FakeAlertRepository();
      final service = AlertService(repo: repo);

      expect(
        () => service.resolve(alertId: 'nonexistent', atUtc: now),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when alert is not ACKNOWLEDGED', () async {
      final repo = FakeAlertRepository();
      repo.seed(makeAlert(status: 'ACTIVE'));
      final service = AlertService(repo: repo);

      expect(
        () => service.resolve(alertId: 'alert-1', atUtc: now),
        throwsA(isA<StateError>()),
      );
    });

    test('resolves ACKNOWLEDGED alert successfully', () async {
      final repo = FakeAlertRepository();
      repo.seed(makeAlert(status: 'ACKNOWLEDGED'));
      final service = AlertService(repo: repo);

      await service.resolve(alertId: 'alert-1', atUtc: now);

      final updated = await repo.findById('alert-1');
      expect(updated!.status, 'RESOLVED');
    });
  });
}
