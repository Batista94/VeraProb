import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contract_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../postgres/postgres_test_config.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _requiredFields = [
  'id',
  'organization_id',
  'name',
  'contractor_name',
  'valid_from_utc',
  'valid_until_utc',
  'status',
  'created_at_utc',
  'penalty_multiplier',
];

Map<String, dynamic> _validRow() => {
  'id': 'c-1',
  'organization_id': 'org-1',
  'name': 'Test Contract',
  'contractor_name': 'ACME Transportes',
  'valid_from_utc': '2024-01-01T00:00:00Z',
  'valid_until_utc': '2025-01-01T00:00:00Z',
  'status': 'draft',
  'created_at_utc': '2024-01-01T00:00:00Z',
  'penalty_multiplier': 1.0,
};

Contract _buildContract({
  required String id,
  required String organizationId,
  Money? financialCeiling,
  int penaltyMultiplierBps = 10000,
  double? latitude,
  double? longitude,
}) {
  return Contract.reconstitute(
    id: id,
    organizationId: organizationId,
    name: 'Contract $id',
    contractorName: 'Contractor LTDA',
    description: 'Integration test contract',
    validFromUtc: DateTime.utc(2024, 1, 1),
    validUntilUtc: DateTime.utc(2025, 1, 1),
    status: ContractStatus.draft,
    createdAtUtc: DateTime.now().toUtc(),
    financialCeiling: financialCeiling,
    penaltyMultiplierBps: penaltyMultiplierBps,
    latitude: latitude,
    longitude: longitude,
  );
}

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  // -------------------------------------------------------------------------
  // Grupo A — Unit: _assertFields (INV-18) — sem banco de dados
  // -------------------------------------------------------------------------
  group('Unit: _assertFields — schema assertion (INV-18)', () {
    // ignore: invalid_use_of_visible_for_testing_member
    final repo = PostgresContractRepository(_MockSupabaseClient());

    for (final field in _requiredFields) {
      test('T04.$field: campo ausente lança IntegrityException', () {
        final row = _validRow()..remove(field);
        expect(
          // ignore: invalid_use_of_visible_for_testing_member
          () => repo.internalAssertFields(row),
          throwsA(
            isA<IntegrityException>().having((e) => e.field, 'field', field),
          ),
        );
      });

      test('T04.$field: campo nulo lança IntegrityException', () {
        final row = _validRow()..[field] = null;
        expect(
          // ignore: invalid_use_of_visible_for_testing_member
          () => repo.internalAssertFields(row),
          throwsA(
            isA<IntegrityException>().having((e) => e.field, 'field', field),
          ),
        );
      });
    }

    test('T04.valid: row completa não lança exceção', () {
      // ignore: invalid_use_of_visible_for_testing_member
      expect(() => repo.internalAssertFields(_validRow()), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // Grupo B — Unit: _parseUtc — UTC enforcement (INV-9) — sem banco de dados
  // -------------------------------------------------------------------------
  group('Unit: _parseUtc — UTC enforcement (INV-9)', () {
    // ignore: invalid_use_of_visible_for_testing_member
    final repo = PostgresContractRepository(_MockSupabaseClient());

    test('T05._parseUtc: null lança IntegrityException', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        () => repo.internalParseUtc(null, 'valid_from_utc'),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.field,
            'field',
            'valid_from_utc',
          ),
        ),
      );
    });

    test('T05._parseUtc: tipo int lança IntegrityException', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        () => repo.internalParseUtc(42, 'valid_from_utc'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('T05._parseUtc: string naive (sem Z) → DateTime UTC (INV-9)', () {
      // ignore: invalid_use_of_visible_for_testing_member
      final result = repo.internalParseUtc(
        '2024-06-15T12:30:00',
        'valid_from_utc',
      );
      expect(result.isUtc, isTrue);
      expect(result.hour, 12);
    });

    test('T05._parseUtc: string com Z já presente → DateTime UTC', () {
      // ignore: invalid_use_of_visible_for_testing_member
      final result = repo.internalParseUtc(
        '2024-06-15T12:30:00Z',
        'valid_from_utc',
      );
      expect(result.isUtc, isTrue);
      expect(result.hour, 12);
    });
  });

  // -------------------------------------------------------------------------
  // Grupo C — Integration: Suíte Forense T01-T06 (INV-1 / INV-9 / INV-18 / INV-19)
  // -------------------------------------------------------------------------
  group(
    'Suíte Forense — Contract Repository Postgres (INV-1 / INV-9 / INV-18 / INV-19)',
    () {
      late SupabaseClient client;
      late PostgresContractRepository repository;
      const uuid = Uuid();

      setUpAll(() async {
        if (isRunning) {
          client = await PostgresTestConfig.createClient();
          await PostgresTestConfig.ensureSentinelOrg(client: client);
          repository = PostgresContractRepository(client);
        }
      });

      // T01 — Happy Path: save + findById retorna entidade completa
      test(
        'T01: save + findById retorna contrato com todos os campos (Happy Path)',
        () async {
          final id = uuid.v4();
          final contract = _buildContract(
            id: id,
            organizationId: PostgresTestConfig.testOrgId,
            financialCeiling: const Money(150000),
            penaltyMultiplierBps: 12500, // 1.25x
            latitude: -23.5505,
            longitude: -46.6333,
          );

          await repository.save(contract);

          final found = await repository.findById(
            id,
            organizationId: PostgresTestConfig.testOrgId,
          );

          expect(found, isNotNull);
          expect(found!.id, id);
          expect(found.organizationId, PostgresTestConfig.testOrgId);
          expect(found.name, contract.name);
          expect(found.contractorName, contract.contractorName);
          expect(found.status, ContractStatus.draft);
          expect(found.penaltyMultiplierBps, 12500);
          expect(found.latitude, -23.5505);
          expect(found.longitude, -46.6333);
          expect(found.financialCeiling, const Money(150000));
          expect(found.createdAtUtc.isUtc, isTrue);
        },
      );

      // T02 — INV-1: findById com org diferente deve retornar null
      test(
        'T02 (INV-1): findById com organizationId de outro tenant retorna null',
        () async {
          final id = uuid.v4();
          final adversaryOrgId = uuid.v4();

          final contract = _buildContract(
            id: id,
            organizationId: PostgresTestConfig.testOrgId,
          );

          await repository.save(contract);

          // Tenant legítimo encontra o contrato.
          final legitimate = await repository.findById(
            id,
            organizationId: PostgresTestConfig.testOrgId,
          );
          expect(legitimate, isNotNull);

          // Tenant adversário não deve encontrar.
          final adversary = await repository.findById(
            id,
            organizationId: adversaryOrgId,
          );
          expect(adversary, isNull);
        },
      );

      // T03 — INV-19: BPS Precision Roundtrip
      test(
        'T03 (INV-19): BPS Precision roundtrip + rounding logic (1.75555 -> 17556)',
        () async {
          final id = uuid.v4();

          // Test with precise 1.75x
          final contract1 = _buildContract(
            id: id,
            organizationId: PostgresTestConfig.testOrgId,
            penaltyMultiplierBps: 17500,
          );
          await repository.save(contract1);
          final found1 = await repository.findById(
            id,
            organizationId: PostgresTestConfig.testOrgId,
          );
          expect(found1!.penaltyMultiplierBps, 17500);

          // Test rounding boundary: 1.75555 should be stored as 1.75555
          // and converted back to 17556 BPS via ((val * 10000).round()).
          final id2 = uuid.v4();
          // We bypass repository.save here to simulate raw DB value
          await client.from('contracts').insert({
            'id': id2,
            'organization_id': PostgresTestConfig.testOrgId,
            'name': 'Rounding Test',
            'contractor_name': 'Rounding LTDA',
            'status': 'draft',
            'valid_from_utc': DateTime.now().toUtc().toIso8601String(),
            'valid_until_utc': DateTime.now()
                .toUtc()
                .add(const Duration(days: 1))
                .toIso8601String(),
            'created_at_utc': DateTime.now().toUtc().toIso8601String(),
            'penalty_multiplier': 1.75555,
          });

          final found2 = await repository.findById(
            id2,
            organizationId: PostgresTestConfig.testOrgId,
          );
          expect(
            found2!.penaltyMultiplierBps,
            17556,
          ); // (1.75555 * 10000) = 17555.5 -> round() -> 17556
        },
      );

      // T05 — WASM Limit (2^53 - 1) centavos
      test(
        'T05: WASM Limit Audit — handles financial values up to 2^53 - 1 cents correctly',
        () async {
          final id = uuid.v4();
          const massiveCents =
              9007199254740991; // 2^53 - 1 (Max safe integer in JS/WASM)

          final contract = _buildContract(
            id: id,
            organizationId: PostgresTestConfig.testOrgId,
            financialCeiling: const Money(massiveCents),
          );

          await repository.save(contract);

          final found = await repository.findById(
            id,
            organizationId: PostgresTestConfig.testOrgId,
          );

          expect(found!.financialCeiling!.cents, massiveCents);
        },
      );

      // T06 — Forensic Proof of HTTP URL Filtering
      test(
        'T06 (INV-1): Forensic proof — verified organization_id filter in HTTP URL',
        () async {
          String? capturedUrl;
          final mockClient = MockClient((request) async {
            capturedUrl = request.url.toString();
            // Return empty list response for supabase select
            return http.Response(
              '[]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          });

          final interceptedClient = SupabaseClient(
            PostgresTestConfig.supabaseUrl,
            PostgresTestConfig.serviceRoleKey,
            httpClient: mockClient,
          );

          final forensicRepo = PostgresContractRepository(interceptedClient);

          await forensicRepo.findByOrganization('forensic-org-99');

          expect(capturedUrl, contains('organization_id=eq.forensic-org-99'));
          expect(capturedUrl, contains('order=created_at_utc.desc'));
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}

extension on PostgresContractRepository {
  // Helpers to access privatized methods for testing without changing the main API.
  // ignore: invalid_use_of_visible_for_testing_member
  void internalAssertFields(Map<String, dynamic> row) => assertFields(row);
  // ignore: invalid_use_of_visible_for_testing_member
  DateTime internalParseUtc(dynamic raw, String fieldName) =>
      parseUtc(raw, fieldName);
}
