import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/sla_audit/contractual_rule.dart';

/// Read-only projection of a single rule version for the history panel.
///
/// Derived from `contract_rule_versions` via [get_rule_version_history] RPC.
/// Carries no business logic — display only.
class RuleVersionHistoryEntry extends Equatable {
  final String id;
  final SlaRuleType ruleType;
  final Map<String, dynamic> config;
  final int ruleVersion;
  final int evaluationOrder;
  final DateTime activeFromUtc;
  final DateTime? activeToUtc;
  final bool isActive;

  const RuleVersionHistoryEntry({
    required this.id,
    required this.ruleType,
    required this.config,
    required this.ruleVersion,
    required this.evaluationOrder,
    required this.activeFromUtc,
    this.activeToUtc,
    required this.isActive,
  });

  factory RuleVersionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RuleVersionHistoryEntry(
      id: json['id'] as String,
      ruleType: SlaRuleType.fromString(json['rule_type'] as String),
      config: Map<String, dynamic>.from(json['rule_config'] as Map),
      ruleVersion: json['rule_version'] as int,
      evaluationOrder: json['evaluation_order'] as int,
      activeFromUtc: DateTime.parse(json['active_from_utc'] as String).toUtc(),
      activeToUtc: json['active_to_utc'] != null
          ? DateTime.parse(json['active_to_utc'] as String).toUtc()
          : null,
      isActive: json['is_active'] as bool,
    );
  }

  String get displayLabel => '${_ruleTypeLabel(ruleType)} v$ruleVersion';

  static String _ruleTypeLabel(SlaRuleType type) => switch (type.value) {
    'MAX_TOLERANCE_DELAY' => 'Tolerância de Atraso',
    'MAX_EVIDENCE_GAP' => 'Lacuna de Evidência',
    'MIN_GEOFENCE_COVERAGE' => 'Permanência Mínima',
    'NO_SHOW_PENALTY' => 'Penalidade No-Show',
    _ => type.value,
  };

  @override
  List<Object?> get props => [id, ruleVersion, isActive];
}
