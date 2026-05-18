import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/super_admin_bypass_tenant_validator.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test doubles
// ─────────────────────────────────────────────────────────────────────────────

class _MockAuthRepository extends Mock implements IAuthRepository {}

// ─────────────────────────────────────────────────────────────────────────────
// Forensic constants — INV-1: no lazy matchers for org IDs, ever
// ─────────────────────────────────────────────────────────────────────────────

const _orgVictim = 'org-victim';
const _orgAttacker = 'org-attacker';
const _orgOwner = 'org-owner';
const _sessionValid = 'session-valid-550e8400';
const _sessionExpired = 'session-expired-deadbeef';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

AuthUser _userOf(String tenantId) => AuthUser(
  id: 'user-${tenantId.hashCode.abs()}',
  email: '$tenantId@internal.test',
  tenantId: tenantId,
);

void main() {
  late _MockAuthRepository mockRepo;
  late TenantValidationService service;

  setUp(() {
    mockRepo = _MockAuthRepository();
    service = TenantValidationService(authRepository: mockRepo);
  });

  // ─── assertTenantMatches ───────────────────────────────────────────────────

  group('assertTenantMatches', () {
    // ── 1: Perfect match → silent completion (INV-1 green path) ──────────────
    test(
      'completes silently when payloadOrgId exactly matches JWT claim',
      () async {
        when(
          () => mockRepo.getUserBySessionId(_sessionValid),
        ).thenAnswer((_) async => _userOf(_orgVictim));

        await expectLater(
          service.assertTenantMatches(
            payloadOrgId: _orgVictim,
            sessionId: _sessionValid,
          ),
          completes,
        );
      },
    );

    // ── 2: Cross-tenant breach → forensic evidence captured (INV-1 red path) ─
    test('throws SovereigntyViolationException whose forensic fields record '
        'exactly who attacked whom', () async {
      when(
        () => mockRepo.getUserBySessionId(_sessionValid),
      ).thenAnswer((_) async => _userOf(_orgVictim));

      SovereigntyViolationException? caught;
      try {
        await service.assertTenantMatches(
          payloadOrgId: _orgAttacker,
          sessionId: _sessionValid,
        );
      } on SovereigntyViolationException catch (e) {
        caught = e;
      }

      expect(
        caught,
        isNotNull,
        reason: 'Service MUST throw on cross-tenant breach',
      );
      expect(
        caught!.payloadOrgId,
        equals(_orgAttacker),
        reason: 'Forensic: payloadOrgId must capture the attacker org',
      );
      expect(
        caught.jwtOrgId,
        equals(_orgVictim),
        reason: 'Forensic: jwtOrgId must capture the victim org',
      );
    });

    // ── 3: Expired/null session → jwtOrgId recorded as "none" ────────────────
    test('throws SovereigntyViolationException with jwtOrgId="none" when '
        'session is invalid or expired', () async {
      when(
        () => mockRepo.getUserBySessionId(_sessionExpired),
      ).thenAnswer((_) async => null);

      SovereigntyViolationException? caught;
      try {
        await service.assertTenantMatches(
          payloadOrgId: _orgAttacker,
          sessionId: _sessionExpired,
        );
      } on SovereigntyViolationException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught!.payloadOrgId, equals(_orgAttacker));
      expect(
        caught.jwtOrgId,
        equals('none'),
        reason: 'Expired session MUST record jwtOrgId as literal "none"',
      );
    });

    // ── 4: Empty payloadOrgId → fail-closed BEFORE reaching the database ─────
    test('blocks immediately (fail-closed) on empty payloadOrgId without '
        'touching the repository', () async {
      await expectLater(
        () => service.assertTenantMatches(
          payloadOrgId: '',
          sessionId: _sessionValid,
        ),
        throwsA(isA<SovereigntyViolationException>()),
      );
      verifyNever(() => mockRepo.getUserBySessionId(any()));
    });

    // ── 5: Case-sensitive enforcement — exact byte match required (INV-1) ─────
    test(
      'throws on case-sensitive mismatch — "Org-Victim" != "org-victim"',
      () async {
        when(
          () => mockRepo.getUserBySessionId(_sessionValid),
        ).thenAnswer((_) async => _userOf(_orgVictim));

        SovereigntyViolationException? caught;
        try {
          await service.assertTenantMatches(
            payloadOrgId: 'Org-Victim',
            sessionId: _sessionValid,
          );
        } on SovereigntyViolationException catch (e) {
          caught = e;
        }

        expect(
          caught,
          isNotNull,
          reason: 'Org IDs are case-sensitive — mixed case must be rejected',
        );
        expect(caught!.payloadOrgId, equals('Org-Victim'));
        expect(caught.jwtOrgId, equals(_orgVictim));
      },
    );

    // ── 6: toForensicString encodes full attacker/victim chain ────────────────
    test('toForensicString contains both attacker and victim org IDs for '
        'internal security logging', () async {
      when(
        () => mockRepo.getUserBySessionId(_sessionValid),
      ).thenAnswer((_) async => _userOf(_orgVictim));

      SovereigntyViolationException? caught;
      try {
        await service.assertTenantMatches(
          payloadOrgId: _orgAttacker,
          sessionId: _sessionValid,
        );
      } on SovereigntyViolationException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      final forensic = caught!.toForensicString();
      expect(
        forensic,
        contains(_orgAttacker),
        reason: 'Forensic log MUST expose the attacker org',
      );
      expect(
        forensic,
        contains(_orgVictim),
        reason: 'Forensic log MUST expose the victim org',
      );
    });
  });

  // ─── verifySourceOwnership ────────────────────────────────────────────────

  group('verifySourceOwnership', () {
    // ── 7: Owner match → silent completion (INV-27 green path) ───────────────
    test('completes silently when resource belongs to the requester', () {
      expect(
        () => service.verifySourceOwnership(
          resourceOrgId: _orgOwner,
          requesterOrgId: _orgOwner,
          resourceType: 'contract',
          resourceId: 'contract-123',
        ),
        returnsNormally,
      );
    });

    // ── 8: Cross-tenant theft → ResourceNotFoundException (INV-27) ────────────
    test('throws ResourceNotFoundException when attacker requests a resource '
        'owned by another org', () {
      ResourceNotFoundException? caught;
      try {
        service.verifySourceOwnership(
          resourceOrgId: _orgOwner,
          requesterOrgId: _orgAttacker,
          resourceType: 'contract',
          resourceId: 'contract-456',
        );
      } on ResourceNotFoundException catch (e) {
        caught = e;
      }

      expect(
        caught,
        isNotNull,
        reason: 'Cross-tenant resource access MUST be blocked',
      );
    });

    // ── 9: Forensic metadata preserved in thrown exception ────────────────────
    test('thrown ResourceNotFoundException carries the exact resourceType and '
        'resourceId for internal forensic logging', () {
      ResourceNotFoundException? caught;
      try {
        service.verifySourceOwnership(
          resourceOrgId: _orgOwner,
          requesterOrgId: _orgAttacker,
          resourceType: 'sla_template',
          resourceId: 'template-789',
        );
      } on ResourceNotFoundException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(
        caught!.resourceType,
        equals('sla_template'),
        reason: 'Forensic: resourceType must be preserved in exception',
      );
      expect(
        caught.resourceId,
        equals('template-789'),
        reason: 'Forensic: resourceId must be preserved in exception',
      );
    });

    // ── 10: Oracle Attack prevention — exception type is ResourceNotFoundException
    //        (indistinguishable from a real 404 — INV-26) ─────────────────────
    test(
      'exception type is ResourceNotFoundException (not SovereigntyViolation) '
      'to prevent Oracle Attacks (INV-26)',
      () {
        expect(
          () => service.verifySourceOwnership(
            resourceOrgId: _orgOwner,
            requesterOrgId: _orgAttacker,
          ),
          throwsA(isA<ResourceNotFoundException>()),
          reason: 'Must surface as 404-class to prevent data inference',
        );
        expect(
          () => service.verifySourceOwnership(
            resourceOrgId: _orgOwner,
            requesterOrgId: _orgAttacker,
          ),
          isNot(throwsA(isA<SovereigntyViolationException>())),
        );
      },
    );

    // ── 11: Empty requesterOrgId → blocked immediately (INV-27 hygiene) ──────
    test('throws ResourceNotFoundException when requesterOrgId is an empty '
        'string — empty strings must never pass the ownership filter', () {
      ResourceNotFoundException? caught;
      try {
        service.verifySourceOwnership(
          resourceOrgId: _orgOwner,
          requesterOrgId: '',
          resourceType: 'asset',
          resourceId: 'asset-001',
        );
      } on ResourceNotFoundException catch (e) {
        caught = e;
      }

      expect(
        caught,
        isNotNull,
        reason: 'Empty requesterOrgId must never grant access',
      );
    });

    // ── 12: Empty resourceOrgId → blocked immediately (INV-27 hygiene) ───────
    test('throws ResourceNotFoundException when resourceOrgId is an empty '
        'string — dangling resources without an owner must be rejected', () {
      ResourceNotFoundException? caught;
      try {
        service.verifySourceOwnership(
          resourceOrgId: '',
          requesterOrgId: _orgOwner,
          resourceType: 'asset',
          resourceId: 'asset-002',
        );
      } on ResourceNotFoundException catch (e) {
        caught = e;
      }

      expect(
        caught,
        isNotNull,
        reason: 'Empty resourceOrgId must never grant access',
      );
    });
  });

  // ─── SuperAdminBypassTenantValidator ──────────────────────────────────────
  //
  // SuperAdmin JWT carries super_admin: true with null org_id.
  // The bypass is a no-op satisfying the structural INV-1 contract without
  // enforcing tenant equality — SuperAdmin has sovereignty over all orgs.

  group('SuperAdminBypassTenantValidator', () {
    late SuperAdminBypassTenantValidator bypass;

    setUp(() {
      bypass = const SuperAdminBypassTenantValidator();
    });

    // ── 13: Cross-tenant assertTenantMatches → no exception ──────────────────
    test('assertTenantMatches completes silently for any payloadOrgId '
        '— SuperAdmin has sovereignty over all orgs (INV-1 bypass)', () async {
      await expectLater(
        bypass.assertTenantMatches(
          payloadOrgId: _orgAttacker,
          sessionId: _sessionValid,
        ),
        completes,
        reason: 'Bypass must never throw SovereigntyViolationException',
      );
    });

    // ── 14: Empty payloadOrgId → no exception (bypass is unconditional) ──────
    test('assertTenantMatches completes even for empty payloadOrgId '
        '— bypass does not validate structural correctness', () async {
      await expectLater(
        bypass.assertTenantMatches(payloadOrgId: '', sessionId: _sessionValid),
        completes,
      );
    });

    // ── 15: verifySourceOwnership → no exception (bypass is unconditional) ───
    test('verifySourceOwnership completes silently for mismatched orgs '
        '— SuperAdmin owns all resources', () {
      expect(
        () => bypass.verifySourceOwnership(
          resourceOrgId: _orgOwner,
          requesterOrgId: _orgAttacker,
          resourceType: 'org_api_secret',
          resourceId: 'secret-001',
        ),
        returnsNormally,
        reason: 'Bypass must never throw for cross-tenant resource access',
      );
    });

    // ── 16: Structural contract — bypass implements TenantValidationService ──
    test(
      'SuperAdminBypassTenantValidator satisfies the TenantValidationService '
      'interface contract (Liskov substitution)',
      () {
        expect(bypass, isA<TenantValidationService>());
      },
    );
  });
}
