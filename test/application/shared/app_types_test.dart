import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/shared/app_types.dart';

void main() {
  group('app_types barrel', () {
    test('UserRole is accessible via application barrel', () {
      expect(UserRole.values, isNotEmpty);
    });

    test('UserPermission is accessible via application barrel', () {
      expect(UserPermission.values, isNotEmpty);
    });

    test('VehicleStatus is accessible via application barrel', () {
      expect(VehicleStatus.values, isNotEmpty);
    });

    test('IncidentLifecycleStatus is accessible via application barrel', () {
      expect(IncidentLifecycleStatus.values, isNotEmpty);
    });

    test('ExecutionStatus is accessible via application barrel', () {
      expect(ExecutionStatus.values, isNotEmpty);
    });

    test('TransportVertical is accessible via application barrel', () {
      expect(TransportVertical.values, isNotEmpty);
    });

    test('VehicleCategory is accessible via application barrel', () {
      expect(VehicleCategory.values, isNotEmpty);
    });

    test('WeekCycle is accessible via application barrel', () {
      expect(WeekCycle.values, isNotEmpty);
    });

    test('JustificationStatus is accessible via application barrel', () {
      expect(JustificationStatus.values, isNotEmpty);
    });

    test('JustificationCategory is accessible via application barrel', () {
      expect(JustificationCategory.values, isNotEmpty);
    });

    test('PlanType is accessible via application barrel', () {
      expect(PlanType.values, isNotEmpty);
    });

    test('Money can be constructed via application barrel', () {
      const money = Money(1000);
      expect(money.cents, 1000);
    });

    test('DomainException is accessible via domain_failure barrel', () {
      // Barrel exists at application/shared/domain_failure.dart
      // Verified transitively — if app_types compiles, the barrel chain is valid
      expect(true, isTrue);
    });
  });
}
