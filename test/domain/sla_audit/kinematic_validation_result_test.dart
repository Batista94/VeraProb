import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/kinematic_validation_result.dart';

void main() {
  group('KinematicValidationResult', () {
    test('ok factory produces non-violation', () {
      final result = KinematicValidationResult.ok(
        distanceMeters: 100.0,
        elapsedSeconds: 10,
        impliedSpeedCms: 1000,
        maxAllowedSpeedCms: 5556,
      );

      expect(result.isViolation, isFalse);
      expect(result.violationType, isNull);
      expect(result.impliedSpeedCms, 1000);
      expect(result.distanceMeters, 100.0);
      expect(result.elapsedSeconds, 10);
    });

    test('violation factory produces a violation', () {
      final result = KinematicValidationResult.violation(
        type: KinematicViolationType.impossibleSpeed,
        distanceMeters: 50000.0,
        elapsedSeconds: 30,
        impliedSpeedCms: 166667,
        maxAllowedSpeedCms: 5556,
      );

      expect(result.isViolation, isTrue);
      expect(result.violationType, KinematicViolationType.impossibleSpeed);
      expect(result.impliedSpeedCms, 166667);
    });

    test('sameTimestampPositionJump type', () {
      final result = KinematicValidationResult.violation(
        type: KinematicViolationType.sameTimestampPositionJump,
        distanceMeters: 500.0,
        elapsedSeconds: 0,
        impliedSpeedCms: null,
        maxAllowedSpeedCms: 5556,
      );

      expect(result.isViolation, isTrue);
      expect(
        result.violationType,
        KinematicViolationType.sameTimestampPositionJump,
      );
      expect(result.impliedSpeedCms, isNull);
    });

    test('Equatable: same values are equal', () {
      final a = KinematicValidationResult.ok(
        distanceMeters: 50.0,
        elapsedSeconds: 5,
        impliedSpeedCms: 1000,
        maxAllowedSpeedCms: 5556,
      );
      final b = KinematicValidationResult.ok(
        distanceMeters: 50.0,
        elapsedSeconds: 5,
        impliedSpeedCms: 1000,
        maxAllowedSpeedCms: 5556,
      );
      expect(a, equals(b));
    });
  });
}
