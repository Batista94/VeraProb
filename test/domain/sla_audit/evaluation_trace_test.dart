import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace.dart';
import 'package:veraprob/domain/sla_audit/evidence_payload.dart';

void main() {
  final evaluatedAt = DateTime.utc(2026, 4, 1, 10, 0, 0);

  EvaluationDecision makeDecision({
    String outcome = 'GUILTY',
    int? financialImpactCents = 5000,
    EvidencePayload? evidence,
  }) {
    return EvaluationDecision(
      ruleId: 'rule-1',
      ruleType: 'NO_SHOW_PENALTY',
      ruleVersion: 2,
      rulePriority: 1,
      outcome: outcome,
      financialImpactCents: financialImpactCents,
      evidence: evidence ?? const PenaltyAssessedEvidence(penaltyAmountCents: 5000),
    );
  }

  EvaluationTrace makeTrace({List<EvaluationDecision>? decisions}) {
    return EvaluationTrace(
      id: 'trace-1',
      organizationId: 'org-1',
      entityId: 'set-1',
      triggeringEventId: 'event-1',
      evaluatedAtUtc: evaluatedAt,
      engineVersion: 'v2.5.0',
      decisions: decisions ?? [makeDecision()],
    );
  }

  group('EvaluationDecision.toJson / fromJson', () {
    test('roundtrip with PenaltyAssessedEvidence', () {
      final decision = makeDecision();
      final json = decision.toJson();
      final restored = EvaluationDecision.fromJson(json);

      expect(restored.ruleId, decision.ruleId);
      expect(restored.ruleType, decision.ruleType);
      expect(restored.ruleVersion, decision.ruleVersion);
      expect(restored.rulePriority, decision.rulePriority);
      expect(restored.outcome, decision.outcome);
      expect(restored.financialImpactCents, decision.financialImpactCents);
    });

    test('toJson omits financial_impact_cents when null', () {
      final decision = makeDecision(financialImpactCents: null);
      final json = decision.toJson();
      expect(json.containsKey('financial_impact_cents'), isFalse);
    });

    test('toJson includes financial_impact_cents when present', () {
      final decision = makeDecision(financialImpactCents: 1500);
      final json = decision.toJson();
      expect(json['financial_impact_cents'], 1500);
    });

    test('roundtrip with DwellRequirementEvidence', () {
      const evidence = DwellRequirementEvidence(
        requiredDwellSeconds: 120,
        parameterSource: 'rule_config',
      );
      final decision = makeDecision(evidence: evidence);
      final restored = EvaluationDecision.fromJson(decision.toJson());
      final restoredEvidence = restored.evidence as DwellRequirementEvidence;

      expect(restoredEvidence.requiredDwellSeconds, 120);
      expect(restoredEvidence.parameterSource, 'rule_config');
    });

    test('roundtrip with SpeedViolationEvidence', () {
      const evidence = SpeedViolationEvidence(
        actualSpeedKmh: 95.5,
        limitSpeedKmh: 80.0,
      );
      final decision = makeDecision(evidence: evidence);
      final restored = EvaluationDecision.fromJson(decision.toJson());
      final restoredEvidence = restored.evidence as SpeedViolationEvidence;

      expect(restoredEvidence.actualSpeedKmh, 95.5);
      expect(restoredEvidence.limitSpeedKmh, 80.0);
    });

    test('roundtrip with GeofenceBindingEvidence', () {
      const evidence = GeofenceBindingEvidence(
        distanceMeters: 12.5,
        allowedRadiusMeters: 50,
        actualDwellSeconds: 90,
        requiredDwellSeconds: 60,
      );
      final decision = makeDecision(evidence: evidence);
      final restored = EvaluationDecision.fromJson(decision.toJson());
      final restoredEvidence = restored.evidence as GeofenceBindingEvidence;

      expect(restoredEvidence.distanceMeters, 12.5);
      expect(restoredEvidence.allowedRadiusMeters, 50);
    });

    test('roundtrip with ExpirationSweepEvidence', () {
      const evidence = ExpirationSweepEvidence(
        scheduledWindowEndUtc: '2026-04-01T08:00:00Z',
        evaluatedAtUtc: '2026-04-01T08:05:00Z',
        expiredBySeconds: 300,
      );
      final decision = makeDecision(evidence: evidence);
      final restored = EvaluationDecision.fromJson(decision.toJson());
      final restoredEvidence = restored.evidence as ExpirationSweepEvidence;

      expect(restoredEvidence.expiredBySeconds, 300);
    });

    test('fromJson falls back to GenericEvidencePayload for unknown _type', () {
      final json = {
        'rule_id': 'r-1',
        'rule_type': 'CUSTOM',
        'rule_version': 1,
        'rule_priority': 1,
        'outcome': 'INNOCENT',
        'evidence': {'_type': 'unknown_type', 'custom_key': 'value'},
      };
      final decision = EvaluationDecision.fromJson(json);
      expect(decision.evidence, isA<GenericEvidencePayload>());
    });

    test('fromJson handles evidence without _type key (legacy records)', () {
      final json = {
        'rule_id': 'r-1',
        'rule_type': 'OLD',
        'rule_version': 1,
        'rule_priority': 1,
        'outcome': 'INNOCENT',
        'evidence': {'some_legacy_key': 42},
      };
      final decision = EvaluationDecision.fromJson(json);
      expect(decision.evidence, isA<GenericEvidencePayload>());
    });
  });

  group('EvaluationTrace', () {
    test('stores all fields correctly', () {
      final trace = makeTrace();
      expect(trace.id, 'trace-1');
      expect(trace.organizationId, 'org-1');
      expect(trace.entityId, 'set-1');
      expect(trace.triggeringEventId, 'event-1');
      expect(trace.evaluatedAtUtc, evaluatedAt);
      expect(trace.engineVersion, 'v2.5.0');
      expect(trace.decisions, hasLength(1));
    });

    test('supports multiple decisions', () {
      final d1 = makeDecision(outcome: 'GUILTY');
      final d2 = makeDecision(
        outcome: 'INNOCENT',
        financialImpactCents: null,
        evidence: const DwellRequirementEvidence(
          requiredDwellSeconds: 60,
          parameterSource: 'default',
        ),
      );
      final trace = makeTrace(decisions: [d1, d2]);
      expect(trace.decisions, hasLength(2));
      expect(trace.decisions.first.outcome, 'GUILTY');
      expect(trace.decisions.last.outcome, 'INNOCENT');
    });

    test('equality based on all props', () {
      final t1 = makeTrace();
      final t2 = makeTrace();
      expect(t1, equals(t2));
    });

    test('traces with different ids are not equal', () {
      final t1 = EvaluationTrace(
        id: 'trace-A',
        organizationId: 'org-1',
        entityId: 'set-1',
        triggeringEventId: 'event-1',
        evaluatedAtUtc: evaluatedAt,
        engineVersion: 'v2.5.0',
        decisions: [],
      );
      final t2 = EvaluationTrace(
        id: 'trace-B',
        organizationId: 'org-1',
        entityId: 'set-1',
        triggeringEventId: 'event-1',
        evaluatedAtUtc: evaluatedAt,
        engineVersion: 'v2.5.0',
        decisions: [],
      );
      expect(t1, isNot(equals(t2)));
    });
  });
}
