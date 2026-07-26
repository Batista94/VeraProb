import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/sandbox_simulation_service.dart';
import 'package:veraprob/application/sla_audit/simulate_sla_sandbox_command.dart';
import 'package:veraprob/application/sla_audit/simulate_sla_sandbox_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_exception.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class _TrackingCommandService implements SandboxSimulationCommandService {
  int simulateCalls = 0;

  @override
  Future<String> simulate({
    required String organizationId,
    required String contractId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required SandboxSimulationOverrides overrides,
    required String sessionLabel,
  }) async {
    simulateCalls++;
    return 'session-created';
  }
}

void main() {
  late MockAuthRepository mockAuth;
  late TenantValidationService tenantValidator;
  late _TrackingCommandService commandService;
  late SimulateSlaSandboxHandler handler;

  setUp(() {
    mockAuth = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuth);
    commandService = _TrackingCommandService();
    when(() => mockAuth.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'admin@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  SimulateSlaSandboxHandler buildHandler({Set<String> permissions = const {}}) {
    return SimulateSlaSandboxHandler(
      tenantValidator: tenantValidator,
      commandService: commandService,
      permissions: PermissionService(
        permissions: permissions,
        scopes: const {},
      ),
    );
  }

  SimulateSlaSandboxCommand cmd({
    UserRole role = UserRole.admin,
    DateTime? start,
    DateTime? end,
    SandboxSimulationOverrides? overrides,
  }) {
    return SimulateSlaSandboxCommand(
      organizationId: 'org-1',
      contractId: 'contract-1',
      periodStartUtc: start ?? DateTime.utc(2026, 1, 1),
      periodEndUtc: end ?? DateTime.utc(2026, 3, 1),
      overrides: overrides ?? const SandboxSimulationOverrides(),
      sessionLabel: 'Teste',
      callerRole: role,
      sessionId: 'session-1',
    );
  }

  group('SimulateSlaSandboxHandler — RBAC', () {
    test(
      'operator without sandbox:simulate is denied BEFORE simulate()',
      () async {
        handler = buildHandler();
        await expectLater(
          handler.handle(cmd(role: UserRole.operator)),
          throwsA(
            isA<SandboxSimulationException>().having(
              (e) => e.failure,
              'failure',
              SandboxSimulationFailure.unauthorized,
            ),
          ),
        );
        expect(commandService.simulateCalls, 0);
      },
    );

    test(
      'auditor without sandbox:simulate is denied BEFORE simulate()',
      () async {
        handler = buildHandler();
        await expectLater(
          handler.handle(cmd(role: UserRole.auditor)),
          throwsA(isA<SandboxSimulationException>()),
        );
        expect(commandService.simulateCalls, 0);
      },
    );

    test(
      'superAdmin without sandbox:simulate is denied (cannot invoke for tenant)',
      () async {
        handler = buildHandler();
        await expectLater(
          handler.handle(cmd(role: UserRole.superAdmin)),
          throwsA(
            isA<SandboxSimulationException>().having(
              (e) => e.failure,
              'failure',
              SandboxSimulationFailure.unauthorized,
            ),
          ),
        );
        expect(commandService.simulateCalls, 0);
      },
    );

    test(
      'TENANT_ADMIN (UserRole.admin) is allowed and invokes simulate()',
      () async {
        handler = buildHandler();
        final id = await handler.handle(cmd(role: UserRole.admin));
        expect(id, 'session-created');
        expect(commandService.simulateCalls, 1);
      },
    );

    test('operator WITH sandbox:simulate permission is allowed', () async {
      handler = buildHandler(permissions: {'sandbox:simulate'});
      final id = await handler.handle(cmd(role: UserRole.operator));
      expect(id, 'session-created');
      expect(commandService.simulateCalls, 1);
    });
  });

  group('SimulateSlaSandboxHandler — period / adverse', () {
    setUp(() => handler = buildHandler());

    test('rejects non-UTC period (INV-6)', () async {
      await expectLater(
        handler.handle(
          cmd(start: DateTime(2026, 1, 1), end: DateTime.utc(2026, 2, 1)),
        ),
        throwsA(
          isA<SandboxSimulationException>().having(
            (e) => e.failure,
            'failure',
            SandboxSimulationFailure.invalidPeriod,
          ),
        ),
      );
      expect(commandService.simulateCalls, 0);
    });

    test('rejects end <= start', () async {
      await expectLater(
        handler.handle(
          cmd(start: DateTime.utc(2026, 3, 1), end: DateTime.utc(2026, 3, 1)),
        ),
        throwsA(
          isA<SandboxSimulationException>().having(
            (e) => e.failure,
            'failure',
            SandboxSimulationFailure.invalidPeriod,
          ),
        ),
      );
      expect(commandService.simulateCalls, 0);
    });

    test('rejects period longer than ~6 months', () async {
      await expectLater(
        handler.handle(
          cmd(start: DateTime.utc(2026, 1, 1), end: DateTime.utc(2026, 8, 1)),
        ),
        throwsA(
          isA<SandboxSimulationException>().having(
            (e) => e.failure,
            'failure',
            SandboxSimulationFailure.periodTooLong,
          ),
        ),
      );
      expect(commandService.simulateCalls, 0);
    });

    test('wrong-org session fails tenant validation before simulate', () async {
      when(() => mockAuth.getUserBySessionId(any())).thenAnswer(
        (_) async => const domain.AuthUser(
          id: 'user-1',
          email: 'x@test.com',
          tenantId: 'other-org',
        ),
      );
      await expectLater(handler.handle(cmd()), throwsA(anything));
      expect(commandService.simulateCalls, 0);
    });
  });
}
