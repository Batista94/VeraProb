// INV-1: Multi-tenant Isolation — God Mode Security Audit
// CIA Triad enforcement for SuperAdminBypassTenantValidator.
//
// Threat model: motivated adversary with forensic tooling attempting to
// leverage the bypass contract as an escalation vector.
//
// No fallback mocks needed — the SUT is a pure no-op implementation.
// All adversarial scenarios target the CONTRACT, not infrastructure.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/shared/super_admin_bypass_tenant_validator.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAuthRepository extends Mock implements IAuthRepository {}

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _tenantA = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa';
const _tenantB = 'bbbbbbbb-0000-0000-0000-bbbbbbbbbbbb';
const _superAdminId = 'sa-000000-0000-0000-0000-000000000000';
const _validSessionId = 'session-super-admin-valid';

AuthUser _superAdminUser() => const AuthUser(
  id: _superAdminId,
  email: 'sa@veraprob.internal',
  tenantId: '', // SuperAdmin: null tenantId by design (D2)
  role: UserRole.superAdmin,
  isMfaEnabled: true,
);

AuthUser _regularAdminUser({String tenantId = _tenantA}) => AuthUser(
  id: 'admin-user-id',
  email: 'admin@tenant-a.com',
  tenantId: tenantId,
  role: UserRole.admin,
  isMfaEnabled: false,
);

// ── Test Suite ────────────────────────────────────────────────────────────────

void main() {
  late SuperAdminBypassTenantValidator sut;
  late MockAuthRepository mockAuth;
  late TenantValidationService restrictedValidator;

  setUpAll(() {
    registerFallbackValue(_tenantA);
  });

  setUp(() {
    sut = const SuperAdminBypassTenantValidator();
    mockAuth = MockAuthRepository();
    restrictedValidator = TenantValidationService(authRepository: mockAuth);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // C — CONFIDENTIALITY: Strict Isolation (INV-1)
  // ══════════════════════════════════════════════════════════════════════════

  group('C — Confidentiality: INV-1 Isolation', () {
    // C-1 ─ Privilege Escalation: regular admin injects bypass context
    test(
      'C-1 [Adverso] role:admin targeting Tenant-B is rejected by standard validator',
      () async {
        // The bypass validator must NEVER be injected for non-superAdmin actors.
        // The standard TenantValidationService is the gatekeeper.
        when(
          () => mockAuth.getUserBySessionId(any()),
        ).thenAnswer((_) async => _regularAdminUser(tenantId: _tenantA));

        // Admin from tenant-A attempts to claim ownership of tenant-B payload
        await expectLater(
          restrictedValidator.assertTenantMatches(
            payloadOrgId: _tenantB,
            sessionId: _validSessionId,
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );

        // Forensic fields must identify the spoof attempt precisely
        try {
          await restrictedValidator.assertTenantMatches(
            payloadOrgId: _tenantB,
            sessionId: _validSessionId,
          );
        } on SovereigntyViolationException catch (e) {
          expect(e.payloadOrgId, equals(_tenantB));
          expect(e.jwtOrgId, equals(_tenantA));
        }
      },
    );

    // C-2 ─ Null/empty payloadOrgId → fail-close before any I/O
    test(
      'C-2 [Adverso] empty payloadOrgId → SovereigntyViolationException (fail-close, zero I/O)',
      () async {
        // Standard validator must reject structurally-invalid org IDs
        // BEFORE calling the auth repository (fail-fast, no I/O leakage).
        await expectLater(
          restrictedValidator.assertTenantMatches(
            payloadOrgId: '',
            sessionId: _validSessionId,
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );

        // Critical: authRepository must NOT have been called (no I/O on malformed input)
        verifyNever(() => mockAuth.getUserBySessionId(any()));
      },
    );

    // C-3 ─ Malicious characters in payloadOrgId → fail-close
    test(
      'C-3 [Adverso] SQL/special-char injection in payloadOrgId → SovereigntyViolationException',
      () async {
        final maliciousIds = [
          "'; DROP TABLE organizations; --",
          '\x00\x01\x02',
          '../../../etc/passwd',
          'null',
          '   ',
        ];

        for (final maliciousId in maliciousIds) {
          // Empty/whitespace are caught by isEmpty before I/O.
          // Non-empty malicious strings reach the DB query layer — the
          // standard validator will reject them if no matching session exists.
          when(
            () => mockAuth.getUserBySessionId(any()),
          ).thenAnswer((_) async => _regularAdminUser(tenantId: _tenantA));

          await expectLater(
            restrictedValidator.assertTenantMatches(
              payloadOrgId: maliciousId.trim(),
              sessionId: _validSessionId,
            ),
            // Whitespace-only becomes empty after trim → SovereigntyViolationException
            // Injection strings mismatch the JWT org → SovereigntyViolationException
            throwsA(isA<SovereigntyViolationException>()),
            reason: 'maliciousId: "$maliciousId"',
          );
        }
      },
    );

    // C-4 ─ HTTP header case-sensitivity: bypass contract is case-agnostic
    // The bypass validator is injected by the DI layer based on JWT role,
    // NOT by header name parsing. Header case-insensitivity is tested at
    // the HTTP boundary, not inside this validator. This test proves the
    // validator's behavior is invariant regardless of which "bypass path"
    // invokes it — the no-op contract holds unconditionally.
    test(
      'C-4 [Case Sensitivity] bypass validator no-op is invariant to invocation origin',
      () async {
        // Simulating multiple "bypass paths" (different header casing scenarios
        // resolved upstream): the SUT always completes without throwing.
        final orgIds = [_tenantA, _tenantB, 'any-tenant-id'];
        final sessionIds = ['session-1', 'session-2', 'SESSION-UPPER'];

        for (final orgId in orgIds) {
          for (final sessionId in sessionIds) {
            await expectLater(
              sut.assertTenantMatches(
                payloadOrgId: orgId,
                sessionId: sessionId,
              ),
              completes,
              reason: 'orgId=$orgId, sessionId=$sessionId',
            );
          }
        }
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // I — INTEGRITY: Token Verity & State Protection
  // ══════════════════════════════════════════════════════════════════════════

  group('I — Integrity: Token Verity & State Protection', () {
    // I-1 ─ Expired/revoked session → standard validator rejects before permission check
    test(
      'I-1 [Adverso] expired/null session → SovereigntyViolationException (fail-fast, no permission I/O)',
      () async {
        // Expired JWT: authRepository returns null for invalid/expired session
        when(
          () => mockAuth.getUserBySessionId(any()),
        ).thenAnswer((_) async => null);

        await expectLater(
          restrictedValidator.assertTenantMatches(
            payloadOrgId: _tenantA,
            sessionId: 'expired-or-revoked-session-token',
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );

        // Session lookup MUST be called exactly once — no retry, no fallback
        verify(
          () => mockAuth.getUserBySessionId('expired-or-revoked-session-token'),
        ).called(1);
      },
    );

    // I-2 ─ Forged claim: JWT with role:super_admin but wrong signing key
    // This is enforced at the JWT verification layer (Supabase/Edge).
    // At the application layer, the contract invariant is: if the DI system
    // injects TenantValidationService (not bypass), then getUserBySessionId
    // returning a non-superAdmin user triggers standard tenant matching.
    test(
      'I-2 [Adverso] forged super_admin claim resolves to tenant-scoped user → isolation enforced',
      () async {
        // Attacker forged super_admin claim but JWT verification demoted them
        // to their actual role (admin). The session resolves to a tenant user.
        when(
          () => mockAuth.getUserBySessionId(any()),
        ).thenAnswer((_) async => _regularAdminUser(tenantId: _tenantA));

        // With standard validator injected (forged claim rejected upstream):
        // payload org != JWT org → SovereigntyViolationException
        await expectLater(
          restrictedValidator.assertTenantMatches(
            payloadOrgId: _tenantB,
            sessionId: 'forged-super-admin-token',
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );

    // I-3 ─ Least privilege: SuperAdmin without bypass header uses restricted scope
    test(
      'I-3 [Adverso] SuperAdmin omits bypass header → standard validator enforces tenant scope',
      () async {
        // When the bypass header is absent, the DI layer injects the standard
        // TenantValidationService. SuperAdmin's JWT tenantId is '' (empty).
        // The empty tenantId causes a mismatch against ANY non-empty payloadOrgId.
        when(
          () => mockAuth.getUserBySessionId(any()),
        ).thenAnswer((_) async => _superAdminUser());

        // SuperAdmin with empty tenantId vs non-empty payload → mismatch
        await expectLater(
          restrictedValidator.assertTenantMatches(
            payloadOrgId: _tenantA,
            sessionId: _validSessionId,
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );

        final captured = verify(
          () => mockAuth.getUserBySessionId(captureAny()),
        ).captured;
        expect(captured.single, equals(_validSessionId));
      },
    );

    // I-4 ─ State mutation: bypass validator is a pure function (idempotent)
    test(
      'I-4 [Bug] bypass validator does not mutate shared state across invocations',
      () async {
        // Capture the validator identity before any call
        final identityBefore = sut.hashCode;

        // Execute multiple times with distinct inputs
        await sut.assertTenantMatches(
          payloadOrgId: _tenantA,
          sessionId: 'session-call-1',
        );
        await sut.assertTenantMatches(
          payloadOrgId: _tenantB,
          sessionId: 'session-call-2',
        );
        await sut.assertTenantMatches(payloadOrgId: '', sessionId: '');

        sut.verifySourceOwnership(
          resourceOrgId: _tenantA,
          requesterOrgId: _tenantB,
          resourceType: 'contract',
          resourceId: 'res-001',
        );

        // Identity must be unchanged — no mutable state
        expect(sut.hashCode, equals(identityBefore));

        // Re-instantiation: Dart const canonicalization guarantees identical()
        // returns true for const objects with same constructor — this is the
        // proof of zero mutable state: the runtime sees them as one object.
        const sut2 = SuperAdminBypassTenantValidator();
        expect(sut2, isA<SuperAdminBypassTenantValidator>());
        expect(identical(sut, sut2), isTrue); // const → zero mutable state
      },
    );

    // I-5 ─ verifySourceOwnership: bypass never throws regardless of tenant mismatch
    test(
      'I-5 [Integrity] bypass verifySourceOwnership is a pure no-op for ALL org combinations',
      () {
        // Standard validator throws ResourceNotFoundException on cross-tenant access.
        // Bypass must NOT throw — SuperAdmin has sovereignty over all resources.
        expect(
          () => sut.verifySourceOwnership(
            resourceOrgId: _tenantB,
            requesterOrgId: _tenantA,
            resourceType: 'contract',
            resourceId: 'resource-id-xyz',
          ),
          returnsNormally,
        );

        // Contrasted against standard validator which MUST throw
        expect(
          () => restrictedValidator.verifySourceOwnership(
            resourceOrgId: _tenantB,
            requesterOrgId: _tenantA,
            resourceType: 'contract',
            resourceId: 'resource-id-xyz',
          ),
          throwsA(isA<ResourceNotFoundException>()),
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // A — AVAILABILITY: Happy Path & Legitimate Bypass
  // ══════════════════════════════════════════════════════════════════════════

  group('A — Availability: Happy Path & Legitimate Bypass', () {
    // A-1 ─ Legitimate SuperAdmin bypass: valid JWT, valid session, valid target tenant
    test(
      'A-1 [Happy Path] legitimate SuperAdmin bypass completes without exception',
      () async {
        // SuperAdmin: valid JWT, bypass header present (DI injects bypass validator),
        // targeting a valid tenant. Must complete (return void) without any throw.
        await expectLater(
          sut.assertTenantMatches(
            payloadOrgId: _tenantB,
            sessionId: _validSessionId,
          ),
          completes,
        );
      },
    );

    // A-2 ─ No false-positive block: bypass does not reject any valid tenant ID
    test(
      'A-2 [Happy Path] bypass allows cross-tenant access to any well-formed tenant ID',
      () async {
        final validTenantIds = [
          _tenantA,
          _tenantB,
          'cccccccc-0000-0000-0000-cccccccccccc',
          '00000000-0000-0000-0000-000000000000',
        ];

        for (final tenantId in validTenantIds) {
          await expectLater(
            sut.assertTenantMatches(
              payloadOrgId: tenantId,
              sessionId: _validSessionId,
            ),
            completes,
            reason: 'tenantId: $tenantId',
          );
        }
      },
    );

    // A-3 ─ Type contract: bypass implements TenantValidationService interface
    test(
      'A-3 [Contract] SuperAdminBypassTenantValidator satisfies TenantValidationService polymorphic contract',
      () {
        expect(sut, isA<TenantValidationService>());

        // Polymorphic usage must be identical to direct usage
        final TenantValidationService polymorphic = sut;
        expect(
          () => polymorphic.verifySourceOwnership(
            resourceOrgId: _tenantA,
            requesterOrgId: _tenantB,
          ),
          returnsNormally,
        );
      },
    );
  });
}
