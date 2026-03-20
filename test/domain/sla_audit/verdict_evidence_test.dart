import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  final validTimestamp = DateTime.utc(2026, 4, 6, 10, 0);

  VerdictEvidence makeValid({
    String clauseRef = 'no-show-penalty-rule-1',
    String ruleId = 'rule-001',
    int ruleVersion = 1,
    double lat = -23.5505,
    double lng = -46.6333,
    DateTime? timestamp,
    double deltaValue = 15.0,
    double thresholdValue = 0.0,
    int fineCents = 150000,
    int confidenceScore = 100,
  }) {
    return VerdictEvidence.create(
      clauseRef: clauseRef,
      ruleId: ruleId,
      ruleVersion: ruleVersion,
      primaryEvidenceLat: lat,
      primaryEvidenceLng: lng,
      primaryEvidenceTimestampUtc: timestamp ?? validTimestamp,
      deltaValue: deltaValue,
      thresholdValue: thresholdValue,
      fineCents: Money(fineCents),
      confidenceScore: confidenceScore,
    );
  }

  group('VerdictEvidence.create — validations', () {
    test('rejects empty clauseRef', () {
      expect(
        () => makeValid(clauseRef: ''),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects empty ruleId', () {
      expect(() => makeValid(ruleId: ''), throwsA(isA<DomainException>()));
    });

    test('rejects lat < -90', () {
      expect(
        () => makeValid(lat: -91.0),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects lat > 90', () {
      expect(
        () => makeValid(lat: 91.0),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects lng < -180', () {
      expect(
        () => makeValid(lng: -181.0),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects lng > 180', () {
      expect(
        () => makeValid(lng: 181.0),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects non-UTC timestamp', () {
      expect(
        () => makeValid(
          timestamp: DateTime(2026, 4, 6, 10, 0), // local time, not UTC
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects fineCents <= 0', () {
      expect(
        () => makeValid(fineCents: 0),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => makeValid(fineCents: -100),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects confidenceScore < 0', () {
      expect(
        () => makeValid(confidenceScore: -1),
        throwsA(isA<DomainException>()),
      );
    });

    test('rejects confidenceScore > 100', () {
      expect(
        () => makeValid(confidenceScore: 101),
        throwsA(isA<DomainException>()),
      );
    });

    test('creates valid instance', () {
      final v = makeValid();
      expect(v.clauseRef, 'no-show-penalty-rule-1');
      expect(v.fineCents.cents, 150000);
      expect(v.evidenceHash.length, 64); // SHA-256 = 64 hex chars
    });
  });

  group('evidenceHash — determinism (INV-7)', () {
    test('same inputs produce same hash', () {
      final v1 = makeValid();
      final v2 = makeValid();
      expect(v1.evidenceHash, v2.evidenceHash);
    });

    test('different fineCents produce different hash', () {
      final v1 = makeValid(fineCents: 100000);
      final v2 = makeValid(fineCents: 200000);
      expect(v1.evidenceHash, isNot(v2.evidenceHash));
    });

    test('different ruleVersion produces different hash', () {
      final v1 = makeValid(ruleVersion: 1);
      final v2 = makeValid(ruleVersion: 2);
      expect(v1.evidenceHash, isNot(v2.evidenceHash));
    });
  });

  group('tamper detection', () {
    test('round-trip via JSON preserves evidenceHash', () {
      final original = makeValid();
      final restored = VerdictEvidence.fromJson(original.toJson());
      expect(restored.evidenceHash, original.evidenceHash);
    });

    test('round-trip preserves equality', () {
      final original = makeValid();
      final restored = VerdictEvidence.fromJson(original.toJson());
      expect(restored, original); // Equatable on evidenceHash
    });
  });

  group('JSON round-trip', () {
    test('toJson/fromJson preserves all fields', () {
      final v = makeValid();
      final json = v.toJson();
      final restored = VerdictEvidence.fromJson(json);

      expect(restored.clauseRef, v.clauseRef);
      expect(restored.ruleId, v.ruleId);
      expect(restored.ruleVersion, v.ruleVersion);
      expect(restored.primaryEvidenceLat, v.primaryEvidenceLat);
      expect(restored.primaryEvidenceLng, v.primaryEvidenceLng);
      expect(
        restored.primaryEvidenceTimestampUtc.toIso8601String(),
        v.primaryEvidenceTimestampUtc.toIso8601String(),
      );
      expect(restored.deltaValue, v.deltaValue);
      expect(restored.thresholdValue, v.thresholdValue);
      expect(restored.fineCents.cents, v.fineCents.cents);
      expect(restored.confidenceScore, v.confidenceScore);
    });
  });
}
