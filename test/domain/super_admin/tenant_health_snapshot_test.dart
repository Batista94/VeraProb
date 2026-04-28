import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';

void main() {
  group('TenantHealthSnapshot', () {
    group('fromJson', () {
      test('maps all fields correctly from complete JSON', () {
        final json = {
          'id': 'org-uuid-1',
          'name': 'Silva Logística',
          'legal_name': 'Transportes Silva Ltda.',
          'plan_type': 'professional',
          'is_active': true,
          'status': 'ACTIVE',
          'max_vehicles': 100,
          'max_active_contracts': 25,
          'active_contract_count': 5,
          'last_telemetry_at': '2026-03-19T10:30:00.000Z',
          'open_critical_alert_count': 2,
        };

        final snapshot = TenantHealthSnapshot.fromJson(json);

        expect(snapshot.id, equals('org-uuid-1'));
        expect(snapshot.name, equals('Silva Logística'));
        expect(snapshot.legalName, equals('Transportes Silva Ltda.'));
        expect(snapshot.planType, equals('professional'));
        expect(snapshot.isActive, isTrue);
        expect(snapshot.status, equals(OrgStatus.active));
        expect(snapshot.maxVehicles, equals(100));
        expect(snapshot.maxActiveContracts, equals(25));
        expect(snapshot.activeContractCount, equals(5));
        expect(snapshot.lastTelemetryAt, isNotNull);
        expect(snapshot.lastTelemetryAt!.isUtc, isTrue);
        expect(snapshot.openCriticalAlertCount, equals(2));
      });

      test('maps TRIAL status correctly', () {
        final json = {
          'id': 'org-trial',
          'name': 'Trial Org',
          'is_active': true,
          'status': 'TRIAL',
          'max_vehicles': 5,
          'max_active_contracts': 2,
          'active_contract_count': 0,
          'open_critical_alert_count': 0,
        };
        final snapshot = TenantHealthSnapshot.fromJson(json);
        expect(snapshot.status, equals(OrgStatus.trial));
        expect(snapshot.isActive, isTrue);
      });

      test('maps SUSPENDED status correctly', () {
        final json = {
          'id': 'org-suspended',
          'name': 'Suspended Org',
          'is_active': false,
          'status': 'SUSPENDED',
          'max_vehicles': 10,
          'max_active_contracts': 5,
          'active_contract_count': 0,
          'open_critical_alert_count': 0,
        };
        final snapshot = TenantHealthSnapshot.fromJson(json);
        expect(snapshot.status, equals(OrgStatus.suspended));
        expect(snapshot.isActive, isFalse);
      });

      test('status is null when absent from JSON (retro-compat)', () {
        final json = {
          'id': 'org-legacy',
          'name': 'Legacy Org',
          'is_active': true,
          'max_vehicles': 10,
          'max_active_contracts': 5,
          'active_contract_count': 0,
          'open_critical_alert_count': 0,
        };
        final snapshot = TenantHealthSnapshot.fromJson(json);
        expect(snapshot.status, isNull);
      });

      test('handles null nullable fields gracefully', () {
        final json = {
          'id': 'org-uuid-2',
          'name': 'Test Org',
          'legal_name': null,
          'plan_type': null,
          'is_active': false,
          'max_vehicles': 50,
          'max_active_contracts': 10,
          'active_contract_count': 0,
          'last_telemetry_at': null,
          'open_critical_alert_count': 0,
        };

        final snapshot = TenantHealthSnapshot.fromJson(json);

        expect(snapshot.legalName, isNull);
        expect(snapshot.planType, isNull);
        expect(snapshot.lastTelemetryAt, isNull);
        expect(snapshot.isActive, isFalse);
      });

      test('defaults numeric fields to 0 when absent', () {
        final json = {
          'id': 'org-uuid-3',
          'name': 'Minimal Org',
          'is_active': true,
        };

        final snapshot = TenantHealthSnapshot.fromJson(json);

        expect(snapshot.maxVehicles, equals(0));
        expect(snapshot.maxActiveContracts, equals(0));
        expect(snapshot.activeContractCount, equals(0));
        expect(snapshot.openCriticalAlertCount, equals(0));
      });

      test('handles numeric fields as double (PostgreSQL aggregates)', () {
        final json = {
          'id': 'org-uuid-4',
          'name': 'Double Org',
          'is_active': true,
          'max_vehicles': 50.0, // PostgREST may return as double
          'max_active_contracts': 10.0,
          'active_contract_count': 3.0,
          'open_critical_alert_count': 1.0,
        };

        final snapshot = TenantHealthSnapshot.fromJson(json);

        expect(snapshot.maxVehicles, equals(50));
        expect(snapshot.activeContractCount, equals(3));
        expect(snapshot.openCriticalAlertCount, equals(1));
      });
    });

    group('hasCriticalAlerts', () {
      test('returns true when openCriticalAlertCount > 0', () {
        const snapshot = TenantHealthSnapshot(
          id: 'x',
          name: 'x',
          isActive: true,
          maxVehicles: 10,
          maxActiveContracts: 5,
          activeContractCount: 1,
          openCriticalAlertCount: 3,
        );
        expect(snapshot.hasCriticalAlerts, isTrue);
      });

      test('returns false when openCriticalAlertCount == 0', () {
        const snapshot = TenantHealthSnapshot(
          id: 'x',
          name: 'x',
          isActive: true,
          maxVehicles: 10,
          maxActiveContracts: 5,
          activeContractCount: 1,
          openCriticalAlertCount: 0,
        );
        expect(snapshot.hasCriticalAlerts, isFalse);
      });
    });

    group('Equatable', () {
      test('two snapshots with same fields are equal', () {
        final dt = DateTime.utc(2026, 3, 19);
        final a = TenantHealthSnapshot(
          id: 'org-1',
          name: 'Org',
          isActive: true,
          maxVehicles: 50,
          maxActiveContracts: 10,
          activeContractCount: 2,
          openCriticalAlertCount: 0,
          lastTelemetryAt: dt,
        );
        final b = TenantHealthSnapshot(
          id: 'org-1',
          name: 'Org',
          isActive: true,
          maxVehicles: 50,
          maxActiveContracts: 10,
          activeContractCount: 2,
          openCriticalAlertCount: 0,
          lastTelemetryAt: dt,
        );
        expect(a, equals(b));
      });
    });
  });
}
