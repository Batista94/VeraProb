import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_exception.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';
import 'package:veraprob/infrastructure/sla_audit/sandbox_simulation_error_mapper.dart';

class TestErrorMapper
    with PostgresErrorInterceptor, SandboxSimulationErrorMapper {}

void main() {
  group('SandboxSimulationErrorMapper', () {
    late TestErrorMapper mapper;

    setUp(() {
      mapper = TestErrorMapper();
    });

    test('maps timeout errors properly', () {
      const ex1 = PostgrestException(
        message: 'statement timeout',
        code: '57014',
      );
      final result1 =
          mapper.mapSandboxSimulationException(ex1)
              as SandboxSimulationException;
      expect(result1.failure, SandboxSimulationFailure.timeout);

      const ex2 = PostgrestException(
        message: 'canceling statement due to user request',
        code: '',
      );
      final result2 =
          mapper.mapSandboxSimulationException(ex2)
              as SandboxSimulationException;
      expect(result2.failure, SandboxSimulationFailure.timeout);
    });

    test('maps concurrent lock errors properly', () {
      const ex1 = PostgrestException(
        message: 'could not obtain lock',
        code: '55P03',
      );
      final result1 =
          mapper.mapSandboxSimulationException(ex1)
              as SandboxSimulationException;
      expect(result1.failure, SandboxSimulationFailure.concurrentLock);

      const ex2 = PostgrestException(
        message: 'a simulation is already running for this organization',
        code: 'P0001',
      );
      final result2 =
          mapper.mapSandboxSimulationException(ex2)
              as SandboxSimulationException;
      expect(result2.failure, SandboxSimulationFailure.concurrentLock);
    });

    test('maps event limit exceeded errors properly', () {
      const ex = PostgrestException(
        message: 'the selected period contains more than 10,000 events',
        code: 'P0001',
      );
      final result =
          mapper.mapSandboxSimulationException(ex)
              as SandboxSimulationException;
      expect(result.failure, SandboxSimulationFailure.eventLimitExceeded);
    });

    test('maps session quota exceeded errors properly', () {
      const ex = PostgrestException(
        message: 'session quota exceeded',
        code: 'P0001',
      );
      final result =
          mapper.mapSandboxSimulationException(ex)
              as SandboxSimulationException;
      expect(result.failure, SandboxSimulationFailure.sessionQuotaExceeded);
    });

    test('maps period validation errors properly', () {
      const ex1 = PostgrestException(
        message: 'period cannot exceed 6 months',
        code: 'P0001',
      );
      final result1 =
          mapper.mapSandboxSimulationException(ex1)
              as SandboxSimulationException;
      expect(result1.failure, SandboxSimulationFailure.periodTooLong);

      const ex2 = PostgrestException(
        message: 'period_end must be after period_start',
        code: 'P0001',
      );
      final result2 =
          mapper.mapSandboxSimulationException(ex2)
              as SandboxSimulationException;
      expect(result2.failure, SandboxSimulationFailure.invalidPeriod);
    });

    test(
      'maps contract not found / wrong org / RLS denial errors (INV-26)',
      () {
        const ex1 = PostgrestException(
          message: 'no rows returned',
          code: 'PGRST116',
        );
        final result1 =
            mapper.mapSandboxSimulationException(ex1)
                as SandboxSimulationException;
        expect(result1.failure, SandboxSimulationFailure.contractNotFound);

        const ex2 = PostgrestException(
          message: 'contract not_found',
          code: 'P0001',
        );
        final result2 =
            mapper.mapSandboxSimulationException(ex2)
                as SandboxSimulationException;
        expect(result2.failure, SandboxSimulationFailure.contractNotFound);
      },
    );

    test(
      'fails closed mapping unknown errors to IntegrityException (anti-oracle)',
      () {
        const ex = PostgrestException(
          message:
              'some obscure database internal error detailing column names',
          code: 'XX000',
        );
        final result = mapper.mapSandboxSimulationException(ex);

        expect(result, isA<IntegrityException>());
        expect(
          (result as IntegrityException).message,
          contains('Não foi possível concluir a simulação'),
        );
        expect(
          result.message,
          isNot(contains('obscure')),
        ); // Does not leak DB internals
      },
    );

    test('parses nested JSON payload messages correctly', () {
      const jsonMsg = '{"code": "55P03", "message": "could not obtain lock"}';
      const ex = PostgrestException(message: jsonMsg, code: 'P0001');
      final result =
          mapper.mapSandboxSimulationException(ex)
              as SandboxSimulationException;
      expect(result.failure, SandboxSimulationFailure.concurrentLock);
    });
  });
}
