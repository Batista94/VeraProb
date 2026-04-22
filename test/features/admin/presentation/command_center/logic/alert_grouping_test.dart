import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/features/admin/presentation/command_center/logic/alert_grouping.dart';
import 'package:veraprob/features/admin/presentation/command_center/models/driver_alert_group.dart';

void main() {
  final now = DateTime.utc(2024, 6, 1, 10);

  OperationalAlert makeAlert({
    String id = 'a-1',
    String severity = 'CRITICAL',
    String? driverId,
    String? driverName,
    DateTime? triggeredAt,
  }) => OperationalAlert(
    id: id,
    organizationId: 'org-1',
    entityId: 'set-1',
    contractId: 'c-1',
    alertType: 'NO_SHOW',
    severity: severity,
    triggeredAtUtc: triggeredAt ?? now,
    context: {'driver_id': ?driverId, 'driver_name': ?driverName},
  );

  group('groupAlertsByDriver', () {
    test('groups alerts by driver_id', () {
      final alerts = [
        makeAlert(id: 'a1', driverId: 'd-1'),
        makeAlert(id: 'a2', driverId: 'd-2'),
        makeAlert(id: 'a3', driverId: 'd-1'),
      ];

      final groups = groupAlertsByDriver(alerts);
      expect(groups.length, 2);

      final d1 = groups.firstWhere((g) => g.driverId == 'd-1');
      expect(d1.count, 2);

      final d2 = groups.firstWhere((g) => g.driverId == 'd-2');
      expect(d2.count, 1);
    });

    test('alerts without driver_id go to _unknown group', () {
      final alerts = [
        makeAlert(id: 'a1'),
        makeAlert(id: 'a2', driverId: 'd-1'),
      ];

      final groups = groupAlertsByDriver(alerts);
      final unknown = groups.firstWhere((g) => g.driverId == '_unknown');
      expect(unknown.driverName, isNull);
      expect(unknown.count, 1);
    });

    test('CRITICAL groups sort before WARNING groups', () {
      final alerts = [
        makeAlert(id: 'a1', driverId: 'd-warn', severity: 'WARNING'),
        makeAlert(id: 'a2', driverId: 'd-crit', severity: 'CRITICAL'),
      ];

      final groups = groupAlertsByDriver(alerts);
      expect(groups.first.driverId, 'd-crit');
      expect(groups.first.contractHealth, ContractHealthStatus.critical);
      expect(groups.last.contractHealth, ContractHealthStatus.green);
    });

    test('within same health, more alerts sort first', () {
      final alerts = [
        makeAlert(id: 'a1', driverId: 'd-1', severity: 'WARNING'),
        makeAlert(id: 'a2', driverId: 'd-2', severity: 'WARNING'),
        makeAlert(id: 'a3', driverId: 'd-2', severity: 'WARNING'),
      ];

      final groups = groupAlertsByDriver(alerts);
      expect(groups.first.driverId, 'd-2');
      expect(groups.first.count, 2);
    });

    test('alerts within group sorted by triggeredAtUtc desc', () {
      final older = now.subtract(const Duration(hours: 1));
      final alerts = [
        makeAlert(id: 'a1', driverId: 'd-1', triggeredAt: older),
        makeAlert(id: 'a2', driverId: 'd-1', triggeredAt: now),
      ];

      final groups = groupAlertsByDriver(alerts);
      expect(groups.first.alerts.first.id, 'a2'); // newer first
    });

    test('driverName extracted from first alert with name', () {
      final alerts = [
        makeAlert(id: 'a1', driverId: 'd-1'),
        makeAlert(id: 'a2', driverId: 'd-1', driverName: 'João'),
      ];

      final groups = groupAlertsByDriver(alerts);
      expect(groups.first.driverName, 'João');
    });

    test('empty list returns empty groups', () {
      expect(groupAlertsByDriver([]), isEmpty);
    });

    test('contractHealth derives correctly', () {
      // HIGH → yellow
      final highAlerts = [
        makeAlert(id: 'a1', driverId: 'd-1', severity: 'HIGH'),
      ];
      final highGroups = groupAlertsByDriver(highAlerts);
      expect(highGroups.first.contractHealth, ContractHealthStatus.yellow);

      // WARNING → green
      final warnAlerts = [
        makeAlert(id: 'a2', driverId: 'd-2', severity: 'WARNING'),
      ];
      final warnGroups = groupAlertsByDriver(warnAlerts);
      expect(warnGroups.first.contractHealth, ContractHealthStatus.green);
    });
  });
}
