import 'package:glados/glados.dart';
import 'package:veraprob/features/super_admin/application/tenant_health_view.dart';
import 'package:veraprob/features/super_admin/domain/tenant_health_snapshot.dart';

/// **Validates: Requirements 1.2, 1.3, 1.4, 6.2, 6.3**
///
/// Property 1: Round-trip de propagação de dados (cnpj + createdAt)
///
/// For any valid JSON representing a row from `super_admin_tenant_health_view`
/// containing `cnpj` (String or null) and `created_at` (ISO 8601 string or
/// null), the pipeline `TenantHealthSnapshot.fromJson(json)` followed by
/// `TenantHealthView.fromDomain(snapshot)` SHALL preserve both values.
void main() {
  /// Builds a minimal valid JSON map with all required fields for
  /// [TenantHealthSnapshot.fromJson], injecting the given [cnpj] and
  /// [createdAt] values.
  Map<String, dynamic> buildJson({String? cnpj, DateTime? createdAt}) {
    return <String, dynamic>{
      'id': 'org-pbt-test',
      'name': 'PBT Org',
      'is_active': true,
      'max_vehicles': 10,
      'max_active_contracts': 5,
      'active_contract_count': 2,
      'open_critical_alert_count': 0,
      'cnpj': ?cnpj,
      if (createdAt != null) 'created_at': createdAt.toIso8601String(),
    };
  }

  /// Custom DateTime generator using safe component ranges:
  /// year 2000–2030, month 1–12, day 1–28, hour 0–23, minute 0–59.
  final safeDateTime = any.combine5(
    any.intInRange(2000, 2031), // year
    any.intInRange(1, 13), // month
    any.intInRange(1, 29), // day (safe for all months)
    any.intInRange(0, 24), // hour
    any.intInRange(0, 60), // minute
    (int year, int month, int day, int hour, int minute) =>
        DateTime(year, month, day, hour, minute),
  );

  group('Feature: tenant-config-immutable-fields, '
      'Property 1: Round-trip de propagação de dados', () {
    Glados2(any.letterOrDigits, safeDateTime).test(
      'non-null cnpj + non-null createdAt are preserved through '
      'JSON → Snapshot → ViewModel pipeline',
      (String cnpj, DateTime createdAt) {
        final json = buildJson(cnpj: cnpj, createdAt: createdAt);

        // Pipeline: JSON → TenantHealthSnapshot → TenantHealthView
        final snapshot = TenantHealthSnapshot.fromJson(json);
        final view = TenantHealthView.fromDomain(snapshot);

        // cnpj must be preserved exactly
        expect(view.cnpj, equals(cnpj));

        // createdAt must be preserved — compare via ISO 8601 round-trip
        // since DateTime.parse(dt.toIso8601String()) may normalize
        // microseconds but preserves minute-level precision.
        expect(view.createdAt, isNotNull);
        expect(view.createdAt!.year, equals(createdAt.year));
        expect(view.createdAt!.month, equals(createdAt.month));
        expect(view.createdAt!.day, equals(createdAt.day));
        expect(view.createdAt!.hour, equals(createdAt.hour));
        expect(view.createdAt!.minute, equals(createdAt.minute));
      },
    );

    test('null cnpj + null createdAt are preserved through '
        'JSON → Snapshot → ViewModel pipeline', () {
      final json = buildJson(cnpj: null, createdAt: null);

      final snapshot = TenantHealthSnapshot.fromJson(json);
      final view = TenantHealthView.fromDomain(snapshot);

      expect(view.cnpj, isNull);
      expect(view.createdAt, isNull);
    });
  });
}
