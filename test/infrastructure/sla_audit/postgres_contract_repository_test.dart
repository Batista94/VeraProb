import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contract_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../postgres/postgres_test_config.dart';

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
};

Contract _buildContract({
  required String id,
  required String organizationId,
  Money? financialCeiling,
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
  );
}

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  // -------------------------------------------------------------------------
  // Grupo A — Unit: assertFields (INV-18) — sem banco de dados
  // -------------------------------------------------------------------------
  group('Unit: assertFields — schema assertion (INV-18)', () {
    // ignore: invalid_use_of_visible_for_testing_member
    final repo = PostgresContractRepository();

    for (final field in _requiredFields) {
      test('T04.$field: campo ausente lança IntegrityException', () {
        final row = _validRow()..remove(field);
        expect(
          () => repo.assertFields(row),
          throwsA(
            isA<IntegrityException>().having((e) => e.field, 'field', field),
          ),
        );
      });

      test('T04.$field: campo nulo lança IntegrityException', () {
        final row = _validRow()..[field] = null;
        expect(
          () => repo.assertFields(row),
          throwsA(
            isA<IntegrityException>().having((e) => e.field, 'field', field),
          ),
        );
      });
    }

    test('T04.valid: row completa não lança exceção', () {
      expect(() => repo.assertFields(_validRow()), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // Grupo B — Unit: parseUtc — UTC enforcement (INV-9) — sem banco de dados
  // -------------------------------------------------------------------------
  group('Unit: parseUtc — UTC enforcement (INV-9)', () {
    // ignore: invalid_use_of_visible_for_testing_member
    final repo = PostgresContractRepository();

    test('T05.parseUtc: null lança IntegrityException', () {
      expect(
        () => repo.parseUtc(null, 'valid_from_utc'),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.field,
            'field',
            'valid_from_utc',
          ),
        ),
      );
    });

    test('T05.parseUtc: tipo int lança IntegrityException', () {
      expect(
        () => repo.parseUtc(42, 'valid_from_utc'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('T05.parseUtc: tipo Map lança IntegrityException', () {
      expect(
        () => repo.parseUtc({'k': 'v'}, 'valid_from_utc'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('T05.parseUtc: string naive (sem Z) → DateTime UTC (INV-9)', () {
      final result = repo.parseUtc('2024-06-15T12:30:00', 'valid_from_utc');
      expect(result.isUtc, isTrue);
      expect(result.hour, 12);
    });

    test('T05.parseUtc: string com Z já presente → DateTime UTC', () {
      final result = repo.parseUtc('2024-06-15T12:30:00Z', 'valid_from_utc');
      expect(result.isUtc, isTrue);
      expect(result.hour, 12);
    });

    test('T05.parseUtc: string com offset +00:00 → DateTime UTC', () {
      final result = repo.parseUtc(
        '2024-06-15T12:30:00+00:00',
        'valid_from_utc',
      );
      expect(result.isUtc, isTrue);
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
          expect(found.description, contract.description);
          expect(found.status, ContractStatus.draft);
          expect(found.validFromUtc.isUtc, isTrue);
          expect(found.validUntilUtc.isUtc, isTrue);
          expect(found.createdAtUtc.isUtc, isTrue);
          expect(found.activatedAtUtc, isNull);
          expect(found.closedAtUtc, isNull);
          expect(found.closedByUserId, isNull);
          expect(found.closeReason, isNull);
          expect(found.submittedForApprovalAtUtc, isNull);
          expect(found.clonedFromContractId, isNull);
          expect(found.financialCeiling, const Money(150000));
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
          expect(
            legitimate,
            isNotNull,
            reason: 'Tenant legítimo deve encontrar o contrato',
          );

          // Tenant adversário não deve encontrar.
          final adversary = await repository.findById(
            id,
            organizationId: adversaryOrgId,
          );
          expect(
            adversary,
            isNull,
            reason:
                'Tenant adversário não deve ver contrato de outro org (INV-1)',
          );
        },
      );

      // T03 — INV-19: financial_ceiling_cents → Money roundtrip sem perda de precisão
      test(
        'T03 (INV-19): financial_ceiling_cents persistido como int é recuperado como Money sem drift',
        () async {
          final id = uuid.v4();
          // 150000 cents = R$ 1500,00 — valor de referência para precisão
          final contract = _buildContract(
            id: id,
            organizationId: PostgresTestConfig.testOrgId,
            financialCeiling: const Money(150000),
          );

          await repository.save(contract);

          final found = await repository.findById(
            id,
            organizationId: PostgresTestConfig.testOrgId,
          );

          expect(found!.financialCeiling, isNotNull);
          expect(
            found.financialCeiling!.cents,
            150000,
            reason:
                'financial_ceiling_cents deve sobreviver ao roundtrip como int exato (INV-19)',
          );
          expect(
            found.financialCeiling!.cents,
            isA<int>(),
            reason: 'Valor financeiro deve ser int, nunca double (INV-19)',
          );
        },
      );

      // T04 (integração) — save + findById com contrato sem financial_ceiling
      test(
        'T04: contrato sem financial_ceiling é persistido e recuperado com financialCeiling null',
        () async {
          final id = uuid.v4();
          final contract = _buildContract(
            id: id,
            organizationId: PostgresTestConfig.testOrgId,
          );

          await repository.save(contract);

          final found = await repository.findById(
            id,
            organizationId: PostgresTestConfig.testOrgId,
          );

          expect(found, isNotNull);
          expect(found!.financialCeiling, isNull);
        },
      );

      // T05 — INV-9: datas de vigência retornam com isUtc == true
      test(
        'T05 (INV-9): validFromUtc e validUntilUtc retornam como DateTime UTC (sem drift de fuso)',
        () async {
          final id = uuid.v4();
          final validFrom = DateTime.utc(2024, 3, 15, 8, 0, 0);
          final validUntil = DateTime.utc(2025, 3, 15, 8, 0, 0);

          final contract = Contract.reconstitute(
            id: id,
            organizationId: PostgresTestConfig.testOrgId,
            name: 'UTC Test Contract',
            contractorName: 'Transportadora UTC LTDA',
            validFromUtc: validFrom,
            validUntilUtc: validUntil,
            status: ContractStatus.draft,
            createdAtUtc: DateTime.now().toUtc(),
          );

          await repository.save(contract);

          final found = await repository.findById(
            id,
            organizationId: PostgresTestConfig.testOrgId,
          );

          expect(found, isNotNull);
          expect(
            found!.validFromUtc.isUtc,
            isTrue,
            reason: 'validFromUtc deve ser UTC após roundtrip (INV-9)',
          );
          expect(
            found.validUntilUtc.isUtc,
            isTrue,
            reason: 'validUntilUtc deve ser UTC após roundtrip (INV-9)',
          );
          expect(
            found.createdAtUtc.isUtc,
            isTrue,
            reason: 'createdAtUtc deve ser UTC após roundtrip (INV-9)',
          );
          expect(found.validFromUtc.year, 2024);
          expect(found.validFromUtc.month, 3);
          expect(found.validFromUtc.day, 15);
        },
      );

      // T06 — INV-1: Prova forense de isolamento via findByOrganization
      test(
        'T06 (INV-1): findByOrganization com org legítima não vaza para org adversária',
        () async {
          final id = uuid.v4();
          final adversaryOrgId = uuid.v4();

          final contract = _buildContract(
            id: id,
            organizationId: PostgresTestConfig.testOrgId,
          );

          await repository.save(contract);

          // Tenant legítimo vê seus contratos.
          final legitimateList = await repository.findByOrganization(
            PostgresTestConfig.testOrgId,
          );
          expect(
            legitimateList.any((c) => c.id == id),
            isTrue,
            reason: 'Tenant legítimo deve ver seus próprios contratos',
          );

          // Tenant adversário recebe lista vazia para este contrato.
          final adversaryList = await repository.findByOrganization(
            adversaryOrgId,
          );
          expect(
            adversaryList.any((c) => c.id == id),
            isFalse,
            reason:
                'Tenant adversário não deve ver contratos de outro org (INV-1)',
          );
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
