import 'package:veraprob/presentation/sandbox/providers/sandbox_wizard_state.dart';

/// Pure validation for the SLA Sandbox creation wizard (UI layer).
///
/// Period cap mirrors the application handler (183 days ≈ 6 months).
abstract final class SandboxWizardValidator {
  /// Max inclusive span accepted by the wizard / RPC compute governance.
  static const Duration maxPeriod = Duration(days: 183);

  static const String maxPeriodMessage =
      'O período máximo permitido é de 6 meses';
  static const String sessionLabelRequired = 'Informe o nome da sessão';
  static const String contractRequired = 'Selecione um contrato';
  static const String startRequired = 'Informe a data inicial';
  static const String endRequired = 'Informe a data final';
  static const String endAfterStart =
      'A data final deve ser posterior à data inicial';

  /// Returns human-readable Portuguese errors (empty = valid).
  static List<String> validate(SandboxWizardState state) {
    final errors = <String>[];

    if (state.sessionLabel.trim().isEmpty) {
      errors.add(sessionLabelRequired);
    }

    final contractId = state.contractId;
    if (contractId == null || contractId.trim().isEmpty) {
      errors.add(contractRequired);
    }

    final start = state.periodStartUtc;
    final end = state.periodEndUtc;

    if (start == null) {
      errors.add(startRequired);
    }
    if (end == null) {
      errors.add(endRequired);
    }

    if (start != null && end != null) {
      if (!end.isAfter(start)) {
        errors.add(endAfterStart);
      } else if (end.difference(start) > maxPeriod) {
        errors.add(maxPeriodMessage);
      }
    }

    return errors;
  }
}
