import 'package:veraprob/domain/sla_audit/contractual_rule.dart';

/// Flat read model for [ContractualRule] used in presentation layer.
///
/// [config] is `Map<String, Object?>` — never `dynamic` (dart-flutter.md §Strong Typing).
class ContractualRuleView {
  final String id;
  final String ruleSetId;
  final String ruleType;
  final Map<String, Object?> config;
  final int ruleVersion;
  final int evaluationOrder;
  final DateTime activeFromUtc;
  final DateTime? activeToUtc;
  final bool isActive;

  const ContractualRuleView({
    required this.id,
    required this.ruleSetId,
    required this.ruleType,
    required this.config,
    required this.ruleVersion,
    required this.evaluationOrder,
    required this.activeFromUtc,
    this.activeToUtc,
    required this.isActive,
  });

  factory ContractualRuleView.fromDomain(ContractualRule rule) {
    return ContractualRuleView(
      id: rule.id,
      ruleSetId: rule.ruleSetId,
      ruleType: rule.ruleType.value,
      config: Map<String, Object?>.from(rule.config),
      ruleVersion: rule.ruleVersion,
      evaluationOrder: rule.evaluationOrder,
      activeFromUtc: rule.activeFromUtc,
      activeToUtc: rule.activeToUtc,
      isActive: rule.isActive,
    );
  }
}
