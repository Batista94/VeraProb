import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/presentation/sandbox/validators/sandbox_wizard_validator.dart';

/// Ephemeral form state for the SLA Sandbox creation wizard.
///
/// Monetary fields are already in BIGINT cents (INV-4). The UI converts
/// masked BRL strings via [BrlCurrencyInputFormatter.toCents] before calling
/// the notifier.
class SandboxWizardState extends Equatable {
  final String sessionLabel;
  final String? contractId;
  final DateTime? periodStartUtc;
  final DateTime? periodEndUtc;

  /// Optional MAX_TOLERANCE_DELAY override (minutes).
  final int? delayToleranceMinutes;

  /// Optional monthly penalty cap in cents.
  final int? monthlyPenaltyCapCents;

  /// Optional base fine override in cents.
  final int? baseFineCents;

  const SandboxWizardState({
    this.sessionLabel = '',
    this.contractId,
    this.periodStartUtc,
    this.periodEndUtc,
    this.delayToleranceMinutes,
    this.monthlyPenaltyCapCents,
    this.baseFineCents,
  });

  bool get isValid => SandboxWizardValidator.validate(this).isEmpty;

  List<String> get validationErrors => SandboxWizardValidator.validate(this);

  /// Builds the RPC payload [SandboxSimulationOverrides] from form inputs.
  SandboxSimulationOverrides buildOverrides() {
    final ruleOverrides = <SandboxRuleOverride>[];
    final minutes = delayToleranceMinutes;
    if (minutes != null) {
      ruleOverrides.add(
        SandboxRuleOverride(
          ruleType: SlaRuleType.maxToleranceDelay,
          ruleConfig: {'threshold_minutes': minutes},
        ),
      );
    }

    final cap = monthlyPenaltyCapCents;
    final base = baseFineCents;
    final financial = (cap != null || base != null)
        ? SandboxFinancialOverrides(
            monthlyPenaltyCapCents: cap,
            baseFineCents: base,
          )
        : null;

    return SandboxSimulationOverrides(
      overrides: ruleOverrides,
      financialOverrides: financial,
    );
  }

  SandboxWizardState copyWith({
    String? sessionLabel,
    String? contractId,
    DateTime? periodStartUtc,
    DateTime? periodEndUtc,
    int? delayToleranceMinutes,
    int? monthlyPenaltyCapCents,
    int? baseFineCents,
    bool clearDelayTolerance = false,
    bool clearMonthlyCap = false,
    bool clearBaseFine = false,
  }) {
    return SandboxWizardState(
      sessionLabel: sessionLabel ?? this.sessionLabel,
      contractId: contractId ?? this.contractId,
      periodStartUtc: periodStartUtc ?? this.periodStartUtc,
      periodEndUtc: periodEndUtc ?? this.periodEndUtc,
      delayToleranceMinutes: clearDelayTolerance
          ? null
          : (delayToleranceMinutes ?? this.delayToleranceMinutes),
      monthlyPenaltyCapCents: clearMonthlyCap
          ? null
          : (monthlyPenaltyCapCents ?? this.monthlyPenaltyCapCents),
      baseFineCents: clearBaseFine
          ? null
          : (baseFineCents ?? this.baseFineCents),
    );
  }

  @override
  List<Object?> get props => [
    sessionLabel,
    contractId,
    periodStartUtc,
    periodEndUtc,
    delayToleranceMinutes,
    monthlyPenaltyCapCents,
    baseFineCents,
  ];
}
