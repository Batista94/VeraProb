// Security boundary tests for PostgresContractRepository.
//
// Forensic Insight -- Skill: QA & Security Lead (Paranoid Protector)
// Invariants under scrutiny:
//   INV-1  (Identity Sovereignty): all queries filtered by organization_id
//   INV-2  (RLS Hardening): 42501 must surface as SovereigntyViolationException
//   INV-3  (Ledger Integrity): organization_id must never appear in UPDATE payload
//   INV-8  (Repo Isolation): repository enforces org_id on ALL read/write ops
//   INV-22 (Multi-Tenancy): Tenant-A must NEVER see Tenant-B data
//   INV-26 (Error Parity): 42501 -> SovereigntyViolationException, not raw PostgrestException
//   INV-27 (Origin Ownership): organization_id is set at creation, immutable thereafter
//
// ALL tests use MockClient -- no real Supabase instance required.
// TDD RED tests (SEC-4, SEC-5) will FAIL against the current implementation.
// That is intentional -- they document invariant violations to be fixed.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contract_repository.dart';

import '../postgres/postgres_test_config.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns a fully-populated DB row map.
/// All 9 required fields are present so assertFields() passes without throwing.
Map<String, dynamic> _validRowMap({
  String id = 'contract-sec-1',
  String organizationId = 'org-a',
}) => {
  'id': id,
  'organization_id': organizationId,
  'name': 'Security Test Contract',
  'contractor_name': 'Adversary LTDA',
  'description': null,
  'valid_from_utc': '2024-01-01T00:00:00Z',
  'valid_until_utc': '2025-01-01T00:00:00Z',
  'status': 'draft',
  'created_at_utc': '2024-01-01T00:00:00Z',
  'penalty_multiplier': 1.0,
  'activated_at_utc': null,
  'closed_at_utc': null,
  'closed_by_user_id': null,
  'close_reason': null,
  'submitted_for_approval_at_utc': null,
  'cloned_from_contract_id': null,
  'financial_ceiling_cents': null,
  'latitude': null,
  'longitude': null,
  'version': 1,
  'previous_hash': null,
  'current_hash': null,
};

/// Builds a Contract aggregate with sane defaults.
Contract _buildContract({
  required String id,
  required String organizationId,
  int version = 1,
  ContractStatus status = ContractStatus.draft,
}) {
  return Contract.reconstitute(
    id: id,
    version: version,
    organizationId: organizationId,
    name: 'Security Contract',
    contractorName: 'Contractor LTDA',
    description: 'Security test',
    validFromUtc: DateTime.utc(2024, 1, 1),
    validUntilUtc: DateTime.utc(2025, 1, 1),
    status: status,
    createdAtUtc: DateTime.utc(2024, 1, 1),
    penaltyMultiplierBps: 10000,
  );
}

/// Creates a [PostgresContractRepository] backed by a [MockClient].
/// Uses the direct SupabaseClient constructor to avoid singleton conflicts
/// with [Supabase.initialize] which is a global singleton.
PostgresContractRepository _repoWithMock(
  Future<http.Response> Function(http.Request request) handler,
) {
  final supabaseClient = SupabaseClient(
    PostgresTestConfig.supabaseUrl,
    PostgresTestConfig.serviceRoleKey,
    httpClient: MockClient(handler),
  );
  return PostgresContractRepository(supabaseClient);
}

// ---------------------------------------------------------------------------
// Security Test Suite
// ---------------------------------------------------------------------------

void main() {
  // SEC-1 ------------------------------------------------------------------
  group('SEC-1: Impersonation Attack', () {
    // Exploit Path: Adversary calls findById(contractId, organizationId: orgB)
    // hoping the repository omits the organization_id filter from the HTTP URL.
    // If the filter is absent, Supabase RLS is the only gate -- a single RLS
    // misconfiguration or service-role key leak exposes all contracts.
    //
    // Closing mechanism: The repository hardcodes
    //   .eq('organization_id', organizationId)
    // in the query chain. The filter appears at the wire level in the HTTP URL.
    // The adversary orgB ID produces a filter against orgB rows only --
    // orgA data is structurally unreachable regardless of RLS configuration.

    test(
      'SEC-1a: findById URL contains organization_id=eq.orgA (Forensic Chain Tracking)',
      () async {
        const contractId = 'contract-sec-1a';
        const orgA = 'org-a-legitimate';
        String? capturedUrl;

        final repo = _repoWithMock((request) async {
          capturedUrl = request.url.toString();
          // maybeSingle() -- return JSON null (no row found)
          return http.Response(
            'null',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        await repo.findById(contractId, organizationId: orgA);

        expect(
          capturedUrl,
          contains('organization_id=eq.$orgA'),
          reason:
              'INV-1/INV-22: The wire-level query MUST include '
              'organization_id=eq.orgA to prevent cross-tenant data access '
              'at the database layer, independent of RLS configuration.',
        );
        expect(
          capturedUrl,
          contains('id=eq.$contractId'),
          reason: 'Primary key filter must also be present in the URL.',
        );
      },
    );

    test(
      'SEC-1b: findById with orgB ID returns null when contract belongs to orgA',
      () async {
        // Mock returns null -- same as real DB when org filter excludes the row.
        final repo = _repoWithMock((request) async {
          return http.Response(
            'null',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        final result = await repo.findById(
          'contract-sec-1b',
          organizationId: 'org-b-adversary',
        );

        expect(
          result,
          isNull,
          reason:
              'INV-22/INV-26: Passing orgB ID to findById must return null. '
              'No data inference possible (Oracle Attack prevention).',
        );
      },
    );

    test(
      'SEC-1c: findById with orgA returns entity with organizationId == orgA',
      () async {
        const contractId = 'contract-sec-1c';
        const orgA = 'org-a-legitimate';

        final repo = _repoWithMock((request) async {
          // maybeSingle() deserialises a single JSON object (not an array)
          return http.Response(
            jsonEncode(_validRowMap(id: contractId, organizationId: orgA)),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        final result = await repo.findById(contractId, organizationId: orgA);

        expect(result, isNotNull);
        expect(
          result!.organizationId,
          equals(orgA),
          reason:
              'INV-1: The returned entity must carry the legitimate orgA ID '
              'unchanged from the database row.',
        );
      },
    );

    test(
      'SEC-1d: findByOrganization URL contains organization_id=eq.orgB (wire filter proof)',
      () async {
        const orgB = 'org-b-adversary';
        String? capturedUrl;

        final repo = _repoWithMock((request) async {
          capturedUrl = request.url.toString();
          // orgB has no contracts -- empty array
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        final results = await repo.findByOrganization(orgB);

        expect(
          results,
          isEmpty,
          reason: 'INV-22: orgB adversary receives empty list, not orgA data.',
        );
        expect(
          capturedUrl,
          contains('organization_id=eq.$orgB'),
          reason:
              'INV-1: The .eq(organization_id, orgB) filter must appear in '
              'the wire-level URL -- proving isolation is applied in the query '
              'itself, not just trusted from the empty result.',
        );
      },
    );
  });

  // SEC-2 ------------------------------------------------------------------
  group('SEC-2: Metadata Tampering Guard', () {
    // Exploit Path: Attacker intercepts the DTO-to-domain mapping and injects
    // a different organization_id before the INSERT reaches the DB.
    //
    // Closing mechanism: Contract is an immutable aggregate.
    // organizationId is a final field set only at Contract.create/reconstitute.
    // The repository exclusively reads from contract.organizationId; there is
    // no code path that accepts an external org_id override on INSERT.
    // Defense-in-Depth: the application layer MUST validate JWT org_id matches
    // contract.organizationId before calling repository.save() (INV-1).

    test(
      'SEC-2a: INSERT POST body organization_id equals contract.organizationId (wire verification)',
      () async {
        const orgLegit = 'org-a-legit';
        const contractId = 'contract-sec-2a';
        Map<String, dynamic>? capturedBody;

        final repo = _repoWithMock((request) async {
          if (request.method == 'POST') {
            capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          }
          // _create uses INSERT with no .select() chain -- empty body / 201 correct
          return http.Response(
            '',
            201,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        final contract = _buildContract(
          id: contractId,
          organizationId: orgLegit,
          version: 1, // version == 1 triggers _create path
        );

        await repo.save(contract);

        expect(
          capturedBody,
          isNotNull,
          reason: 'MockClient must have captured a POST request body.',
        );
        expect(
          capturedBody!['organization_id'],
          equals(orgLegit),
          reason:
              'INV-1/INV-8: The INSERT payload must contain the domain '
              'aggregate organizationId, not any externally supplied value.',
        );
      },
    );

    test(
      'SEC-2b: Contract immutability closes the tamper path -- no external org_id override exists',
      () async {
        // Documents why external tampering is impossible at the repository layer:
        // Contract.organizationId is final. The defence against a subverted
        // Contract construction is at the application layer (JWT org_id check).
        const orgTamper = 'org-b-tamper';
        Map<String, dynamic>? capturedBody;

        final repo = _repoWithMock((request) async {
          if (request.method == 'POST') {
            capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          }
          return http.Response(
            '',
            201,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        final tamperedContract = _buildContract(
          id: 'contract-sec-2b',
          organizationId: orgTamper,
          version: 1,
        );

        await repo.save(tamperedContract);

        // The repository transparently serializes contract.organizationId.
        // There is NO secondary override mechanism inside the repository.
        expect(
          capturedBody!['organization_id'],
          equals(orgTamper),
          reason:
              'Repository faithfully serializes contract.organizationId. '
              'No secondary override exists inside the repo. '
              'The exploit gate is the application-layer JWT check (INV-1).',
        );
      },
    );
  });

  // SEC-3 ------------------------------------------------------------------
  group('SEC-3: Realtime Leak Guard (N/A)', () {
    test(
      'Realtime subscriptions not implemented -- no leak surface',
      () {},
      skip: 'No realtime API in PostgresContractRepository',
    );
  });

  // SEC-4 ------------------------------------------------------------------
  group('SEC-4: Immutability Breach -- org_id in UPDATE', () {
    // Exploit Path: If organization_id appears in a PATCH payload, a race
    // condition or compromised DB trigger could reassign a contract to a
    // different tenant mid-flight. Ownership is established at INSERT and
    // must be immutable thereafter.
    //
    // INV-3 (Ledger Integrity): ownership must never mutate post-insert.
    // INV-27 (Origin Ownership): source ownership is immutable.
    //
    // TDD RED PHASE: The current _update() method includes
    //   'organization_id': contract.organizationId
    // in the PATCH data map (postgres_contract_repository.dart ~line 137).
    // This test WILL FAIL until that line is removed.
    //
    // Remediation: Remove 'organization_id' from the data{} map in _update().
    // The RLS policy and .eq('id', id).eq('version', currentVersion)
    // filter already constrain the update to the correct row.

    test(
      // TDD: RED -- INV-27 violation in current impl
      'SEC-4: PATCH body must NOT contain organization_id (immutable ownership)',
      () async {
        const contractId = 'contract-sec-4';
        const orgA = 'org-a-owner';
        Map<String, dynamic>? patchBody;

        final repo = _repoWithMock((request) async {
          if (request.method == 'PATCH') {
            patchBody = jsonDecode(request.body) as Map<String, dynamic>;
            // maybeSingle() on .select('id, version') expects a single JSON object
            return http.Response(
              jsonEncode({'id': contractId, 'version': 2}),
              200,
              headers: {
                'content-type': 'application/json',
                'Prefer': 'return=representation',
              },
              request: request,
            );
          }
          // Fallback for the secondary SELECT (conflict discriminator path)
          return http.Response(
            'null',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        final contract = _buildContract(
          id: contractId,
          organizationId: orgA,
          version: 2, // version > 1 triggers _update path
        );

        await repo.save(contract);

        expect(
          patchBody,
          isNotNull,
          reason: 'MockClient must have captured a PATCH request body.',
        );

        // TDD: RED -- CURRENTLY FAILS because _update() sends
        // 'organization_id': contract.organizationId in the data map.
        // Fix: remove that key from the data{} literal in _update().
        expect(
          patchBody,
          isNot(contains('organization_id')),
          reason:
              'INV-3/INV-27: organization_id must never appear in UPDATE '
              'payload -- ownership is immutable. Remove it from the _update() '
              'data map in postgres_contract_repository.dart.',
        );
      },
    );
  });

  // SEC-5 ------------------------------------------------------------------
  group('SEC-5: 42501 Privilege Denial -> SovereigntyViolation', () {
    // Exploit Path: When Supabase/Postgres RLS denies access (42501 --
    // insufficient_privilege), the raw PostgrestException surfaces to the
    // caller. A caller catching Exception can introspect e.code == '42501'
    // and infer that the tenant exists but was blocked -- Oracle Attack (INV-26).
    //
    // Closing mechanism: mapPostgrestToDomainException must match '42501'
    // and throw SovereigntyViolationException, stripping DB code from the caller.
    //
    // TDD RED PHASE: postgres_error_interceptor.dart switch has no '42501'
    // arm. It falls through to '_ => throw e' (raw PostgrestException rethrow).
    // This test WILL FAIL until the arm is added:
    //
    //   '42501' => SovereigntyViolationException(
    //       payloadOrgId: resourceId ?? '',
    //       jwtOrgId: '',
    //       message: 'RLS policy denied access (42501 insufficient_privilege)',
    //     ),

    test(
      // TDD: RED -- 42501 not mapped to SovereigntyViolationException
      'SEC-5: Supabase 403/42501 -> SovereigntyViolationException (not raw PostgrestException)',
      () async {
        const orgX = 'org-x-rls-blocked';

        final repo = _repoWithMock((request) async {
          return http.Response(
            jsonEncode({
              'code': '42501',
              'message': 'insufficient_privilege',
              'details': null,
              'hint': null,
            }),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        });

        // TDD: RED -- currently throws raw PostgrestException (code 42501)
        // because mapPostgrestToDomainException has no '42501' arm.
        await expectLater(
          () => repo.findByOrganization(orgX),
          throwsA(isA<SovereigntyViolationException>()),
          reason:
              'INV-2/INV-26: PostgrestException code 42501 (RLS denied) must '
              'be mapped to SovereigntyViolationException -- never leak raw DB '
              'error codes. Add a 42501 arm to mapPostgrestToDomainException() '
              'in postgres_error_interceptor.dart.',
        );
      },
    );
  });
}
