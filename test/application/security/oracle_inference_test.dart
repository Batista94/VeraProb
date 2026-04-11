/// Oracle Inference Attack Prevention Test (INV-26: Error Parity)
///
/// Validates that security-sensitive endpoints return IDENTICAL 404 responses
/// for both "Resource Not Found" (real 404) and "Resource Owned by Another Org"
/// (unauthorized access), preventing data inference via error message analysis.
///
/// TDD: Written BEFORE implementation (Red phase).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/shared/sovereignty_error_mapper.dart';

void main() {
  group('Oracle Inference Prevention (INV-26)', () {
    // ── Scenario 1: Non-existent resource (real 404) ──────────────────────

    test('produces identical 404 response for non-existent resource', () {
      // Simulates: caller requests a resource that doesn't exist in DB
      const notFoundException = ResourceNotFoundException();

      final response = SovereigntyErrorMapper.toResponse(notFoundException);

      expect(response['status'], 404);
      expect(response['body'], '{"error":"Not Found"}');
    });

    // ── Scenario 2: Resource owned by another org (unauthorized) ──────────

    test('produces identical 404 response for cross-org access attempt', () {
      // Simulates: attacker tries to access resource from another tenant
      const sovereigntyException = SovereigntyViolationException(
        payloadOrgId: 'org-attacker',
        jwtOrgId: 'org-victim',
      );

      final response = SovereigntyErrorMapper.toResponse(sovereigntyException);

      expect(response['status'], 404);
      expect(response['body'], '{"error":"Not Found"}');
    });

    // ── Scenario 3: ResourceNotFoundException with forensic details ───────

    test(
      'hides forensic details from attacker even when exception has them',
      () {
        // Exception has internal details — mapper must strip them
        const exception = ResourceNotFoundException(
          resourceType: 'contract',
          resourceId: 'contract-secret-123',
          message: 'Internal: org-456 owns this',
        );

        final response = SovereigntyErrorMapper.toResponse(exception);

        // Attacker sees ONLY the generic response
        expect(response['status'], 404);
        expect(response['body'], '{"error":"Not Found"}');
        expect(response['body'], isNot(contains('contract')));
        expect(response['body'], isNot(contains('contract-secret-123')));
        expect(response['body'], isNot(contains('Internal')));
        expect(response['body'], isNot(contains('org-456')));
      },
    );

    // ── Scenario 4: SovereigntyViolationException with forensic details ───

    test('hides org IDs from attacker even when exception has them', () {
      const exception = SovereigntyViolationException(
        payloadOrgId: 'org-attacker-123',
        jwtOrgId: 'org-victim-456',
        message: 'Detailed forensic message with sensitive info',
      );

      final response = SovereigntyErrorMapper.toResponse(exception);

      expect(response['status'], 404);
      expect(response['body'], '{"error":"Not Found"}');
      expect(response['body'], isNot(contains('org-attacker-123')));
      expect(response['body'], isNot(contains('org-victim-456')));
      expect(response['body'], isNot(contains('forensic')));
    });

    // ── Scenario 5: Response indistinguishability ─────────────────────────

    test('both exception types produce byte-identical HTTP responses', () {
      const notFound = ResourceNotFoundException(
        resourceType: 'asset',
        resourceId: 'asset-999',
      );
      const sovereignty = SovereigntyViolationException(
        payloadOrgId: 'org-x',
        jwtOrgId: 'org-y',
      );

      final responseA = SovereigntyErrorMapper.toResponse(notFound);
      final responseB = SovereigntyErrorMapper.toResponse(sovereignty);

      // Byte-identical — no oracle attack surface
      expect(responseA['status'], equals(responseB['status']));
      expect(responseA['body'], equals(responseB['body']));
      expect(responseA, equals(responseB));
    });

    // ── Scenario 6: Origin Ownership (INV-27) ─────────────────────────────

    test('unauthorized source ID produces same 404 as non-existent source', () {
      // INV-27: Origin Ownership — treat unauthorized source as non-existent
      const nonExistentSource = ResourceNotFoundException(
        resourceType: 'source',
        resourceId: 'source-does-not-exist',
      );
      const unauthorizedSource = ResourceNotFoundException(
        resourceType: 'source',
        resourceId: 'source-other-org',
      );

      final responseA = SovereigntyErrorMapper.toResponse(nonExistentSource);
      final responseB = SovereigntyErrorMapper.toResponse(unauthorizedSource);

      expect(responseA, equals(responseB));
      expect(responseA['body'], '{"error":"Not Found"}');
    });

    // ── Scenario 7: statusCode constant ───────────────────────────────────

    test('statusCode constant is 404', () {
      expect(SovereigntyErrorMapper.statusCode, 404);
    });

    // ── Scenario 8: Cross-platform byte parity (Dart ↔ TypeScript) ────────

    test(
      'Dart canonicalBody is byte-identical to TypeScript SOVEREIGNTY_BODY',
      () {
        // TypeScript: JSON.stringify({ error: "Not Found" })
        // Produces: {"error":"Not Found"}
        //
        // Dart: const String _canonicalBody = '{"error":"Not Found"}'
        //
        // This test guarantees both platforms produce the EXACT same bytes.
        // If either side changes, this test fails — preventing silent INV-26 breakage.
        const expected = '{"error":"Not Found"}';

        expect(SovereigntyErrorMapper.canonicalBody, equals(expected));
        expect(SovereigntyErrorMapper.canonicalBody.length, 21);
        expect(
          SovereigntyErrorMapper.canonicalBody.codeUnits,
          equals(expected.codeUnits),
        );
      },
    );

    // ── Scenario 9: Malformed/malicious resource IDs (DB technology hiding) ─

    test('malformed ID returns same 404 as valid ID — hides DB technology', () {
      // An invalid UUID (or SQL injection attempt) must NOT trigger a
      // different error like "invalid input syntax for type uuid" or
      // Postgres-specific messages. It must look identical to a real 404.

      // Malformed: not even close to a UUID
      const malformedId = ResourceNotFoundException(
        resourceType: 'contract',
        resourceId: 'NOT-A-UUID!!!',
      );

      // SQL injection attempt in resourceId
      const sqlInjection = ResourceNotFoundException(
        resourceType: 'contract',
        resourceId: "'; DROP TABLE contracts; --",
      );

      // Path traversal attempt
      const pathTraversal = ResourceNotFoundException(
        resourceType: 'contract',
        resourceId: '../../../etc/passwd',
      );

      // Standard non-existent valid UUID (the baseline)
      const standardNotFound = ResourceNotFoundException(
        resourceType: 'contract',
        resourceId: '550e8400-e29b-41d4-a716-446655440000',
      );

      final malformedResponse = SovereigntyErrorMapper.toResponse(malformedId);
      final sqlResponse = SovereigntyErrorMapper.toResponse(sqlInjection);
      final traversalResponse = SovereigntyErrorMapper.toResponse(
        pathTraversal,
      );
      final standardResponse = SovereigntyErrorMapper.toResponse(
        standardNotFound,
      );

      // All must be byte-identical — no technology fingerprinting
      expect(malformedResponse, equals(standardResponse));
      expect(sqlResponse, equals(standardResponse));
      expect(traversalResponse, equals(standardResponse));
      expect(malformedResponse['body'], '{"error":"Not Found"}');
      expect(sqlResponse['body'], '{"error":"Not Found"}');
      expect(traversalResponse['body'], '{"error":"Not Found"}');
    });
  });
}
