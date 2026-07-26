import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/telemetry_evidence.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_telemetry_evidence_repository.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

TelemetryEvidence makeEvidence({
  String organizationId = 'org-1',
  String setId = 'set-1',
  String vehicleId = 'v-1',
  String previousEvidenceHash = TelemetryEvidence.kGenesisHash,
}) {
  return TelemetryEvidence.create(
    organizationId: organizationId,
    setId: setId,
    vehicleId: vehicleId,
    capturedAtUtc: DateTime.utc(2026, 3, 16, 8, 0),
    rawLatitude: -23.5505,
    rawLongitude: -46.6333,
    rawSpeedCms: 1200,
    sourceType: 'GPS_PING',
    previousEvidenceHash: previousEvidenceHash,
  );
}

void main() {
  group('InMemoryTelemetryEvidenceRepository', () {
    late InMemoryTelemetryEvidenceRepository repo;

    setUp(() => repo = InMemoryTelemetryEvidenceRepository());

    test('save and findBySetId returns records ordered by insertion', () async {
      final e1 = makeEvidence();
      final e2 = makeEvidence(previousEvidenceHash: e1.chainHash);

      await repo.save(e1);
      await repo.save(e2);

      final chain = await repo.findBySetId('set-1', organizationId: 'org-1');
      expect(chain.length, 2);
      expect(chain[0].id, e1.id);
      expect(chain[1].id, e2.id);
    });

    test('findLatestBySetId returns last saved record', () async {
      final e1 = makeEvidence();
      final e2 = makeEvidence(previousEvidenceHash: e1.chainHash);

      await repo.save(e1);
      await repo.save(e2);

      final latest = await repo.findLatestBySetId(
        'set-1',
        organizationId: 'org-1',
      );
      expect(latest?.id, e2.id);
    });

    test('findLatestBySetId returns null for empty chain', () async {
      final result = await repo.findLatestBySetId(
        'nonexistent',
        organizationId: 'org-1',
      );
      expect(result, isNull);
    });

    test('duplicate contentHash throws StateError (INV-1)', () async {
      final e1 = makeEvidence();
      await repo.save(e1);
      // Reconstitute same object to force same contentHash
      final duplicate = TelemetryEvidence.reconstitute(
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
      expect(() => repo.save(duplicate), throwsA(isA<IntegrityException>()));
    });

    test('tenant isolation: findBySetId returns empty for wrong org', () async {
      final e = makeEvidence(organizationId: 'org-1');
      await repo.save(e);

      final result = await repo.findBySetId('set-1', organizationId: 'org-2');
      expect(result, isEmpty);
    });

    test('chain integrity holds across two saves', () async {
      final e1 = makeEvidence();
      final e2 = makeEvidence(previousEvidenceHash: e1.chainHash);

      await repo.save(e1);
      await repo.save(e2);

      expect(e1.verifyIntegrity(), isTrue);
      expect(e2.verifyIntegrity(), isTrue);
      // e2's previousEvidenceHash must equal e1's chainHash
      expect(e2.previousEvidenceHash, equals(e1.chainHash));
    });
  });
}
