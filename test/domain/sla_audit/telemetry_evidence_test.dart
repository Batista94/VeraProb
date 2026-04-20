import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/telemetry_evidence.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

void main() {
  final baseTime = DateTime.utc(2026, 4, 1, 10, 0, 0);

  TelemetryEvidence createValid({
    String previousEvidenceHash = TelemetryEvidence.kGenesisHash,
    double lat = -23.5505,
    double lon = -46.6333,
    int? speedCms = 1000,
  }) {
    return TelemetryEvidence.create(
      organizationId: 'org-1',
      setId: 'set-1',
      vehicleId: 'vehicle-1',
      capturedAtUtc: baseTime,
      rawLatitude: lat,
      rawLongitude: lon,
      rawSpeedCms: speedCms,
      sourceType: 'GPS_PING',
      previousEvidenceHash: previousEvidenceHash,
    );
  }

  group('TelemetryEvidence.create — field validation', () {
    test('creates valid evidence with genesis hash', () {
      final e = createValid();
      expect(e.organizationId, 'org-1');
      expect(e.setId, 'set-1');
      expect(e.vehicleId, 'vehicle-1');
      expect(e.capturedAtUtc.isUtc, isTrue);
      expect(e.contentHash, isNotEmpty);
      expect(e.chainHash, isNotEmpty);
      expect(e.previousEvidenceHash, TelemetryEvidence.kGenesisHash);
    });

    test('generates unique IDs for each call', () {
      final e1 = createValid();
      final e2 = createValid();
      expect(e1.id, isNot(equals(e2.id)));
    });

    test('throws DomainException for empty organizationId', () {
      expect(
        () => TelemetryEvidence.create(
          organizationId: '',
          setId: 'set-1',
          vehicleId: 'v-1',
          capturedAtUtc: baseTime,
          rawLatitude: -23.5,
          rawLongitude: -46.6,
          sourceType: 'GPS_PING',
          previousEvidenceHash: TelemetryEvidence.kGenesisHash,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for empty setId', () {
      expect(
        () => TelemetryEvidence.create(
          organizationId: 'org-1',
          setId: '',
          vehicleId: 'v-1',
          capturedAtUtc: baseTime,
          rawLatitude: -23.5,
          rawLongitude: -46.6,
          sourceType: 'GPS_PING',
          previousEvidenceHash: TelemetryEvidence.kGenesisHash,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for empty vehicleId', () {
      expect(
        () => TelemetryEvidence.create(
          organizationId: 'org-1',
          setId: 'set-1',
          vehicleId: '',
          capturedAtUtc: baseTime,
          rawLatitude: -23.5,
          rawLongitude: -46.6,
          sourceType: 'GPS_PING',
          previousEvidenceHash: TelemetryEvidence.kGenesisHash,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for non-UTC timestamp (INV-9)', () {
      final localTime = DateTime(2026, 4, 1, 10, 0, 0); // local, not UTC
      expect(
        () => TelemetryEvidence.create(
          organizationId: 'org-1',
          setId: 'set-1',
          vehicleId: 'v-1',
          capturedAtUtc: localTime,
          rawLatitude: -23.5,
          rawLongitude: -46.6,
          sourceType: 'GPS_PING',
          previousEvidenceHash: TelemetryEvidence.kGenesisHash,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for latitude out of range', () {
      expect(() => createValid(lat: 91.0), throwsA(isA<DomainException>()));
      expect(() => createValid(lat: -91.0), throwsA(isA<DomainException>()));
    });

    test('throws DomainException for longitude out of range', () {
      expect(() => createValid(lon: 181.0), throwsA(isA<DomainException>()));
      expect(() => createValid(lon: -181.0), throwsA(isA<DomainException>()));
    });

    test('throws DomainException for negative speed', () {
      expect(() => createValid(speedCms: -1), throwsA(isA<DomainException>()));
    });

    test('accepts null speed (optional field)', () {
      final e = createValid(speedCms: null);
      expect(e.rawSpeedCms, isNull);
    });

    test('throws DomainException for empty sourceType', () {
      expect(
        () => TelemetryEvidence.create(
          organizationId: 'org-1',
          setId: 'set-1',
          vehicleId: 'v-1',
          capturedAtUtc: baseTime,
          rawLatitude: -23.5,
          rawLongitude: -46.6,
          sourceType: '',
          previousEvidenceHash: TelemetryEvidence.kGenesisHash,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for empty previousEvidenceHash', () {
      expect(
        () => createValid(previousEvidenceHash: ''),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('TelemetryEvidence — hash chain integrity (INV-8)', () {
    test('contentHash and chainHash are different', () {
      final e = createValid();
      expect(e.contentHash, isNot(equals(e.chainHash)));
    });

    test('verifyIntegrity() returns true for freshly created evidence', () {
      final e = createValid();
      expect(e.verifyIntegrity(), isTrue);
    });

    test(
      'chain links correctly: next.previousEvidenceHash == prev.chainHash',
      () {
        final first = createValid();
        final second = TelemetryEvidence.create(
          organizationId: 'org-1',
          setId: 'set-1',
          vehicleId: 'vehicle-1',
          capturedAtUtc: baseTime.add(const Duration(minutes: 1)),
          rawLatitude: -23.5510,
          rawLongitude: -46.6340,
          sourceType: 'GPS_PING',
          previousEvidenceHash: first.chainHash,
        );
        expect(second.previousEvidenceHash, equals(first.chainHash));
        expect(second.verifyIntegrity(), isTrue);
      },
    );

    test('reconstitute + verifyIntegrity detects tampering', () {
      final original = createValid();

      // Reconstitute with tampered latitude
      final tampered = TelemetryEvidence.reconstitute(
        id: original.id,
        organizationId: original.organizationId,
        setId: original.setId,
        vehicleId: original.vehicleId,
        capturedAtUtc: original.capturedAtUtc,
        rawLatitude: -99.0, // TAMPERED
        rawLongitude: original.rawLongitude,
        rawSpeedCms: original.rawSpeedCms,
        sourceType: original.sourceType,
        contentHash: original.contentHash,
        previousEvidenceHash: original.previousEvidenceHash,
        chainHash: original.chainHash,
      );

      expect(tampered.verifyIntegrity(), isFalse);
    });

    test('same inputs produce same contentHash (deterministic)', () {
      // Two evidence records with the SAME id produce the same content hash
      // We test this via reconstitute since create() generates a new UUID each time
      final e1 = createValid();
      final e2 = TelemetryEvidence.reconstitute(
        id: e1.id,
        organizationId: e1.organizationId,
        setId: e1.setId,
        vehicleId: e1.vehicleId,
        capturedAtUtc: e1.capturedAtUtc,
        rawLatitude: e1.rawLatitude,
        rawLongitude: e1.rawLongitude,
        rawSpeedCms: e1.rawSpeedCms,
        sourceType: e1.sourceType,
        contentHash: e1.contentHash,
        previousEvidenceHash: e1.previousEvidenceHash,
        chainHash: e1.chainHash,
      );
      expect(e2.verifyIntegrity(), isTrue);
      expect(e2.contentHash, equals(e1.contentHash));
      expect(e2.chainHash, equals(e1.chainHash));
    });

    test('kGenesisHash is the sentinel for first records in a chain', () {
      expect(TelemetryEvidence.kGenesisHash, 'GENESIS');
      final first = createValid(
        previousEvidenceHash: TelemetryEvidence.kGenesisHash,
      );
      expect(first.previousEvidenceHash, 'GENESIS');
    });
  });
}
