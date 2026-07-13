import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';

void main() {
  group('TenantHealthView', () {
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

    group('fromDomain', () {
      test('propagates capabilities from snapshot', () {
        const snapshot = TenantHealthSnapshot(
          id: 'org-1',
          name: 'Test',
          isActive: true,
          status: OrgStatus.active,
          maxVehicles: 10,
          maxActiveContracts: 5,
          activeContractCount: 0,
          openCriticalAlertCount: 0,
          capabilities: {'allows_sealing': false, 'allows_loading': true},
          toolCostCents: 25000,
          dwellTimeSeconds: 600,
          billingDay: 10,
          contactEmail: 'ops@test.com',
          externalId: 'ERP-42',
        );

        final view = TenantHealthView.fromDomain(snapshot);

        expect(view.capabilities.allowsSealing, isFalse);
        expect(view.capabilities.allowsLoading, isTrue);
        expect(view.toolCostCents, equals(25000));
        expect(view.dwellTimeSeconds, equals(600));
        expect(view.billingDay, equals(10));
        expect(view.contactEmail, equals('ops@test.com'));
        expect(view.externalId, equals('ERP-42'));
      });

      test('null capabilities defaults to all-true (legacy orgs)', () {
        const snapshot = TenantHealthSnapshot(
          id: 'org-legacy',
          name: 'Legacy',
          isActive: true,
          maxVehicles: 10,
          maxActiveContracts: 5,
          activeContractCount: 0,
          openCriticalAlertCount: 0,
          capabilities: null,
        );

        final view = TenantHealthView.fromDomain(snapshot);

        expect(view.capabilities, equals(OrgCapabilitiesViewModel.defaults));
        expect(view.toolCostCents, isNull);
        expect(view.dwellTimeSeconds, equals(300));
        expect(view.billingDay, isNull);
        expect(view.contactEmail, isNull);
        expect(view.externalId, isNull);
      });
    });
  });
}
