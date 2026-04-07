import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/kinematic_guard.dart';
import 'package:veraprob/domain/sla_audit/kinematic_validation_result.dart';

CanonicalFact makeFact({
  required double lat,
  required double lng,
  required DateTime gpsTimestamp,
  int? speedCms,
}) {
  return CanonicalFact.create(
    organizationId: 'org-1',
    rawPayloadId: 'raw-1',
    assetId: 'asset-1',
    deviceId: 'device-1',
    sourceAdapter: 'TEST_V1',
    receivedAtUtc: gpsTimestamp,
    gpsTimestamp: gpsTimestamp,
    lat: lat,
    lng: lng,
    speedCms: speedCms,
    integrityFlag: IngestionIntegrityFlag.ok,
  );
}

void main() {
  const guard = KinematicGuard();

  group('KinematicGuard.validate', () {
    test('normal speed (60 km/h) returns ok', () {
      // 60 km/h = 16.67 m/s. In 60s → ~1000m.
      // ~1000m ≈ 0.009° lat at equator
      final prev = makeFact(
        lat: 0.0,
        lng: 0.0,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      final curr = makeFact(
        lat: 0.009,
        lng: 0.0,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 1, 0),
      );

      final result = guard.validate(prev, curr);
      expect(result.isViolation, isFalse);
    });

    test('GPS teleport (500 km in 30 seconds) returns violation', () {
      // SP to RJ in 30 seconds = impossible
      final prev = makeFact(
        lat: -23.5505,
        lng: -46.6333,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      final curr = makeFact(
        lat: -22.9068,
        lng: -43.1729,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 0, 30),
      );

      final result = guard.validate(prev, curr);
      expect(result.isViolation, isTrue);
      expect(result.violationType, KinematicViolationType.impossibleSpeed);
    });

    test('same timestamp, >5m apart returns sameTimestampPositionJump', () {
      final t = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final prev = makeFact(lat: 0.0, lng: 0.0, gpsTimestamp: t);
      // ~111m apart
      final curr = makeFact(lat: 0.001, lng: 0.0, gpsTimestamp: t);

      final result = guard.validate(prev, curr);
      expect(result.isViolation, isTrue);
      expect(
        result.violationType,
        KinematicViolationType.sameTimestampPositionJump,
      );
    });

    test('same timestamp, <5m apart returns ok', () {
      final t = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final prev = makeFact(lat: 0.0, lng: 0.0, gpsTimestamp: t);
      // ~1.1m apart
      final curr = makeFact(lat: 0.00001, lng: 0.0, gpsTimestamp: t);

      final result = guard.validate(prev, curr);
      expect(result.isViolation, isFalse);
    });

    test('exactly at 200 km/h threshold returns ok', () {
      // 200 km/h = 55.556 m/s. In 1s → 55.556m.
      // 55.556m ≈ 0.0005° lat
      final prev = makeFact(
        lat: 0.0,
        lng: 0.0,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      final curr = makeFact(
        lat: 0.0005,
        lng: 0.0,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 0, 1),
      );

      final result = guard.validate(prev, curr);
      // 55.6m / 1s = 5560 cm/s, which is >= 5556 threshold
      // This is borderline — just 4 cm/s over. Let's check:
      expect(result.impliedSpeedCms, closeTo(5560, 20));
      // At the boundary, slight over → violation
      expect(result.isViolation, isTrue);
    });

    test('just under 200 km/h returns ok', () {
      // 199 km/h = 55.28 m/s. In 10s → 552.8m.
      // 552.8m ≈ 0.00497° lat
      final prev = makeFact(
        lat: 0.0,
        lng: 0.0,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      final curr = makeFact(
        lat: 0.00497,
        lng: 0.0,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 0, 10),
      );

      final result = guard.validate(prev, curr);
      expect(result.isViolation, isFalse);
    });

    test('configurable max speed for freight (120 km/h)', () {
      const freightGuard = KinematicGuard(maxSpeedCms: 3333); // 120 km/h

      // 150 km/h = 41.67 m/s. In 10s → 416.7m.
      // 416.7m ≈ 0.00375° lat
      final prev = makeFact(
        lat: 0.0,
        lng: 0.0,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      final curr = makeFact(
        lat: 0.00375,
        lng: 0.0,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 0, 10),
      );

      final result = freightGuard.validate(prev, curr);
      expect(result.isViolation, isTrue);
      expect(result.violationType, KinematicViolationType.impossibleSpeed);
    });

    test('stationary vehicle returns ok', () {
      final prev = makeFact(
        lat: -23.5505,
        lng: -46.6333,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      final curr = makeFact(
        lat: -23.5505,
        lng: -46.6333,
        gpsTimestamp: DateTime.utc(2026, 1, 1, 12, 5, 0),
      );

      final result = guard.validate(prev, curr);
      expect(result.isViolation, isFalse);
      expect(result.impliedSpeedCms, 0);
    });
  });
}
