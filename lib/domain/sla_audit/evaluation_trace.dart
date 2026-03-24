import 'package:equatable/equatable.dart';

import 'evidence_payload.dart';

/// Represents a single deterministic decision made by the Evaluation Engine.
class EvaluationDecision extends Equatable {
  final String ruleId;
  final String ruleType;
  final int ruleVersion;
  final int rulePriority;
  final String outcome;
  final int? financialImpactCents;
  final EvidencePayload evidence;

  const EvaluationDecision({
    required this.ruleId,
    required this.ruleType,
    required this.ruleVersion,
    required this.rulePriority,
    required this.outcome,
    this.financialImpactCents,
    required this.evidence,
  });

  Map<String, dynamic> toJson() {
    return {
      'rule_id': ruleId,
      'rule_type': ruleType,
      'rule_version': ruleVersion,
      'rule_priority': rulePriority,
      'outcome': outcome,
      if (financialImpactCents != null)
        'financial_impact_cents': financialImpactCents,
      'evidence': evidence.toJson(),
    };
  }

  factory EvaluationDecision.fromJson(Map<String, dynamic> json) {
    return EvaluationDecision(
      ruleId: json['rule_id'] as String,
      ruleType: json['rule_type'] as String,
      ruleVersion: json['rule_version'] as int,
      rulePriority: json['rule_priority'] as int,
      outcome: json['outcome'] as String,
      financialImpactCents: json['financial_impact_cents'] as int?,
      evidence: EvidencePayload.fromJson(
        json['evidence'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  List<Object?> get props => [
    ruleId,
    ruleType,
    ruleVersion,
    rulePriority,
    outcome,
    financialImpactCents,
    evidence,
  ];
}

/// The immutable investigative artifact representing the engine's entire reasoning
/// for a specific evaluation execution.
class EvaluationTrace extends Equatable {
  final String id;
  final String organizationId;
  final String entityId;
  final String triggeringEventId;
  final DateTime evaluatedAtUtc;
  final String engineVersion;
  final List<EvaluationDecision> decisions;

  const EvaluationTrace({
    required this.id,
    required this.organizationId,
    required this.entityId,
    required this.triggeringEventId,
    required this.evaluatedAtUtc,
    required this.engineVersion,
    required this.decisions,
  });

  @override
  List<Object?> get props => [
    id,
    organizationId,
    entityId,
    triggeringEventId,
    evaluatedAtUtc,
    engineVersion,
    decisions,
  ];
}
