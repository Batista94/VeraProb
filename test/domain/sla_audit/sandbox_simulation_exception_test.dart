import 'package:test/test.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_exception.dart';

void main() {
  group('SandboxSimulationException', () {
    test('maps all enum values to correct Portuguese messages (INV-10)', () {
      final unauthorized = SandboxSimulationException(
        SandboxSimulationFailure.unauthorized,
      );
      expect(unauthorized.message, contains('não tem permissão'));

      final invalidPeriod = SandboxSimulationException(
        SandboxSimulationFailure.invalidPeriod,
      );
      expect(invalidPeriod.message, contains('posterior à data inicial'));

      final periodTooLong = SandboxSimulationException(
        SandboxSimulationFailure.periodTooLong,
      );
      expect(periodTooLong.message, contains('não pode exceder 6 meses'));

      final timeout = SandboxSimulationException(
        SandboxSimulationFailure.timeout,
      );
      expect(timeout.message, contains('tempo limite'));

      final concurrentLock = SandboxSimulationException(
        SandboxSimulationFailure.concurrentLock,
      );
      expect(concurrentLock.message, contains('já está em andamento'));

      final eventLimit = SandboxSimulationException(
        SandboxSimulationFailure.eventLimitExceeded,
      );
      expect(eventLimit.message, contains('10.000 eventos'));

      final sessionQuota = SandboxSimulationException(
        SandboxSimulationFailure.sessionQuotaExceeded,
      );
      expect(sessionQuota.message, contains('Limite de 50 simulações'));

      final notFound = SandboxSimulationException(
        SandboxSimulationFailure.contractNotFound,
      );
      expect(notFound.message, contains('não encontrado'));
    });
  });
}
