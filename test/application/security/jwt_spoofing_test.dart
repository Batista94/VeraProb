/// JWT Spoofing Attack Prevention Test (INV-1: Identity Sovereignty)
///
/// Validates that the application layer detects and rejects requests where the
/// organization_id in the payload does NOT match the JWT claim, preventing
/// tenant isolation bypass attacks.
///
/// TDD: Written BEFORE implementation (Red phase).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

// ── Helpers ──────────────────────────────────────────────────────────────────

AuthUser _createUser({required String id, required String tenantId}) {
  return AuthUser(id: id, tenantId: tenantId);
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService service;

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    service = TenantValidationService(authRepository: mockAuthRepo);
  });

  group('JWT Spoofing Prevention (INV-1)', () {
    // ── Scenario 1: Legitimate request (payload org matches JWT org) ──────

    test('passes when payload org_id matches JWT org_id', () async {
      const sessionId = 'session-valid-123';
      const payloadOrgId = 'org-legitimate';

      when(() => mockAuthRepo.getUserBySessionId(sessionId)).thenAnswer(
        (_) async => _createUser(id: 'user-1', tenantId: 'org-legitimate'),
      );

      // Should NOT throw
      await service.assertTenantMatches(
        payloadOrgId: payloadOrgId,
        sessionId: sessionId,
      );

      verify(() => mockAuthRepo.getUserBySessionId(sessionId)).called(1);
    });

    // ── Scenario 2: Spoofed payload org_id ────────────────────────────────

    test(
      'throws SovereigntyViolationException when payload org_id ≠ JWT org_id',
      () async {
        const sessionId = 'session-spoofed-456';
        const payloadOrgId = 'org-attacker'; // Spoofed!
        const jwtOrgId = 'org-victim';

        when(() => mockAuthRepo.getUserBySessionId(sessionId)).thenAnswer(
          (_) async => _createUser(id: 'user-1', tenantId: jwtOrgId),
        );

        expect(
          () => service.assertTenantMatches(
            payloadOrgId: payloadOrgId,
            sessionId: sessionId,
          ),
          throwsA(
            isA<SovereigntyViolationException>()
                .having(
                  (e) => e.payloadOrgId,
                  'payloadOrgId',
                  equals(payloadOrgId),
                )
                .having((e) => e.jwtOrgId, 'jwtOrgId', equals(jwtOrgId)),
          ),
        );
      },
    );

    // ── Scenario 3: Expired/invalid session ───────────────────────────────

    test(
      'throws SovereigntyViolationException when session is invalid/null',
      () async {
        const sessionId = 'session-expired-789';
        const payloadOrgId = 'org-some-tenant';

        // Session doesn't exist — user is not authenticated
        when(
          () => mockAuthRepo.getUserBySessionId(sessionId),
        ).thenAnswer((_) async => null);

        expect(
          () => service.assertTenantMatches(
            payloadOrgId: payloadOrgId,
            sessionId: sessionId,
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );

    // ── Scenario 4: Attacker sends valid JWT but wrong payload org ────────

    test(
      'detects org mismatch even with valid authenticated session',
      () async {
        const sessionId = 'session-valid-attacker';
        const payloadOrgId =
            'org-target-victim'; // Trying to access another org's data

        when(() => mockAuthRepo.getUserBySessionId(sessionId)).thenAnswer(
          (_) async =>
              _createUser(id: 'attacker-user', tenantId: 'org-attacker-real'),
        );

        expect(
          () => service.assertTenantMatches(
            payloadOrgId: payloadOrgId,
            sessionId: sessionId,
          ),
          throwsA(
            isA<SovereigntyViolationException>()
                .having(
                  (e) => e.payloadOrgId,
                  'payloadOrgId',
                  equals('org-target-victim'),
                )
                .having(
                  (e) => e.jwtOrgId,
                  'jwtOrgId',
                  equals('org-attacker-real'),
                ),
          ),
        );
      },
    );

    // ── Scenario 5: Null payload org_id ───────────────────────────────────

    test(
      'throws SovereigntyViolationException when payload org_id is empty',
      () async {
        const sessionId = 'session-valid-123';
        const payloadOrgId = ''; // Missing org_id

        when(() => mockAuthRepo.getUserBySessionId(sessionId)).thenAnswer(
          (_) async => _createUser(id: 'user-1', tenantId: 'org-legitimate'),
        );

        expect(
          () => service.assertTenantMatches(
            payloadOrgId: payloadOrgId,
            sessionId: sessionId,
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );

    // ── Scenario 6: Case sensitivity ──────────────────────────────────────

    test(
      'treats different casing as different org_id (case-sensitive match)',
      () async {
        const sessionId = 'session-valid-123';
        const payloadOrgId = 'ORG-LEGITIMATE'; // Different casing
        const jwtOrgId = 'org-legitimate';

        when(() => mockAuthRepo.getUserBySessionId(sessionId)).thenAnswer(
          (_) async => _createUser(id: 'user-1', tenantId: jwtOrgId),
        );

        // Case mismatch should still fail — exact string comparison required
        expect(
          () => service.assertTenantMatches(
            payloadOrgId: payloadOrgId,
            sessionId: sessionId,
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );
  });

  group('Origin Ownership Check (INV-27)', () {
    test('passes when resource org matches requester org', () {
      // Same org — allowed
      service.verifySourceOwnership(
        resourceOrgId: 'org-123',
        requesterOrgId: 'org-123',
      );
      // No exception — passes
    });

    test(
      'throws ResourceNotFoundException when resource org ≠ requester org',
      () {
        // INV-27: treat as "not found" to prevent inference
        expect(
          () => service.verifySourceOwnership(
            resourceOrgId: 'org-other',
            requesterOrgId: 'org-requester',
            resourceType: 'contract',
            resourceId: 'contract-456',
          ),
          throwsA(
            isA<ResourceNotFoundException>()
                .having(
                  (e) => e.resourceType,
                  'resourceType',
                  equals('contract'),
                )
                .having(
                  (e) => e.resourceId,
                  'resourceId',
                  equals('contract-456'),
                ),
          ),
        );
      },
    );

    test(
      'throws ResourceNotFoundException without resource details when not provided',
      () {
        expect(
          () => service.verifySourceOwnership(
            resourceOrgId: 'org-other',
            requesterOrgId: 'org-requester',
          ),
          throwsA(isA<ResourceNotFoundException>()),
        );
      },
    );
  });
}
