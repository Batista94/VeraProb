import 'package:equatable/equatable.dart';

enum SlaRuleType {
  maxToleranceDelay('MAX_TOLERANCE_DELAY'),
  maxEvidenceGap('MAX_EVIDENCE_GAP'),
  minGeofenceCoverage('MIN_GEOFENCE_COVERAGE'),
  noShowPenalty('NO_SHOW_PENALTY'),
  excessiveSpeed('EXCESSIVE_SPEED');

  final String value;
  const SlaRuleType(this.value);

  static SlaRuleType fromString(String val) {
    return values.firstWhere(
      (e) => e.value == val,
      orElse: () => throw ArgumentError('Unknown SLA Rule Type: $val'),
    );
  }
}

/// Represents a historically tracked set of rule parameters.
/// Config is strictly parameter data (JSON), not executable logic.
class ContractualRule extends Equatable {
  final String id;
  final String ruleSetId;
  final SlaRuleType ruleType;
  // architectural-note: config is intentionally Map<String, dynamic> — it maps
  // directly to a JSONB column in Postgres. Each SlaRuleType defines its own
  // required keys (validated by UpdateContractualRuleHandler._validateConfig).
  // A sealed RuleConfig hierarchy is deferred to Phase 10 (ADR pending).
  final Map<String, dynamic> config;
  final int ruleVersion;
  final int evaluationOrder;
  final DateTime activeFromUtc;
  final DateTime? activeToUtc;

  const ContractualRule({
    required this.id,
    required this.ruleSetId,
    required this.ruleType,
    required this.config,
    required this.ruleVersion,
    required this.evaluationOrder,
    required this.activeFromUtc,
    this.activeToUtc,
  });

  bool get isActive => activeToUtc == null;

  @override
  List<Object?> get props => [
    id,
    ruleSetId,
    ruleType,
    config,
    ruleVersion,
    evaluationOrder,
    activeFromUtc,
    activeToUtc,
  ];
}
