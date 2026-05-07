import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';

void main() {
  group('OrgCapabilities.fromJson — injection hardening (INV-10)', () {
    test('non-bool allows_sealing throws IntegrityException', () {
      expect(
        () => OrgCapabilities.fromJson({'allows_sealing': 'not-a-bool'}),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('non-bool allows_loading throws IntegrityException', () {
      expect(
        () => OrgCapabilities.fromJson({'allows_loading': 1}),
        throwsA(isA<IntegrityException>()),
      );
    });

    test(
      'string NaN for max_kinematic_speed_kmh throws IntegrityException',
      () {
        expect(
          () => OrgCapabilities.fromJson({'max_kinematic_speed_kmh': 'NaN'}),
          throwsA(isA<IntegrityException>()),
        );
      },
    );

    test('unknown key __proto__ is ignored — valid result returned', () {
      final result = OrgCapabilities.fromJson({'__proto__': 'polluted'});
      expect(result.allowsSealing, isTrue);
      expect(result.allowsLoading, isTrue);
      expect(result.maxKinematicSpeedKmh, isNull);
    });

    test('all valid bools parse correctly', () {
      final result = OrgCapabilities.fromJson({
        'allows_sealing': true,
        'allows_loading': false,
        'allows_cargo_check': true,
        'allows_incident': false,
        'allows_doc': true,
        'smart_classify': false,
        'max_kinematic_speed_kmh': 120.5,
      });
      expect(result.allowsSealing, isTrue);
      expect(result.allowsLoading, isFalse);
      expect(result.maxKinematicSpeedKmh, 120.5);
    });
  });

  group('OrgCapabilitiesViewModel — preset override integrity', () {
    test(
      'Carga preset → manual uncheck Lacre → toDomain toJson shows false',
      () {
        // Simulate "Carga" preset: all capabilities enabled
        const carga = OrgCapabilitiesViewModel(
          allowsSealing: true,
          allowsLoading: true,
          allowsCargoCheck: true,
          allowsIncident: true,
          allowsDoc: true,
          smartClassify: true,
        );

        // User manually unchecks Lacre (allowsSealing)
        final modified = carga.copyWith(allowsSealing: false);

        // Domain conversion must preserve the manual override
        final json = modified.toDomain().toJson();
        expect(
          json['allows_sealing'],
          isFalse,
          reason:
              'copyWith(allowsSealing: false) must not be coerced back to true',
        );
      },
    );

    test('false does not get swallowed by null-coalescing', () {
      const initial = OrgCapabilitiesViewModel(allowsSealing: true);
      final modified = initial.copyWith(allowsSealing: false);
      expect(modified.allowsSealing, isFalse);
    });

    test('isCustomized detects allowsSealing override', () {
      const template = OrgCapabilitiesViewModel(allowsSealing: true);
      final modified = template.copyWith(allowsSealing: false);
      expect(modified.isCustomized(template), isTrue);
    });
  });
}
