/// CreateContractHandler — INV-1 Security Tests (Cross-Tenant Injection)
///
/// Validates that the handler performs Fail-Fast Identity Sync before any
/// repository, domain factory, or ledger operation is invoked.
///
/// TDD: Written BEFORE implementation (Red phase).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/create_contract_command.dart';
import 'package:veraprob/application/sla_audit/create_contract_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contract_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

// ── Helpers ──────────────────────────────────────────────────────────────────

AuthUser _createUser({required String id, required String tenantId}) {
  return AuthUser(id: id, tenantId: tenantId);
}

CreateContractCommand _makeCommand({
  String organizationId = 'org-1',
  String sessionId = 'session-valid',
}) {
  return CreateContractCommand(
    organizationId: organizationId,
    name: 'Contrato Norte',
    contractorName: 'Trans Norte Ltda',
    validFromUtc: DateTime.utc(2026, 1, 1),
    validUntilUtc: DateTime.utc(2026, 12, 31),
    sessionId: sessionId,
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;
  late InMemoryContractRepository repository;
  late InMemorySlaAuditLedgerRepository ledger;
  late CreateContractHandler handler;

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    repository = InMemoryContractRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    handler = CreateContractHandler(
      tenantValidator: tenantValidator,
      contractRepository: repository,
      ledger: ledger,
      clock: FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12, 0, 0)),
    );
  });

  group('CreateContractHandler — INV-1 Security (Cross-Tenant Injection)', () {
    test(
      'happy path: tenant matches → handler proceeds to create contract',
      () async {
        const sessionId = 'session-valid-123';
        const orgId = 'org-1';

        when(
          () => mockAuthRepo.getUserBySessionId(sessionId),
        ).thenAnswer((_) async => _createUser(id: 'user-1', tenantId: orgId));

        final contract = await handler.handle(
          _makeCommand(organizationId: orgId, sessionId: sessionId),
        );

        expect(contract.status.toString(), contains('draft'));
        expect(contract.organizationId, orgId);
        // Verify repository was actually called (security guard passed)
        final saved = await repository.findById(
          contract.id,
          organizationId: orgId,
        );
        expect(saved, isNotNull);
      },
    );

    test(
      'cross-tenant injection: mismatched org_id throws SovereigntyViolationException',
      () async {
        const sessionId = 'session-attacker';
        const attackerOrgId = 'org-attacker';
        const victimOrgId = 'org-victim';

        // Attacker's JWT says org-attacker, but command claims org-victim
        when(() => mockAuthRepo.getUserBySessionId(sessionId)).thenAnswer(
          (_) async => _createUser(id: 'attacker', tenantId: attackerOrgId),
        );

        // Command tries to create a contract under the victim's org
        final command = _makeCommand(
          organizationId: victimOrgId, // Spoofed!
          sessionId: sessionId,
        );

        expect(
          () => handler.handle(command),
          throwsA(
            isA<SovereigntyViolationException>()
                .having(
                  (e) => e.payloadOrgId,
                  'payloadOrgId',
                  equals(victimOrgId),
                )
                .having((e) => e.jwtOrgId, 'jwtOrgId', equals(attackerOrgId)),
          ),
        );

        // Verify: NO contract was created (fail-fast before domain factory)
        expect(await repository.findByOrganization(victimOrgId), isEmpty);
      },
    );

    test(
      'invalid session: no active session throws SovereigntyViolationException',
      () async {
        const sessionId = 'session-expired';

        // No active session
        when(
          () => mockAuthRepo.getUserBySessionId(sessionId),
        ).thenAnswer((_) async => null);

        final command = _makeCommand(
          organizationId: 'org-1',
          sessionId: sessionId,
        );

        expect(
          () => handler.handle(command),
          throwsA(isA<SovereigntyViolationException>()),
        );

        // Verify: NO contract was created
        expect(await repository.findByOrganization('org-1'), isEmpty);
      },
    );

    test('tenant validation runs BEFORE any repository call', () async {
      // This test proves fail-fast: the tenant validator throws before
      // the repository is ever touched.
      const sessionId = 'session-spoofed';

      when(() => mockAuthRepo.getUserBySessionId(sessionId)).thenAnswer(
        (_) async => const AuthUser(id: 'user-x', tenantId: 'org-wrong'),
      );

      final command = _makeCommand(
        organizationId: 'org-target',
        sessionId: sessionId,
      );

      try {
        await handler.handle(command);
        fail('Expected SovereigntyViolationException');
      } on SovereigntyViolationException {
        // Expected — verify repository and ledger were NEVER called.
        // The in-memory repos start empty; if they had been touched,
        // we'd see state changes.
        expect(
          await repository.findByOrganization('org-target'),
          isEmpty,
          reason: 'Repository must not be called before tenant validation',
        );
        expect(
          ledger.entries,
          isEmpty,
          reason: 'Ledger must not be touched before tenant validation',
        );
      }
    });
  });
}
