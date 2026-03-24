import 'package:equatable/equatable.dart';
import 'contractual_rule.dart';

/// Represents a single frozen rule inside a snapshot.
class RuleSnapshotItem extends Equatable {
  final String ruleId;
  final SlaRuleType ruleType;
  // architectural-note: config is intentionally Map<String, dynamic> — frozen
  // snapshot of JSONB rule parameters at declaration time (INV-7: deterministic
  // replay). Sealed RuleConfig hierarchy deferred to Phase 10.
  final Map<String, dynamic> config;
  final int ruleVersion;
  final int evaluationOrder;

  const RuleSnapshotItem({
    required this.ruleId,
    required this.ruleType,
    required this.config,
    required this.ruleVersion,
    required this.evaluationOrder,
  });

  factory RuleSnapshotItem.fromJson(Map<String, dynamic> json) {
    return RuleSnapshotItem(
      ruleId: json['ruleId'],
      ruleType: SlaRuleType.fromString(json['ruleType']),
      config: Map<String, dynamic>.from(json['config']),
      ruleVersion: json['ruleVersion'],
      evaluationOrder: json['evaluationOrder'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ruleId': ruleId,
      'ruleType': ruleType.value,
      'config': config,
      'ruleVersion': ruleVersion,
      'evaluationOrder': evaluationOrder,
    };
  }

  @override
  List<Object?> get props => [
    ruleId,
    ruleType,
    config,
    ruleVersion,
    evaluationOrder,
  ];
}

/// The immutable snapshot embedded within a `PlanDeclaration`.
class RuleSnapshot extends Equatable {
  final List<RuleSnapshotItem> rules;

  const RuleSnapshot(this.rules);

  /// Helper to get ordered rules for engine resolution
  List<RuleSnapshotItem> get orderedRules {
    final sorted = List<RuleSnapshotItem>.from(rules);
    sorted.sort((a, b) => a.evaluationOrder.compareTo(b.evaluationOrder));
    return sorted;
  }

  factory RuleSnapshot.fromJson(List<dynamic> jsonList) {
    final list = jsonList
        .map((e) => RuleSnapshotItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return RuleSnapshot(list);
  }

  List<Map<String, dynamic>> toJson() {
    return rules.map((e) => e.toJson()).toList();
  }

  @override
  List<Object?> get props => [rules];
}
