import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/domain/admin/org_status.dart';

void main() {
  group('TenantHealthView', () {
    test('can be constructed with required fields', () {
      const view = TenantHealthView(
        id: 'org-1',
        name: 'Empresa Teste',
        maxVehicles: 50,
        maxActiveContracts: 10,
        activeContractCount: 4,
        openCriticalAlertCount: 2,
      );
      expect(view.id, 'org-1');
      expect(view.isActive, isFalse);
    });

    test('isActive derived from status == OrgStatus.active', () {
      const active = TenantHealthView(
        id: 'org-a',
        name: 'Ativa',
        status: OrgStatus.active,
        maxVehicles: 50,
        maxActiveContracts: 10,
        activeContractCount: 4,
        openCriticalAlertCount: 0,
      );
      const trial = TenantHealthView(
        id: 'org-t',
        name: 'Trial',
        status: OrgStatus.trial,
        maxVehicles: 10,
        maxActiveContracts: 5,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
      );
      expect(active.isActive, isTrue);
      expect(trial.isActive, isFalse);
    });

    test('isOperational true for ACTIVE and TRIAL', () {
      const active = TenantHealthView(
        id: 'o1',
        name: 'A',
        status: OrgStatus.active,
        maxVehicles: 0,
        maxActiveContracts: 0,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
      );
      const trial = TenantHealthView(
        id: 'o2',
        name: 'T',
        status: OrgStatus.trial,
        maxVehicles: 0,
        maxActiveContracts: 0,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
      );
      const archived = TenantHealthView(
        id: 'o3',
        name: 'Ar',
        status: OrgStatus.archived,
        maxVehicles: 0,
        maxActiveContracts: 0,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
      );
      expect(active.isOperational, isTrue);
      expect(trial.isOperational, isTrue);
      expect(archived.isOperational, isFalse);
    });

    test('isArchived true only for ARCHIVED status', () {
      const archived = TenantHealthView(
        id: 'o1',
        name: 'Ar',
        status: OrgStatus.archived,
        maxVehicles: 0,
        maxActiveContracts: 0,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
      );
      const active = TenantHealthView(
        id: 'o2',
        name: 'Act',
        status: OrgStatus.active,
        maxVehicles: 0,
        maxActiveContracts: 0,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
      );
      expect(archived.isArchived, isTrue);
      expect(active.isArchived, isFalse);
    });

    test('statusKey returns uppercase DB value', () {
      const view = TenantHealthView(
        id: 'o1',
        name: 'A',
        status: OrgStatus.archived,
        maxVehicles: 0,
        maxActiveContracts: 0,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
      );
      expect(view.statusKey, 'ARCHIVED');
    });

    test('legalName, planType, lastTelemetryAt are optional', () {
      const view = TenantHealthView(
        id: 'org-2',
        name: 'Empresa Sem Plano',
        maxVehicles: 0,
        maxActiveContracts: 0,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
      );
      expect(view.legalName, isNull);
      expect(view.planType, isNull);
      expect(view.lastTelemetryAt, isNull);
    });

    test('hasCriticalAlerts is true when openCriticalAlertCount > 0', () {
      const view = TenantHealthView(
        id: 'org-3',
        name: 'Empresa Crítica',
        maxVehicles: 100,
        maxActiveContracts: 20,
        activeContractCount: 18,
        openCriticalAlertCount: 5,
      );
      expect(view.hasCriticalAlerts, isTrue);
    });

    test('all quota fields are int', () {
      const view = TenantHealthView(
        id: 'org-4',
        name: 'Empresa',
        maxVehicles: 10,
        maxActiveContracts: 5,
        activeContractCount: 3,
        openCriticalAlertCount: 0,
      );
      expect(view.maxVehicles, isA<int>());
      expect(view.maxActiveContracts, isA<int>());
      expect(view.activeContractCount, isA<int>());
      expect(view.openCriticalAlertCount, isA<int>());
    });
  });
}
