import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Typed failure modes for the SLA Sandbox simulation flow.
///
/// All user-facing messages are in Portuguese (INV-10). Raw database errors
/// and stack traces must never reach the UI.
enum SandboxSimulationFailure {
  unauthorized,
  invalidPeriod,
  periodTooLong,
  timeout,
  concurrentLock,
  eventLimitExceeded,
  sessionQuotaExceeded,
  contractNotFound,
}

/// Domain exception for SLA Sandbox operations with safe Portuguese messages.
class SandboxSimulationException extends DomainException {
  final SandboxSimulationFailure failure;

  SandboxSimulationException(this.failure) : super(_messageFor(failure));

  static String _messageFor(SandboxSimulationFailure failure) {
    return switch (failure) {
      SandboxSimulationFailure.unauthorized =>
        'Você não tem permissão para executar simulações de SLA.',
      SandboxSimulationFailure.invalidPeriod =>
        'A data final deve ser posterior à data inicial.',
      SandboxSimulationFailure.periodTooLong =>
        'O período de análise não pode exceder 6 meses. '
            'Divida em simulações menores.',
      SandboxSimulationFailure.timeout =>
        'A simulação excedeu o tempo limite. Reduza o período de análise.',
      SandboxSimulationFailure.concurrentLock =>
        'Uma simulação já está em andamento para esta organização. '
            'Aguarde a conclusão.',
      SandboxSimulationFailure.eventLimitExceeded =>
        'O período selecionado contém mais de 10.000 eventos. '
            'Selecione um intervalo menor.',
      SandboxSimulationFailure.sessionQuotaExceeded =>
        'Limite de 50 simulações ativas atingido. '
            'Aguarde a expiração de sessões antigas ou exporte os resultados.',
      SandboxSimulationFailure.contractNotFound =>
        'Contrato não encontrado ou indisponível.',
    };
  }
}
