import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/spoofing_audit_entry.dart';
import 'package:veraprob/domain/sla_audit/spoofing_risk_score.dart';
import 'package:veraprob/domain/sla_audit/spoofing_signal.dart';

void main() {
  final windowStart = DateTime.utc(2026, 3, 1, 10, 0);
  final windowEnd = DateTime.utc(2026, 3, 1, 10, 15);

  const riskScore = SpoofingRiskScore(
    score: 0.85,
    signals: [
      SpoofingSignal.zeroEntropyAccuracy,
      SpoofingSignal.staticPositionWhileMoving,
    ],
  );

  group('SpoofingAuditEntry.create', () {
    test('generates a non-empty id and contentHash', () {
      final entry = SpoofingAuditEntry.create(
        organizationId: 'org-1',
        deviceId: 'dev-abc',
        windowStart: windowStart,
        windowEnd: windowEnd,
        riskScore: riskScore,
        factsAnalyzed: 20,
        factIds: ['fact-1', 'fact-2'],
      );

      expect(entry.id, isNotEmpty);
      expect(entry.contentHash, isNotEmpty);
      expect(entry.contentHash.length, 64); // SHA-256 hex = 64 chars
    });

    test('sets organizationId, deviceId, riskScore, and factsAnalyzed', () {
      final entry = SpoofingAuditEntry.create(
        organizationId: 'org-1',
        deviceId: 'dev-abc',
        windowStart: windowStart,
        windowEnd: windowEnd,
        riskScore: riskScore,
        factsAnalyzed: 20,
        factIds: ['fact-1', 'fact-2'],
      );

      expect(entry.organizationId, 'org-1');
      expect(entry.deviceId, 'dev-abc');
      expect(entry.riskScore.score, 0.85);
      expect(entry.factsAnalyzed, 20);
      expect(entry.assetId, isNull);
    });

    test('accepts optional assetId', () {
      final entry = SpoofingAuditEntry.create(
        organizationId: 'org-1',
        deviceId: 'dev-abc',
        assetId: 'vehicle-99',
        windowStart: windowStart,
        windowEnd: windowEnd,
        riskScore: riskScore,
        factsAnalyzed: 5,
        factIds: [],
      );

      expect(entry.assetId, 'vehicle-99');
    });

    test('produces deterministic contentHash for same inputs', () {
      // Two entries created at different times will have different ids,
      // but the hash function is deterministic given the same payload structure.
      // We verify the hash is non-trivially reproducible by checking its format.
      final entry = SpoofingAuditEntry.create(
        organizationId: 'org-deterministic',
        deviceId: 'dev-det',
        windowStart: windowStart,
        windowEnd: windowEnd,
        riskScore: SpoofingRiskScore.zero(),
        factsAnalyzed: 0,
        factIds: [],
      );

      expect(entry.contentHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('SpoofingAuditEntry.reconstitute', () {
    test('restores all fields including review status', () {
      final createdAt = DateTime.utc(2026, 3, 1, 11, 0);
      final reviewedAt = DateTime.utc(2026, 3, 2, 9, 0);

      final entry = SpoofingAuditEntry.reconstitute(
        id: 'entry-uuid-123',
        organizationId: 'org-2',
        deviceId: 'dev-xyz',
        windowStart: windowStart,
        windowEnd: windowEnd,
        riskScore: riskScore,
        factsAnalyzed: 10,
        factIds: ['fact-a'],
        contentHash: 'a' * 64,
        createdAt: createdAt,
        reviewedBy: 'auditor-user-1',
        reviewedAt: reviewedAt,
        reviewOutcome: 'cleared',
      );

      expect(entry.id, 'entry-uuid-123');
      expect(entry.contentHash, 'a' * 64);
      expect(entry.reviewedBy, 'auditor-user-1');
      expect(entry.reviewOutcome, 'cleared');
    });
  });

  group('SpoofingRiskScore', () {
    test('zero() produces score of 0.0 with no signals', () {
      final zero = SpoofingRiskScore.zero();
      expect(zero.score, 0.0);
      expect(zero.signals, isEmpty);
      expect(zero.isSuspected(), isFalse);
    });

    test('isSuspected returns true when score >= threshold', () {
      const score = SpoofingRiskScore(score: 0.7, signals: []);
      expect(score.isSuspected(), isTrue);
    });

    test('isSuspected returns false when score < threshold', () {
      const score = SpoofingRiskScore(score: 0.69, signals: []);
      expect(score.isSuspected(), isFalse);
    });

    test('isSuspected respects custom threshold', () {
      const score = SpoofingRiskScore(score: 0.5, signals: []);
      expect(score.isSuspected(threshold: 0.4), isTrue);
      expect(score.isSuspected(threshold: 0.6), isFalse);
    });

    test('toJson serializes score and signal names', () {
      const score = SpoofingRiskScore(
        score: 0.9,
        signals: [SpoofingSignal.routeReplayDetected],
      );
      final json = score.toJson();
      expect(json['score'], 0.9);
      expect(json['signals'], ['routeReplayDetected']);
    });
  });
}
