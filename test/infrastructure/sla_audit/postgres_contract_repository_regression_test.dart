// Regression + adversarial + CIA triad infrastructure tests for PostgresContractRepository.
//
// Skill Insight — QA & Security Lead (Paranoid Protector)
// Invariants guarded:
//   INV-3  (Ledger Integrity): INSERT must not include version/hashes; PATCH omits org_id.
//   INV-5  (Rounding): penalty_multiplier = bps / 10000.0.
//   INV-9  (SHA-256 Seal): hashes are DB-managed, never written by application.
//   INV-10 (Typed Exceptions): DB error codes → typed domain exceptions, never raw PostgrestException.
//   INV-18 (Zero-Trust Telemetry): assertFields + parseUtc enforce schema at ingest boundary.
//   INV-26 (Error Parity): error mapping hides raw DB codes (Anti-Oracle).
//   INV-27 (Origin Ownership): organization_id immutable post-INSERT.
//
// CT04 regression guard (REG-1/REG-4):
//   Before fix: Contract.create() returned version=1. Handler loaded saved contract
//   (version=1), called activate() (preserved version=1), then save() dispatched to
//   _create() (INSERT) → duplicate PK on 'contracts'.
//   REG-1 + REG-4 lock in the correct POST→PATCH dispatch sequence.
//
// CIA triad coverage:
//   Confidentiality — tenant isolation at wire level: covered by SEC-1a/SEC-1b/SEC-1d
//                     in postgres_contract_repository_security_test.dart.
//   Integrity       — CIA-I group: payload correctness (no version, no hashes, formula).
//   Availability    — CIA-A group: error-code mapping to typed exceptions (no raw crashes).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contract_repository.dart';

import '../postgres/postgres_test_config.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Map<String, dynamic> _validRowMap({String organizationId = 'org-1'}) => {
  'id': 'contract-reg-1',
  'organization_id': organizationId,
  'name': 'Contrato Regressão',
  'contractor_name': 'Empresa LTDA',
  'description': null,
  'valid_from_utc': '2026-01-01T00:00:00Z',
  'valid_until_utc': '2026-12-31T00:00:00Z',
  'status': 'draft',
  'created_at_utc': '2026-01-01T00:00:00Z',
  'penalty_multiplier': 1.0,
  'version': 1,
  'activated_at_utc': null,
  'closed_at_utc': null,
  'closed_by_user_id': null,
  'close_reason': null,
  'submitted_for_approval_at_utc': null,
  'cloned_from_contract_id': null,
  'financial_ceiling_cents': null,
  'latitude': null,
  'longitude': null,
  'previous_hash': null,
  'current_hash': null,
};

/// New aggregate — version=0 sentinel. save() must dispatch to INSERT (POST).
Contract _newContract({int penaltyMultiplierBps = 10000}) => Contract.create(
  organizationId: 'org-1',
  name: 'Contrato Novo',
  contractorName: 'Empresa LTDA',
  validFromUtc: DateTime.utc(2026, 1, 1),
  validUntilUtc: DateTime.utc(2026, 12, 31),
  nowUtc: DateTime.utc(2026, 6, 6),
  penaltyMultiplierBps: penaltyMultiplierBps,
);

/// Loaded aggregate — version >= 1. save() must dispatch to UPDATE (PATCH).
Contract _persistedContract({
  String id = 'contract-persisted-1',
  int version = 1,
  ContractStatus status = ContractStatus.draft,
  int penaltyMultiplierBps = 10000,
}) => Contract.reconstitute(
  id: id,
  version: version,
  organizationId: 'org-1',
  name: 'Contrato Persistido',
  contractorName: 'Empresa LTDA',
  validFromUtc: DateTime.utc(2026, 1, 1),
  validUntilUtc: DateTime.utc(2026, 12, 31),
  status: status,
  createdAtUtc: DateTime.utc(2026, 1, 1),
  penaltyMultiplierBps: penaltyMultiplierBps,
);

PostgresContractRepository _repoWithMock(
  Future<http.Response> Function(http.Request) handler,
) {
  final supabaseClient = SupabaseClient(
    PostgresTestConfig.supabaseUrl,
    PostgresTestConfig.serviceRoleKey,
    httpClient: MockClient(handler),
  );
  return PostgresContractRepository(supabaseClient);
}

http.Response _jsonResponse(Object? body, int status, http.Request request) {
  return http.Response(
    body == null ? 'null' : jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
    request: request,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── REG: Version sentinel → HTTP verb dispatch ───────────────────────────

  group('REG: version sentinel dispatches correct HTTP verb (CT04 regression lock)', () {
    test('REG-1: save(version=0) sends POST, not PATCH', () async {
      String? capturedMethod;
      final repo = _repoWithMock((req) async {
        capturedMethod = req.method;
        return _jsonResponse(null, 201, req);
      });

      await repo.save(_newContract());

      expect(
        capturedMethod,
        'POST',
        reason:
            'CT04 regression: version=0 sentinel must dispatch to INSERT (POST). '
            'Any other verb re-introduces the duplicate-key bug.',
      );
    });

    test('REG-2: save(version=1) sends PATCH, not POST', () async {
      const id = 'contract-reg-2';
      String? capturedMethod;
      final repo = _repoWithMock((req) async {
        capturedMethod = req.method;
        return _jsonResponse({'id': id, 'version': 2}, 200, req);
      });

      await repo.save(_persistedContract(id: id, version: 1));

      expect(
        capturedMethod,
        'PATCH',
        reason:
            'version=1 must dispatch to UPDATE (PATCH). '
            'If POST fires here, the next save() also POSTs → duplicate key.',
      );
    });

    test(
      'REG-3: save(version=0) returns reconstituted entity with version=1',
      () async {
        final repo = _repoWithMock(
          (req) async => _jsonResponse(null, 201, req),
        );

        final saved = await repo.save(_newContract());

        expect(
          saved.version,
          1,
          reason:
              'Post-INSERT reconstitution must carry version=1 so callers '
              'route to PATCH on the next save(), not INSERT again.',
        );
      },
    );

    test(
      'REG-4: full CT04 lifecycle — v0→POST returns v1, activate, save(v1)→PATCH, '
      'never double-INSERT',
      () async {
        final List<String> capturedMethods = [];
        final repo = _repoWithMock((req) async {
          capturedMethods.add(req.method);
          if (req.method == 'POST') {
            return _jsonResponse(null, 201, req);
          }
          // PATCH returns new version from DB trigger.
          return _jsonResponse({'id': 'any-id', 'version': 2}, 200, req);
        });

        // Step 1: persist new contract → POST
        final savedOnce = await repo.save(_newContract());

        // Step 2: business transition on returned v1 entity
        final activated = savedOnce.activate(nowUtc: DateTime.utc(2026, 6, 6));

        // Step 3: persist activated state → must PATCH, not INSERT
        await repo.save(activated);

        expect(
          capturedMethods,
          ['POST', 'PATCH'],
          reason:
              'CT04: correct lifecycle is POST then PATCH. '
              'POST+POST = duplicate key. PATCH+PATCH on version=0 = missed INSERT.',
        );
      },
    );

    test(
      'REG-5: createClone() at version=0 → save dispatches POST (INSERT path)',
      () async {
        String? capturedMethod;
        final repo = _repoWithMock((req) async {
          capturedMethod = req.method;
          return _jsonResponse(null, 201, req);
        });

        final clone = Contract.createClone(
          organizationId: 'org-1',
          name: 'Clone Contrato',
          contractorName: 'Empresa LTDA',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
          clonedFromContractId: 'source-id-abc',
          nowUtc: DateTime.utc(2026, 6, 6),
        );
        await repo.save(clone);

        expect(
          capturedMethod,
          'POST',
          reason:
              'Cloned contracts are new aggregates (version=0) and must INSERT, '
              'never UPDATE an existing row.',
        );
      },
    );
  });

  // ── ADV: Adversarial DB response mapping ─────────────────────────────────

  group('ADV: Adversarial DB response mapping', () {
    test(
      'ADV-1: findById — row missing required field → IntegrityException',
      () async {
        final badRow = Map<String, dynamic>.from(_validRowMap())
          ..remove('status');
        final repo = _repoWithMock(
          (req) async => _jsonResponse(badRow, 200, req),
        );

        await expectLater(
          () => repo.findById('contract-reg-1', organizationId: 'org-1'),
          throwsA(isA<IntegrityException>()),
          reason:
              'INV-18: absent required field must throw IntegrityException, '
              'not a null-dereference crash.',
        );
      },
    );

    test(
      'ADV-2: findById — null required timestamp → IntegrityException',
      () async {
        final badRow = Map<String, dynamic>.from(_validRowMap())
          ..['valid_from_utc'] = null;
        final repo = _repoWithMock(
          (req) async => _jsonResponse(badRow, 200, req),
        );

        await expectLater(
          () => repo.findById('contract-reg-1', organizationId: 'org-1'),
          throwsA(isA<IntegrityException>()),
          reason: 'INV-6/INV-18: null timestamp must throw IntegrityException.',
        );
      },
    );

    test(
      'ADV-3: findById — non-String timestamp (epoch int) → IntegrityException',
      () async {
        final badRow = Map<String, dynamic>.from(_validRowMap())
          ..['valid_from_utc'] = 1735689600; // int instead of ISO-8601 string
        final repo = _repoWithMock(
          (req) async => _jsonResponse(badRow, 200, req),
        );

        await expectLater(
          () => repo.findById('contract-reg-1', organizationId: 'org-1'),
          throwsA(isA<IntegrityException>()),
          reason:
              'INV-6/INV-18: non-String timestamp must throw IntegrityException. '
              'A silent int-parse would produce an incorrect UTC DateTime.',
        );
      },
    );

    test(
      'ADV-4: findById — unknown enum status → IntegrityException',
      () async {
        final badRow = Map<String, dynamic>.from(_validRowMap())
          ..['status'] = 'totally_unknown_status';
        final repo = _repoWithMock(
          (req) async => _jsonResponse(badRow, 200, req),
        );

        await expectLater(
          () => repo.findById('contract-reg-1', organizationId: 'org-1'),
          throwsA(isA<IntegrityException>()),
          reason:
              'INV-10: unknown enum must throw IntegrityException via '
              'IntegrityException.shield(), not ArgumentError.',
        );
      },
    );

    test(
      'ADV-5: PATCH version mismatch (stale) → ConflictException isDeleted=false',
      () async {
        const id = 'contract-adv-5';
        final repo = _repoWithMock((req) async {
          if (req.method == 'PATCH') {
            // Zero rows matched — another writer bumped the version concurrently.
            return _jsonResponse(null, 200, req);
          }
          // Discriminator GET: row exists at a higher version.
          return _jsonResponse({'id': id, 'version': 5}, 200, req);
        });

        await expectLater(
          () => repo.save(_persistedContract(id: id, version: 1)),
          throwsA(
            isA<ConflictException>().having(
              (e) => e.isDeleted,
              'isDeleted',
              isFalse,
            ),
          ),
          reason:
              'Stale optimistic lock: PATCH matched nothing, GET found v5. '
              'Must be ConflictException.staleVersion (isDeleted=false).',
        );
      },
    );

    test(
      'ADV-6: PATCH then row gone → ConflictException isDeleted=true',
      () async {
        const id = 'contract-adv-6';
        final repo = _repoWithMock((req) async {
          // Both PATCH and discriminator GET return null.
          return _jsonResponse(null, 200, req);
        });

        await expectLater(
          () => repo.save(_persistedContract(id: id, version: 1)),
          throwsA(
            isA<ConflictException>().having(
              (e) => e.isDeleted,
              'isDeleted',
              isTrue,
            ),
          ),
          reason:
              'Deleted resource: PATCH matched nothing and GET also null. '
              'Must be ConflictException.deleted (isDeleted=true).',
        );
      },
    );
  });

  // ── CIA-I: Integrity — INSERT/PATCH payload correctness ──────────────────

  group('CIA-I: INSERT payload must not contain version or forensic hashes', () {
    // INV-3: version is managed by DB DEFAULT + UPDATE trigger. Client must not
    // send it — doing so could override the DEFAULT or conflict with the trigger.
    // INV-9: SHA-256 hashes are computed by the DB seal layer after ingest.
    // Writing them from the application layer would break the forensic chain.

    test('CIA-I1: INSERT POST body has no "version" key', () async {
      Map<String, dynamic>? capturedBody;
      final repo = _repoWithMock((req) async {
        if (req.method == 'POST') {
          capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
        }
        return _jsonResponse(null, 201, req);
      });

      await repo.save(_newContract());

      expect(
        capturedBody,
        isNot(contains('version')),
        reason:
            'INV-3: version is assigned by the DB (DEFAULT=1, trigger on UPDATE). '
            'Client-supplied version on INSERT could corrupt the sequence.',
      );
    });

    test(
      'CIA-I2: INSERT POST body has no "previous_hash" or "current_hash"',
      () async {
        Map<String, dynamic>? capturedBody;
        final repo = _repoWithMock((req) async {
          if (req.method == 'POST') {
            capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
          }
          return _jsonResponse(null, 201, req);
        });

        await repo.save(_newContract());

        expect(capturedBody, isNot(contains('previous_hash')));
        expect(
          capturedBody,
          isNot(contains('current_hash')),
          reason:
              'INV-9: forensic hashes are DB-managed. '
              'Application writing them directly breaks the SHA-256 chain.',
        );
      },
    );

    test(
      'CIA-I3: INSERT penalty_multiplier = penaltyMultiplierBps / 10000.0',
      () async {
        Map<String, dynamic>? capturedBody;
        final repo = _repoWithMock((req) async {
          if (req.method == 'POST') {
            capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
          }
          return _jsonResponse(null, 201, req);
        });

        await repo.save(_newContract(penaltyMultiplierBps: 15000));

        expect(
          capturedBody!['penalty_multiplier'],
          closeTo(1.5, 0.0001),
          reason:
              'INV-5: penalty_multiplier = bps / 10000.0. '
              'Wrong formula corrupts all financial penalty verdicts.',
        );
      },
    );

    test(
      'CIA-I4: PATCH payload has no "organization_id" (ownership immutable)',
      () async {
        const id = 'contract-cia-i4';
        Map<String, dynamic>? patchBody;
        final repo = _repoWithMock((req) async {
          if (req.method == 'PATCH') {
            patchBody = jsonDecode(req.body) as Map<String, dynamic>;
            return _jsonResponse({'id': id, 'version': 2}, 200, req);
          }
          return _jsonResponse(null, 200, req);
        });

        await repo.save(_persistedContract(id: id, version: 1));

        expect(
          patchBody,
          isNot(contains('organization_id')),
          reason:
              'INV-3/INV-27: organization_id is immutable after INSERT. '
              'Including it in PATCH opens a tenant-reassignment race condition.',
        );
      },
    );
  });

  // ── CIA-A: Availability — typed exception mapping ─────────────────────────

  group(
    'CIA-A: DB error codes → typed domain exceptions (no raw PostgrestException)',
    () {
      // INV-10 + INV-26: callers rely on typed exceptions for error handling.
      // Raw PostgrestException leaks DB constraint names and error codes to the UI
      // layer, enabling Oracle Attacks and causing unhandled exception crashes.

      test('CIA-A1: 23505 unique violation on INSERT → IntegrityException', () async {
        final repo = _repoWithMock((req) async {
          return http.Response(
            jsonEncode({
              'code': '23505',
              'message':
                  'duplicate key value violates unique constraint "contracts_pkey"',
              'details': null,
              'hint': null,
            }),
            409,
            headers: {'content-type': 'application/json'},
            request: req,
          );
        });

        await expectLater(
          () => repo.save(_newContract()),
          throwsA(isA<IntegrityException>()),
          reason:
              'INV-10/INV-26: 23505 (duplicate key) must map to IntegrityException. '
              'Raw PostgrestException leaks constraint names and enables Oracle Attacks.',
        );
      });

      test(
        'CIA-A2: P0001 DB trigger RAISE on INSERT → IntegrityException',
        () async {
          final repo = _repoWithMock((req) async {
            return http.Response(
              jsonEncode({
                'code': 'P0001',
                'message': 'integrity violation raised by DB trigger',
                'details': null,
                'hint': null,
              }),
              400,
              headers: {'content-type': 'application/json'},
              request: req,
            );
          });

          await expectLater(
            () => repo.save(_newContract()),
            throwsA(isA<IntegrityException>()),
            reason:
                'INV-10: P0001 (DB RAISE EXCEPTION) must surface as IntegrityException, '
                'not raw PostgrestException.',
          );
        },
      );

      test(
        'CIA-A3: 22P02 invalid UUID input on findById → ResourceNotFoundException',
        () async {
          final repo = _repoWithMock((req) async {
            return http.Response(
              jsonEncode({
                'code': '22P02',
                'message': 'invalid input syntax for type uuid: "not-a-uuid"',
                'details': null,
                'hint': null,
              }),
              400,
              headers: {'content-type': 'application/json'},
              request: req,
            );
          });

          await expectLater(
            () => repo.findById('not-a-uuid', organizationId: 'org-1'),
            throwsA(isA<ResourceNotFoundException>()),
            reason:
                'INV-26: 22P02 (invalid UUID) must map to ResourceNotFoundException. '
                'Leaking a distinct "bad input" exception reveals schema structure.',
          );
        },
      );
    },
  );
}
