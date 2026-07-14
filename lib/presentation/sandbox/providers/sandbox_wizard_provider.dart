import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/presentation/sandbox/providers/sandbox_wizard_state.dart';
import 'package:veraprob/presentation/shared/formatters/brl_currency_input_formatter.dart';
import 'package:veraprob/state/providers/sandbox_providers.dart';

export 'sandbox_wizard_state.dart';

/// Ephemeral Riverpod state for the SLA Sandbox creation wizard.
class SandboxWizardNotifier extends Notifier<SandboxWizardState> {
  @override
  SandboxWizardState build() => const SandboxWizardState();

  void setSessionLabel(String value) {
    state = state.copyWith(sessionLabel: value);
  }

  void setContractId(String? contractId) {
    state = state.copyWith(contractId: contractId);
  }

  void setPeriod({DateTime? startUtc, DateTime? endUtc}) {
    state = state.copyWith(
      periodStartUtc: startUtc != null
          ? (startUtc.isUtc ? startUtc : startUtc.toUtc())
          : state.periodStartUtc,
      periodEndUtc: endUtc != null
          ? (endUtc.isUtc ? endUtc : endUtc.toUtc())
          : state.periodEndUtc,
    );
  }

  /// Slider: delay tolerance in whole minutes (MAX_TOLERANCE_DELAY).
  void setDelayToleranceMinutes(double value) {
    state = state.copyWith(delayToleranceMinutes: value.round());
  }

  /// Parses masked BRL (`R$ 5.000,00`) into cents and stores as [int] (INV-4).
  void setMonthlyPenaltyCapFromMasked(String maskedBrl) {
    final cents = BrlCurrencyInputFormatter.toCents(maskedBrl);
    if (cents == null) {
      state = state.copyWith(clearMonthlyCap: true);
      return;
    }
    state = state.copyWith(monthlyPenaltyCapCents: cents);
  }

  void setBaseFineFromMasked(String maskedBrl) {
    final cents = BrlCurrencyInputFormatter.toCents(maskedBrl);
    if (cents == null) {
      state = state.copyWith(clearBaseFine: true);
      return;
    }
    state = state.copyWith(baseFineCents: cents);
  }

  SandboxSimulationOverrides buildOverrides() => state.buildOverrides();

  void reset() => state = const SandboxWizardState();

  /// Runs the Step-1 simulation controller when the form is valid.
  ///
  /// Returns the created session UUID, or `null` on validation / RPC failure.
  Future<String?> executeSimulation() async {
    if (!state.isValid) return null;

    final start = state.periodStartUtc!;
    final end = state.periodEndUtc!;
    final contractId = state.contractId!;
    final label = state.sessionLabel.trim();

    return ref
        .read(sandboxSimulationControllerProvider.notifier)
        .runSimulation(
          contractId: contractId,
          periodStartUtc: start.isUtc ? start : start.toUtc(),
          periodEndUtc: end.isUtc ? end : end.toUtc(),
          overrides: state.buildOverrides(),
          sessionLabel: label,
        );
  }
}

final sandboxWizardProvider =
    NotifierProvider.autoDispose<SandboxWizardNotifier, SandboxWizardState>(
      SandboxWizardNotifier.new,
    );
