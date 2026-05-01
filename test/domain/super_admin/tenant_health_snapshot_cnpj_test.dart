import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';

void main() {
  /// Minimal JSON with all required fields for TenantHealthSnapshot.fromJson.
  Map<String, dynamic> baseJson({
    String? cnpj,
    String? createdAt,
    bool includeCnpj = true,
    bool includeCreatedAt = true,
  }) {
    final json = <String, dynamic>{
      'id': 'org-test',
      'name': 'Test Org',
      'is_active': true,
      'max_vehicles': 10,
      'max_active_contracts': 5,
      'active_contract_count': 2,
      'open_critical_alert_count': 0,
    };
    if (includeCnpj) json['cnpj'] = cnpj;
    if (includeCreatedAt) json['created_at'] = createdAt;
    return json;
  }

  group('TenantHealthSnapshot — cnpj field', () {
    test('fromJson maps valid cnpj string', () {
      final snapshot = TenantHealthSnapshot.fromJson(
        baseJson(cnpj: '12.345.678/0001-90'),
      );
      expect(snapshot.cnpj, equals('12.345.678/0001-90'));
    });

    test('fromJson maps cnpj null', () {
      final snapshot = TenantHealthSnapshot.fromJson(baseJson(cnpj: null));
      expect(snapshot.cnpj, isNull);
    });

    test('fromJson handles cnpj key absent from JSON', () {
      final snapshot = TenantHealthSnapshot.fromJson(
        baseJson(includeCnpj: false),
      );
      expect(snapshot.cnpj, isNull);
    });
  });

  group('TenantHealthSnapshot — createdAt field', () {
    test('fromJson maps valid created_at (ISO 8601 string)', () {
      final snapshot = TenantHealthSnapshot.fromJson(
        baseJson(createdAt: '2025-03-15T14:30:00.000Z'),
      );
      expect(snapshot.createdAt, isNotNull);
      expect(snapshot.createdAt, equals(DateTime.utc(2025, 3, 15, 14, 30)));
    });

    test('fromJson maps created_at null', () {
      final snapshot = TenantHealthSnapshot.fromJson(baseJson(createdAt: null));
      expect(snapshot.createdAt, isNull);
    });

    test('fromJson handles created_at key absent from JSON', () {
      final snapshot = TenantHealthSnapshot.fromJson(
        baseJson(includeCreatedAt: false),
      );
      expect(snapshot.createdAt, isNull);
    });
  });

  group('TenantHealthSnapshot — Equatable includes cnpj and createdAt', () {
    test('props includes cnpj and createdAt', () {
      final dt = DateTime.utc(2025, 1, 1);
      const cnpj = '00.000.000/0001-00';

      final a = TenantHealthSnapshot(
        id: 'org-1',
        name: 'Org',
        isActive: true,
        maxVehicles: 10,
        maxActiveContracts: 5,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
        cnpj: cnpj,
        createdAt: dt,
      );
      final b = TenantHealthSnapshot(
        id: 'org-1',
        name: 'Org',
        isActive: true,
        maxVehicles: 10,
        maxActiveContracts: 5,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
        cnpj: cnpj,
        createdAt: dt,
      );
      final c = TenantHealthSnapshot(
        id: 'org-1',
        name: 'Org',
        isActive: true,
        maxVehicles: 10,
        maxActiveContracts: 5,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
        cnpj: '99.999.999/0001-99', // different cnpj
        createdAt: dt,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
