import 'package:flutter_test/flutter_test.dart';
import 'package:pactaflow/domain/sla_audit/canonical_fact.dart';
import 'package:pactaflow/domain/sla_audit/domain_exception.dart';
import 'package:pactaflow/domain/sla_audit/ingestion_integrity_flag.dart';

void main() {
  // ── Helpers ────────────────────────────────────────────────────────────────
  final _receivedAt = DateTime.utc(2026, 3, 17, 14, 0, 0);
  final _gpsTs = DateTime.utc(2026, 3, 17, 13, 55, 0); // 5 min before receipt

  CanonicalFact makeValid({
    String organizationId = 'org-1',
    String rawPayloadId = 'raw-1',
    String? assetId = 'asset-1',
    String deviceId = 'SASCAR-DEV-001',
    String sourceAdapter = 'SASCAR_V1',
    DateTime? receivedAtUtc,
    DateTime? gpsTimestamp,
    double lat = -23.5505,
    double lng = -46.6333,
    int? speedCms = 2778, // ~100 km/h
    int? headingDegrees = 90,
    double? accuracyMeters = 15.0,
    IngestionIntegrityFlag integrityFlag = IngestionIntegrityFlag.ok,
  }) =>
      CanonicalFact.create(
        organizationId: organizationId,
        rawPayloadId: rawPayloadId,
        assetId: assetId,
        deviceId: deviceId,
        sourceAdapter: sourceAdapter,
        receivedAtUtc: receivedAtUtc ?? _receivedAt,
        gpsTimestamp: gpsTimestamp ?? _gpsTs,
        lat: lat,
        lng: lng,
        speedCms: speedCms,
        headingDegrees: headingDegrees,
        accuracyMeters: accuracyMeters,
        integrityFlag: integrityFlag,
      );

  // ── Creation ───────────────────────────────────────────────────────────────
  group('CanonicalFact.create()', () {
    test('creates valid fact with all fields', () {
      final fact = makeValid();

      expect(fact.id, isNotEmpty);
      expect(fact.organizationId, 'org-1');
      expect(fact.rawPayloadId, 'raw-1');
      expect(fact.deviceId, 'SASCAR-DEV-001');
      expect(fact.sourceAdapter, 'SASCAR_V1');
      expect(fact.lat, -23.5505);
      expect(fact.lng, -46.6333);
      expect(fact.speedCms, 2778);
      expect(fact.integrityFlag, IngestionIntegrityFlag.ok);
    });

    test('two create() calls produce different ids (no singleton)', () {
      final a = makeValid();
      final b = makeValid();
      expect(a.id, isNot(b.id));
    });

    test('assetId may be null (device not yet mapped)', () {
      final fact = makeValid(assetId: null);
      expect(fact.assetId, isNull);
    });

    test('optional fields may be null', () {
      final fact = makeValid(
        speedCms: null,
        headingDegrees: null,
        accuracyMeters: null,
      );
      expect(fact.speedCms, isNull);
      expect(fact.headingDegrees, isNull);
      expect(fact.accuracyMeters, isNull);
    });
  });

  // ── INV-3: UTC enforcement ─────────────────────────────────────────────────
  group('UTC invariant (INV-3)', () {
    test('throws if receivedAtUtc is not UTC', () {
      expect(
        () => makeValid(
          receivedAtUtc: DateTime(2026, 3, 17, 14, 0, 0), // local time
        ),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('receivedAtUtc must be UTC'),
          ),
        ),
      );
    });

    test('throws if gpsTimestamp is not UTC', () {
      expect(
        () => makeValid(
          gpsTimestamp: DateTime(2026, 3, 17, 13, 55, 0), // local time
        ),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            contains('gpsTimestamp must be UTC'),
          ),
        ),
      );
    });
  });

  // ── Field validation ───────────────────────────────────────────────────────
  group('Field validation', () {
    test('throws on empty organizationId', () {
      expect(
        () => makeValid(organizationId: ''),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on empty rawPayloadId', () {
      expect(
        () => makeValid(rawPayloadId: ''),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on empty deviceId', () {
      expect(
        () => makeValid(deviceId: ''),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on empty sourceAdapter', () {
      expect(
        () => makeValid(sourceAdapter: ''),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on lat < -90', () {
      expect(() => makeValid(lat: -91.0), throwsA(isA<DomainException>()));
    });

    test('throws on lat > 90', () {
      expect(() => makeValid(lat: 91.0), throwsA(isA<DomainException>()));
    });

    test('throws on lng < -180', () {
      expect(() => makeValid(lng: -181.0), throwsA(isA<DomainException>()));
    });

    test('throws on lng > 180', () {
      expect(() => makeValid(lng: 181.0), throwsA(isA<DomainException>()));
    });

    test('throws on negative speedCms', () {
      expect(
        () => makeValid(speedCms: -1),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on headingDegrees < 0', () {
      expect(
        () => makeValid(headingDegrees: -1),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on headingDegrees > 359', () {
      expect(
        () => makeValid(headingDegrees: 360),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on negative accuracyMeters', () {
      expect(
        () => makeValid(accuracyMeters: -0.1),
        throwsA(isA<DomainException>()),
      );
    });
  });

  // ── IoT Chaos Scenarios ────────────────────────────────────────────────────
  group('IoT Chaos Scenarios', () {
    // C1: Late Arrival — fact stored, flag set, eligible for evaluation
    test('C1: lateArrival flag — fact is eligible for evaluation', () {
      final fact = makeValid(integrityFlag: IngestionIntegrityFlag.lateArrival);
      expect(fact.integrityFlag, IngestionIntegrityFlag.lateArrival);
      expect(fact.isEligibleForEvaluation, isTrue);
    });

    // C2: Future Timestamp — stored but excluded from evaluation
    test('C2: futureTimestamp flag — fact is NOT eligible for evaluation', () {
      final now = DateTime.utc(2026, 3, 17, 14, 0, 0);
      final future = DateTime.utc(2026, 3, 17, 14, 10, 0); // 10 min in future
      final fact = makeValid(
        receivedAtUtc: now,
        gpsTimestamp: future,
        integrityFlag: IngestionIntegrityFlag.futureTimestamp,
      );
      expect(fact.isEligibleForEvaluation, isFalse);
      expect(fact.telemetryLatency.isNegative, isTrue);
    });

    // C5: Kinematic Anomaly — GPS jitter, excluded from evaluation
    test('C5: kinematicAnomaly flag — fact is NOT eligible for evaluation', () {
      final fact = makeValid(
        speedCms: 55556, // ~2000 km/h — physically impossible
        integrityFlag: IngestionIntegrityFlag.kinematicAnomaly,
      );
      expect(fact.isEligibleForEvaluation, isFalse);
    });

    // C6: Null Island — excluded from evaluation
    test('C6: nullIsland flag — (0.0, 0.0) stored, excluded from evaluation', () {
      // Note: (0.0, 0.0) passes lat/lng range checks — flag is set by the Adapter.
      final fact = makeValid(
        lat: 0.0,
        lng: 0.0,
        integrityFlag: IngestionIntegrityFlag.nullIsland,
      );
      expect(fact.lat, 0.0);
      expect(fact.lng, 0.0);
      expect(fact.isEligibleForEvaluation, isFalse);
    });

    // Low accuracy — excluded from evaluation
    test('lowAccuracy flag — fact is NOT eligible for evaluation', () {
      final fact = makeValid(
        accuracyMeters: 250.0,
        integrityFlag: IngestionIntegrityFlag.lowAccuracy,
      );
      expect(fact.isEligibleForEvaluation, isFalse);
    });
  });

  // ── Derived properties ─────────────────────────────────────────────────────
  group('Derived properties', () {
    test('telemetryLatency is positive for late arrival', () {
      final received = DateTime.utc(2026, 3, 17, 18, 0, 0);
      final gps = DateTime.utc(2026, 3, 17, 14, 0, 0); // 4h before receipt
      final fact = makeValid(
        receivedAtUtc: received,
        gpsTimestamp: gps,
        integrityFlag: IngestionIntegrityFlag.lateArrival,
      );
      expect(fact.telemetryLatency, const Duration(hours: 4));
    });

    test('isEligibleForEvaluation is true only for ok and lateArrival', () {
      expect(makeValid(integrityFlag: IngestionIntegrityFlag.ok).isEligibleForEvaluation, isTrue);
      expect(makeValid(integrityFlag: IngestionIntegrityFlag.lateArrival).isEligibleForEvaluation, isTrue);
      expect(makeValid(integrityFlag: IngestionIntegrityFlag.futureTimestamp).isEligibleForEvaluation, isFalse);
      expect(makeValid(integrityFlag: IngestionIntegrityFlag.kinematicAnomaly).isEligibleForEvaluation, isFalse);
      expect(makeValid(integrityFlag: IngestionIntegrityFlag.nullIsland).isEligibleForEvaluation, isFalse);
      expect(makeValid(integrityFlag: IngestionIntegrityFlag.lowAccuracy).isEligibleForEvaluation, isFalse);
    });
  });

  // ── Reconstitution ─────────────────────────────────────────────────────────
  group('CanonicalFact.reconstitute()', () {
    test('preserves all fields including provided id', () {
      const storedId = 'stored-uuid-123';
      final fact = CanonicalFact.reconstitute(
        id: storedId,
        organizationId: 'org-1',
        rawPayloadId: 'raw-1',
        deviceId: 'DEV-001',
        sourceAdapter: 'SASCAR_V1',
        receivedAtUtc: _receivedAt,
        gpsTimestamp: _gpsTs,
        lat: -23.5505,
        lng: -46.6333,
        integrityFlag: IngestionIntegrityFlag.ok,
      );
      expect(fact.id, storedId);
      expect(fact.organizationId, 'org-1');
    });
  });

  // ── Equality ───────────────────────────────────────────────────────────────
  group('Equality', () {
    test('two facts with same id are equal', () {
      const id = 'same-id';
      final a = CanonicalFact.reconstitute(
        id: id,
        organizationId: 'org-1',
        rawPayloadId: 'raw-1',
        deviceId: 'DEV-001',
        sourceAdapter: 'SASCAR_V1',
        receivedAtUtc: _receivedAt,
        gpsTimestamp: _gpsTs,
        lat: -23.5505,
        lng: -46.6333,
        integrityFlag: IngestionIntegrityFlag.ok,
      );
      final b = CanonicalFact.reconstitute(
        id: id,
        organizationId: 'org-1',
        rawPayloadId: 'raw-1',
        deviceId: 'DEV-001',
        sourceAdapter: 'SASCAR_V1',
        receivedAtUtc: _receivedAt,
        gpsTimestamp: _gpsTs,
        lat: -23.5505,
        lng: -46.6333,
        integrityFlag: IngestionIntegrityFlag.ok,
      );
      expect(a, equals(b));
    });

    test('two create() facts with different ids are not equal', () {
      final a = makeValid();
      final b = makeValid();
      expect(a, isNot(equals(b)));
    });
  });
}
