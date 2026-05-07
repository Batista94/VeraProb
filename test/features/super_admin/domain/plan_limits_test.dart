import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/features/super_admin/domain/plan_limits.dart';
import 'package:veraprob/features/super_admin/domain/plan_type.dart';

void main() {
  group('PlanLimits', () {
    test('starter plan has lower vehicle limit than professional', () {
      final starterMax = PlanLimits.maxVehicles(PlanType.starter)!;
      final proMax = PlanLimits.maxVehicles(PlanType.professional)!;
      expect(starterMax, lessThan(proMax));
    });

    test('starter plan has lower contract limit than professional', () {
      final starterMax = PlanLimits.maxContracts(PlanType.starter)!;
      final proMax = PlanLimits.maxContracts(PlanType.professional)!;
      expect(starterMax, lessThan(proMax));
    });

    test('enterprise plan has unlimited vehicles (null)', () {
      expect(PlanLimits.maxVehicles(PlanType.enterprise), isNull);
    });

    test('enterprise plan has unlimited contracts (null)', () {
      expect(PlanLimits.maxContracts(PlanType.enterprise), isNull);
    });

    test('starter maxVehicles is 10', () {
      expect(PlanLimits.maxVehicles(PlanType.starter), 10);
    });

    test('starter maxContracts is 5', () {
      expect(PlanLimits.maxContracts(PlanType.starter), 5);
    });

    test('professional maxVehicles is 100', () {
      expect(PlanLimits.maxVehicles(PlanType.professional), 100);
    });

    test('professional maxContracts is 50', () {
      expect(PlanLimits.maxContracts(PlanType.professional), 50);
    });

    test('all plan types are covered in defaults map', () {
      for (final plan in PlanType.values) {
        expect(PlanLimits.defaults, contains(plan));
      }
    });
  });
}
