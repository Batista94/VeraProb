import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';

void main() {
  group('TenantHealthView', () {
    test('can be constructed with required fields', () {
      const view = TenantHealthView(
        id: 'org-1',
        name: 'Empresa Teste',
        isActive: true,
        maxVehicles: 50,
        maxActiveContracts: 10,
        activeContractCount: 4,
        openCriticalAlertCount: 2,
      );
      expect(view.id, 'org-1');
      expect(view.isActive, isTrue);
    });

    test('legalName, planType, lastTelemetryAt are optional', () {
      const view = TenantHealthView(
        id: 'org-2',
        name: 'Empresa Sem Plano',
        isActive: false,
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
        isActive: true,
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
        isActive: true,
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
