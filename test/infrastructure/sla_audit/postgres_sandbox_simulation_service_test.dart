import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_delta.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sandbox_simulation_service.dart';
import 'package:veraprob/infrastructure/sla_audit/sandbox_simulation_error_mapper.dart';

// ── Mocks / fakes ─────────────────────────────────────────────────────────────

class MockSupabaseClient extends Mock implements SupabaseClient {}

/// Mimics `PostgrestFilterBuilder` returned by `SupabaseClient.rpc<String>()`.
/// Errors are only materialized when [then] is awaited (no orphan Future.error).
class FakeRpcBuilder extends Fake implements PostgrestFilterBuilder<String> {
  final String? _value;
  final Object? _error;

  FakeRpcBuilder.success(String value) : _value = value, _error = null;

  FakeRpcBuilder.failure(Object error) : _value = null, _error = error;

  Future<String> get _future {
    if (_error != null) return Future<String>.error(_error);
    return Future<String>.value(_value!);
  }

  @override
  Future<S> then<S>(
    FutureOr<S> Function(String value) onValue, {
    Function? onError,
  }) {
    return _future.then(onValue, onError: onError);
  }

  @override
  Future<String> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) {
    return _future.catchError(onError, test: test);
  }

  @override
  Future<String> whenComplete(FutureOr<void> Function() action) {
    return _future.whenComplete(action);
  }

  @override
  Stream<String> asStream() => _future.asStream();

  @override
  Future<String> timeout(
    Duration timeLimit, {
    FutureOr<String> Function()? onTimeout,
  }) {
    return _future.timeout(timeLimit, onTimeout: onTimeout);
  }
}

class _MapperHarness
    with PostgresErrorInterceptor, SandboxSimulationErrorMapper {}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _orgId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _contractId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

SandboxSimulationOverrides get _overrides => const SandboxSimulationOverrides(
  financialOverrides: SandboxFinancialOverrides(baseFineCents: 15000),
);

Map<String, dynamic> get _sessionRow => <String, dynamic>{
  'id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'organization_id': _orgId,
  'contract_id': _contractId,
  'session_label': 'Simulação',
  'period_start_utc': '2026-01-01T00:00:00Z',
  'period_end_utc': '2026-03-01T00:00:00Z',
  'overrides_snapshot': {
    'financial_overrides': {'base_fine_cents': 15000},
  },
  'baseline_total_fines_cents': 8420000,
  'simulated_total_fines_cents': 7157000,
  'delta_cents': 1263000,
  'delta_bps': -1500,
  'baseline_event_count': 847,
  'simulated_capped_event_count': 18,
  'created_by_user_id': 'user-1',
  'created_at_utc': '2026-07-01T10:00:00Z',
  'expires_at_utc': '2026-07-31T10:00:00Z',
};

void main() {
  late MockSupabaseClient mockClient;
  late PostgresSandboxSimulationService service;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    service = PostgresSandboxSimulationService(mockClient);
  });

  void stubRpc(FakeRpcBuilder builder) {
    // Production calls rpc<String> — stub must match the generic.
    when(
      () => mockClient.rpc<String>(
        'simulate_sla_sandbox',
        params: any(named: 'params'),
      ),
    ).thenAnswer((_) => builder);
  }

  Future<String> runSimulate() {
    return service.simulate(
      organizationId: _orgId,
      contractId: _contractId,
      periodStartUtc: DateTime.utc(2026, 1, 1),
      periodEndUtc: DateTime.utc(2026, 3, 1),
      overrides: _overrides,
      sessionLabel: 'Simulação',
    );
  }

  group('SandboxSimulationErrorMapper — INV-10 Portuguese mapping', () {
    late _MapperHarness mapper;

    setUp(() => mapper = _MapperHarness());

    test(
      'timeout (57014 / statement timeout) → SandboxSimulationFailure.timeout',
      () {
        final mapped = mapper.mapSandboxSimulationException(
          const PostgrestException(
            message: 'canceling statement due to statement timeout',
            code: '57014',
          ),
        );

        expect(mapped, isA<SandboxSimulationException>());
        final ex = mapped as SandboxSimulationException;
        expect(ex.failure, SandboxSimulationFailure.timeout);
        expect(ex.message, contains('tempo limite'));
        expect(ex.message, isNot(contains('57014')));
        expect(ex.message, isNot(contains('statement timeout')));
      },
    );

    test('>10k events → SandboxSimulationFailure.eventLimitExceeded', () {
      final mapped = mapper.mapSandboxSimulationException(
        const PostgrestException(
          message:
              'sandbox: period contains more than 10,000 penal events. Narrow the date range.',
          code: 'P0001',
        ),
      );

      expect(mapped, isA<SandboxSimulationException>());
      final ex = mapped as SandboxSimulationException;
      expect(ex.failure, SandboxSimulationFailure.eventLimitExceeded);
      expect(ex.message, contains('10.000'));
      expect(ex.message, isNot(contains('penal events')));
    });

    test('concurrency lock → SandboxSimulationFailure.concurrentLock', () {
      final mapped = mapper.mapSandboxSimulationException(
        const PostgrestException(
          message:
              'sandbox: a simulation is already running for this organization',
          code: '55P03',
        ),
      );

      expect(mapped, isA<SandboxSimulationException>());
      final ex = mapped as SandboxSimulationException;
      expect(ex.failure, SandboxSimulationFailure.concurrentLock);
      expect(ex.message, contains('já está em andamento'));
      expect(ex.message, isNot(contains('55P03')));
      expect(ex.message, isNot(contains('advisory')));
    });

    test('lock_not_available code → concurrentLock', () {
      final mapped = mapper.mapSandboxSimulationException(
        const PostgrestException(
          message: 'could not obtain lock',
          code: 'lock_not_available',
        ),
      );
      expect(
        (mapped as SandboxSimulationException).failure,
        SandboxSimulationFailure.concurrentLock,
      );
    });

    test('session quota → sessionQuotaExceeded', () {
      final mapped = mapper.mapSandboxSimulationException(
        const PostgrestException(
          message:
              'sandbox: session quota exceeded (max 50 active sessions per org)',
          code: 'P0001',
        ),
      );
      expect(
        (mapped as SandboxSimulationException).failure,
        SandboxSimulationFailure.sessionQuotaExceeded,
      );
    });

    test('INV-26 not_found / 42501 → contractNotFound (no oracle)', () {
      for (final code in ['no_data_found', 'PGRST116', '42501', 'P0002']) {
        final mapped = mapper.mapSandboxSimulationException(
          PostgrestException(message: 'not_found', code: code),
        );
        expect(
          (mapped as SandboxSimulationException).failure,
          SandboxSimulationFailure.contractNotFound,
          reason: 'code $code must not leak distinct shapes',
        );
      }
    });

    test(
      'unknown PostgREST code fail-closed — never rethrows raw exception',
      () {
        final mapped = mapper.mapSandboxSimulationException(
          const PostgrestException(
            message: 'some obscure internal postgres fault XYZ',
            code: 'XX000',
          ),
        );

        expect(mapped, isA<IntegrityException>());
        expect(mapped.toString(), isNot(contains('XX000')));
        expect(mapped.toString(), isNot(contains('obscure internal')));
      },
    );
  });

  group('PostgresSandboxSimulationService.simulate — INV-10 via Supabase mock', () {
    test('happy path returns session UUID from RPC', () async {
      const sessionId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
      stubRpc(FakeRpcBuilder.success(sessionId));

      final result = await runSimulate();
      expect(result, sessionId);
      verify(
        () => mockClient.rpc<String>(
          'simulate_sla_sandbox',
          params: any(named: 'params'),
        ),
      ).called(1);
    });

    test('happy path session row maps delta direction with int cents', () {
      final session = SandboxSimulationSession.fromRow(_sessionRow);

      expect(session.baselineTotalFines.cents, isA<int>());
      expect(session.baselineTotalFines.cents, 8420000);
      expect(session.simulatedTotalFines.cents, 7157000);
      expect(session.deltaCents, 1263000);
      expect(session.direction, SandboxDeltaDirection.savings);
      expect(
        session.overridesSnapshot.financialOverrides!.baseFineCents,
        15000,
      );
    });

    test(
      'RPC timeout PostgrestException → SandboxSimulationException(timeout)',
      () async {
        stubRpc(
          FakeRpcBuilder.failure(
            const PostgrestException(
              message: 'canceling statement due to statement timeout',
              code: '57014',
            ),
          ),
        );

        await expectLater(
          runSimulate(),
          throwsA(
            isA<SandboxSimulationException>()
                .having(
                  (e) => e.failure,
                  'failure',
                  SandboxSimulationFailure.timeout,
                )
                .having((e) => e.message, 'message', contains('tempo limite')),
          ),
        );
      },
    );

    test('RPC 10k volume PostgrestException → eventLimitExceeded', () async {
      stubRpc(
        FakeRpcBuilder.failure(
          const PostgrestException(
            message:
                'sandbox: period contains more than 10,000 penal events. Narrow the date range.',
            code: 'P0001',
          ),
        ),
      );

      await expectLater(
        runSimulate(),
        throwsA(
          isA<SandboxSimulationException>().having(
            (e) => e.failure,
            'failure',
            SandboxSimulationFailure.eventLimitExceeded,
          ),
        ),
      );
    });

    test('RPC concurrency lock PostgrestException → concurrentLock', () async {
      stubRpc(
        FakeRpcBuilder.failure(
          const PostgrestException(
            message:
                'sandbox: a simulation is already running for this organization',
            code: '55P03',
          ),
        ),
      );

      await expectLater(
        runSimulate(),
        throwsA(
          isA<SandboxSimulationException>().having(
            (e) => e.failure,
            'failure',
            SandboxSimulationFailure.concurrentLock,
          ),
        ),
      );
    });

    test('raw PostgrestException never escapes the service boundary', () async {
      stubRpc(
        FakeRpcBuilder.failure(
          const PostgrestException(message: 'weird db dump', code: '42P01'),
        ),
      );

      try {
        await runSimulate();
        fail('expected mapped domain exception');
      } catch (e) {
        expect(e, isNot(isA<PostgrestException>()));
        expect(e, isA<IntegrityException>());
        expect('$e', isNot(contains('weird db dump')));
      }
    });

    test(
      'RPC params include org, contract, ISO UTC periods, overrides',
      () async {
        stubRpc(FakeRpcBuilder.success('sess-uuid'));

        await runSimulate();

        final verified = verify(
          () => mockClient.rpc<String>(
            'simulate_sla_sandbox',
            params: captureAny(named: 'params'),
          ),
        );
        final params = verified.captured.single as Map<String, dynamic>;
        expect(params['p_org_id'], _orgId);
        expect(params['p_contract_id'], _contractId);
        expect(params['p_period_start'], '2026-01-01T00:00:00.000Z');
        expect(params['p_period_end'], '2026-03-01T00:00:00.000Z');
        expect(params['p_overrides'], isA<Map<String, dynamic>>());
        expect(
          (params['p_overrides']
              as Map)['financial_overrides']['base_fine_cents'],
          15000,
        );
      },
    );
  });
}
