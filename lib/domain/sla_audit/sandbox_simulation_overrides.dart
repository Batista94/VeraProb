import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// A single rule-type override passed to the shadow evaluation engine.
///
/// Mirrors `contract_rule_versions.rule_config` — keys not overridden fall
/// through to the production rule active at verdict time.
class SandboxRuleOverride extends Equatable {
  final SlaRuleType ruleType;
  final Map<String, dynamic> ruleConfig;

  const SandboxRuleOverride({required this.ruleType, required this.ruleConfig});

  Map<String, dynamic> toJson() => {
    'rule_type': ruleType.value,
    'rule_config': ruleConfig,
  };

  factory SandboxRuleOverride.fromJson(Map<String, dynamic> json) {
    return SandboxRuleOverride(
      ruleType: SlaRuleType.fromString(json['rule_type'] as String),
      ruleConfig: Map<String, dynamic>.from(
        json['rule_config'] as Map? ?? const {},
      ),
    );
  }

  @override
  List<Object?> get props => [ruleType, ruleConfig];
}

/// Optional financial term overrides (stop-loss cap, base fine).
class SandboxFinancialOverrides extends Equatable {
  /// Hypothetical monthly penalty cap in cents (INV-4).
  final int? monthlyPenaltyCapCents;

  /// Hypothetical base fine in cents (INV-4).
  final int? baseFineCents;

  const SandboxFinancialOverrides({
    this.monthlyPenaltyCapCents,
    this.baseFineCents,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (monthlyPenaltyCapCents != null) {
      map['monthly_penalty_cap_cents'] = monthlyPenaltyCapCents;
    }
    if (baseFineCents != null) {
      map['base_fine_cents'] = baseFineCents;
    }
    return map;
  }

  factory SandboxFinancialOverrides.fromJson(Map<String, dynamic> json) {
    return SandboxFinancialOverrides(
      monthlyPenaltyCapCents: (json['monthly_penalty_cap_cents'] as num?)
          ?.toInt(),
      baseFineCents: (json['base_fine_cents'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [monthlyPenaltyCapCents, baseFineCents];
}

/// Ephemeral override payload for [simulate_sla_sandbox] — never persisted to
/// production contract rules; sealed in `overrides_snapshot` on the session.
class SandboxSimulationOverrides extends Equatable {
  final List<SandboxRuleOverride> overrides;
  final SandboxFinancialOverrides? financialOverrides;

  const SandboxSimulationOverrides({
    this.overrides = const [],
    this.financialOverrides,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'overrides': overrides.map((o) => o.toJson()).toList(),
    };
    if (financialOverrides != null) {
      map['financial_overrides'] = financialOverrides!.toJson();
    }
    return map;
  }

  factory SandboxSimulationOverrides.fromJson(Map<String, dynamic> json) {
    final rawOverrides = json['overrides'];
    final overrides = rawOverrides is List
        ? rawOverrides
              .map(
                (e) => SandboxRuleOverride.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList()
        : const <SandboxRuleOverride>[];

    final financialRaw = json['financial_overrides'];
    return SandboxSimulationOverrides(
      overrides: overrides,
      financialOverrides: financialRaw is Map
          ? SandboxFinancialOverrides.fromJson(
              Map<String, dynamic>.from(financialRaw),
            )
          : null,
    );
  }

  void validate() {
    for (final override in overrides) {
      if (override.ruleConfig.isEmpty) {
        throw DomainException(
          'Configuração vazia para a regra ${override.ruleType.value}.',
        );
      }
    }
    final cap = financialOverrides?.monthlyPenaltyCapCents;
    if (cap != null && cap < 0) {
      throw const DomainException(
        'O teto mensal de multas não pode ser negativo.',
      );
    }
    final base = financialOverrides?.baseFineCents;
    if (base != null && base < 0) {
      throw const DomainException('A multa base não pode ser negativa.');
    }
  }

  @override
  List<Object?> get props => [overrides, financialOverrides];
}
