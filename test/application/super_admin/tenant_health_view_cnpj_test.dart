import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/super_admin/application/tenant_health_view.dart';
import 'package:veraprob/features/super_admin/domain/tenant_health_snapshot.dart';

void main() {
  group('TenantHealthView — cnpj and createdAt via fromDomain', () {
    test(
      'fromDomain preserves cnpj and createdAt from TenantHealthSnapshot',
      () {
        final dt = DateTime.utc(2025, 3, 15, 14, 30);
        // Use a non-const to set createdAt (DateTime is not const-constructible)
        final snapshotWithDate = TenantHealthSnapshot(
          id: 'org-1',
          name: 'Test Org',
          isActive: true,
          maxVehicles: 10,
          maxActiveContracts: 5,
          activeContractCount: 2,
          openCriticalAlertCount: 0,
          cnpj: '12.345.678/0001-90',
          createdAt: dt,
        );

        final view = TenantHealthView.fromDomain(snapshotWithDate);

        expect(view.cnpj, equals('12.345.678/0001-90'));
        expect(view.createdAt, equals(dt));
      },
    );

    test('fromDomain preserves null cnpj and null createdAt', () {
      const snapshot = TenantHealthSnapshot(
        id: 'org-2',
        name: 'Null Fields Org',
        isActive: true,
        maxVehicles: 10,
        maxActiveContracts: 5,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
        cnpj: null,
        createdAt: null,
      );

      final view = TenantHealthView.fromDomain(snapshot);

      expect(view.cnpj, isNull);
      expect(view.createdAt, isNull);
    });
  });

  group('TenantHealthView — cnpj and createdAt via fromJson', () {
    Map<String, dynamic> baseJson({String? cnpj, String? createdAt}) {
      return {
        'id': 'org-json',
        'name': 'JSON Org',
        'is_active': true,
        'max_vehicles': 10,
        'max_active_contracts': 5,
        'active_contract_count': 2,
        'open_critical_alert_count': 0,
        'cnpj': cnpj,
        'created_at': createdAt,
      };
    }

    test('fromJson preserves cnpj and createdAt', () {
      final view = TenantHealthView.fromJson(
        baseJson(
          cnpj: '98.765.432/0001-10',
          createdAt: '2025-06-01T09:00:00.000Z',
        ),
      );

      expect(view.cnpj, equals('98.765.432/0001-10'));
      expect(view.createdAt, equals(DateTime.utc(2025, 6, 1, 9, 0)));
    });

    test('fromJson preserves null cnpj and null createdAt', () {
      final view = TenantHealthView.fromJson(
        baseJson(cnpj: null, createdAt: null),
      );

      expect(view.cnpj, isNull);
      expect(view.createdAt, isNull);
    });
  });
}
