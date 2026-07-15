import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/simulate_sla_sandbox_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_result.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_session.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sandbox_simulation_service.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sandbox_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

/// Tracks whether [simulate] was invoked — fails the test if called unexpectedly.
class _SpySandboxService {
  int simulateCalls = 0;
  final bool failIfSimulateCalled;

  _SpySandboxService({this.failIfSimulateCalled = false});

  Future<String> simulate({
    required String organizationId,
    required String contractId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required SandboxSimulationOverrides overrides,
    required String sessionLabel,
  }) async {
    simulateCalls++;
    if (failIfSimulateCalled) {
      fail('repository.simulate must not be called for unauthorized users');
    }
    return 'session-ok';
  }

  Future<List<SandboxSimulationSession>> listSessions({
    required String organizationId,
    String? contractId,
    int limit = 50,
  }) async {
    return fail('listSessions must not be called without sandbox RBAC');
  }

  Future<SandboxSimulationSession?> getSession({
    required String organizationId,
    required String sessionId,
  }) async {
    return fail('getSession must not be called without sandbox RBAC');
  }

  Future<List<SandboxSimulationResult>> listResults({
    required String organizationId,
    required String sessionId,
  }) async {
    return fail('listResults must not be called without sandbox RBAC');
  }
}

/// Concrete subtype so overrides of [sandboxSimulationServiceProvider] type-check.
class _SpyPostgresSandboxService extends Fake
    implements PostgresSandboxSimulationService {
  final _SpySandboxService inner;

  _SpyPostgresSandboxService(this.inner);

  @override
  Future<String> simulate({
    required String organizationId,
    required String contractId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required SandboxSimulationOverrides overrides,
    required String sessionLabel,
  }) => inner.simulate(
    organizationId: organizationId,
    contractId: contractId,
    periodStartUtc: periodStartUtc,
    periodEndUtc: periodEndUtc,
    overrides: overrides,
    sessionLabel: sessionLabel,
  );

  @override
  Future<List<SandboxSimulationSession>> listSessions({
    required String organizationId,
    String? contractId,
    int limit = 50,
  }) => inner.listSessions(
    organizationId: organizationId,
    contractId: contractId,
    limit: limit,
  );

  @override
  Future<SandboxSimulationSession?> getSession({
    required String organizationId,
    required String sessionId,
  }) => inner.getSession(organizationId: organizationId, sessionId: sessionId);

  @override
  Future<List<SandboxSimulationResult>> listResults({
    required String organizationId,
    required String sessionId,
  }) => inner.listResults(organizationId: organizationId, sessionId: sessionId);
}

void main() {
  late _SpySandboxService spy;
  late _SpyPostgresSandboxService spyPostgres;
  late MockAuthRepository mockAuth;

  setUp(() {
    spy = _SpySandboxService(failIfSimulateCalled: true);
    spyPostgres = _SpyPostgresSandboxService(spy);
    mockAuth = MockAuthRepository();
    when(() => mockAuth.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'admin@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  ProviderContainer unauthorizedContainer(UserRole role) {
    return ProviderContainer.test(
      overrides: [
        currentUserRoleProvider.overrideWithValue(role),
        permissionServiceProvider.overrideWithValue(
          const PermissionService(permissions: {}, scopes: {}),
        ),
        currentOrganizationIdProvider.overrideWithValue('org-1'),
        currentSessionIdProvider.overrideWithValue('sess-1'),
        sandboxSimulationServiceProvider.overrideWithValue(spyPostgres),
      ],
    );
  }

  group('SandboxSimulationController — RBAC before repository', () {
    test(
      'operator WITHOUT TENANT_ADMIN / sandbox:simulate aborts BEFORE simulate()',
      () async {
        final container = unauthorizedContainer(UserRole.operator);
        addTearDown(container.dispose);

        final result = await container
            .read(sandboxSimulationControllerProvider.notifier)
            .runSimulation(
              contractId: 'ct-1',
              periodStartUtc: DateTime.utc(2026, 1, 1),
              periodEndUtc: DateTime.utc(2026, 2, 1),
              overrides: const SandboxSimulationOverrides(),
              sessionLabel: 'Ataque',
            );

        expect(result, isNull);
        expect(spy.simulateCalls, 0);

        final state = container.read(sandboxSimulationControllerProvider);
        expect(state.hasError, isTrue);
        expect(state.error, isA<String>());
        expect(
          state.error,
          SandboxSimulationException(
            SandboxSimulationFailure.unauthorized,
          ).message,
        );
      },
    );

    test('auditor is denied and repository is never touched', () async {
      final container = unauthorizedContainer(UserRole.auditor);
      addTearDown(container.dispose);

      await container
          .read(sandboxSimulationControllerProvider.notifier)
          .runSimulation(
            contractId: 'ct-1',
            periodStartUtc: DateTime.utc(2026, 1, 1),
            periodEndUtc: DateTime.utc(2026, 2, 1),
            overrides: const SandboxSimulationOverrides(),
            sessionLabel: 'Auditor probe',
          );

      expect(spy.simulateCalls, 0);
      expect(container.read(canSimulateSandboxProvider), isFalse);
    });

    test('canSimulateSandboxProvider is false for operator without claim', () {
      final container = unauthorizedContainer(UserRole.operator);
      addTearDown(container.dispose);
      expect(container.read(canSimulateSandboxProvider), isFalse);
    });

    test('canSimulateSandboxProvider is true for TENANT_ADMIN', () {
      final container = unauthorizedContainer(UserRole.admin);
      addTearDown(container.dispose);
      expect(container.read(canSimulateSandboxProvider), isTrue);
    });

    test(
      'canSimulateSandboxProvider is true for operator with sandbox:simulate',
      () {
        final container = ProviderContainer.test(
          overrides: [
            currentUserRoleProvider.overrideWithValue(UserRole.operator),
            permissionServiceProvider.overrideWithValue(
              const PermissionService(
                permissions: {'sandbox:simulate'},
                scopes: {},
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        expect(container.read(canSimulateSandboxProvider), isTrue);
      },
    );

    test(
      'query providers return empty without calling repo when unauthorized',
      () async {
        final container = unauthorizedContainer(UserRole.operator);
        addTearDown(container.dispose);

        final sessions = await container.read(
          sandboxSessionsProvider(null).future,
        );
        final detail = await container.read(
          sandboxSessionDetailProvider('sess-x').future,
        );
        final results = await container.read(
          sandboxSessionResultsProvider('sess-x').future,
        );

        expect(sessions, isEmpty);
        expect(detail, isNull);
        expect(results, isEmpty);
      },
    );
  });

  group('SandboxSimulationController — authorized path reaches service', () {
    test('admin invokes simulate exactly once', () async {
      spy = _SpySandboxService(failIfSimulateCalled: false);
      spyPostgres = _SpyPostgresSandboxService(spy);

      final container = ProviderContainer.test(
        overrides: [
          currentUserRoleProvider.overrideWithValue(UserRole.admin),
          permissionServiceProvider.overrideWithValue(
            const PermissionService(permissions: {}, scopes: {}),
          ),
          currentOrganizationIdProvider.overrideWithValue('org-1'),
          currentSessionIdProvider.overrideWithValue('sess-1'),
          sandboxSimulationServiceProvider.overrideWithValue(spyPostgres),
          simulateSlaSandboxHandlerProvider.overrideWithValue(
            SimulateSlaSandboxHandler(
              tenantValidator: TenantValidationService(
                authRepository: mockAuth,
              ),
              commandService: spyPostgres,
              permissions: const PermissionService(permissions: {}, scopes: {}),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final id = await container
          .read(sandboxSimulationControllerProvider.notifier)
          .runSimulation(
            contractId: 'ct-1',
            periodStartUtc: DateTime.utc(2026, 1, 1),
            periodEndUtc: DateTime.utc(2026, 2, 1),
            overrides: const SandboxSimulationOverrides(),
            sessionLabel: 'OK',
          );

      expect(id, 'session-ok');
      expect(spy.simulateCalls, 1);
      expect(
        container.read(sandboxSimulationControllerProvider).hasValue,
        isTrue,
      );
    });
  });
}
