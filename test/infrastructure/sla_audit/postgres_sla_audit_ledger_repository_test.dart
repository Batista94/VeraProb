import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sla_audit_ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../postgres/postgres_test_config.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _requiredFields = [
  'organization_id',
  'type',
  'occurred_at_utc',
  'contract_id',
  'plan_version',
];

Map<String, dynamic> _validRow() => {
  'organization_id': 'org-1',
  'type': 'TEST',
  'occurred_at_utc': '2024-01-01T00:00:00Z',
  'contract_id': 'c-1',
  'plan_version': 1,
};

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'FASE 5 - Ledger Repository Postgres Tests (sla_audit_ledger)',
    () {
      late SupabaseClient client;
      late PostgresSlaAuditLedgerRepository repository;
      const uuid = Uuid();

      setUpAll(() async {
        if (isRunning) {
          client = await PostgresTestConfig.createClient();
          await PostgresTestConfig.ensureSentinelOrg(client: client);
          repository = PostgresSlaAuditLedgerRepository(client);
        }
      });

      test(
        '1. Append entry (append-only via repository) works smoothly',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();
          final entry = SlaLedgerEntry(
            organizationId: PostgresTestConfig.testOrgId,
            type: 'PLAN_DECLARED',
            setId: setId,
            contractId: contractId,
            planVersion: 1,
            occurredAtUtc: DateTime.now().toUtc(),
            payload: {'test': true},
          );

          // Must succeed (append-only insert)
          await repository.append(entry);

          // Prove insertion via reconstitution
          final entries = await repository.getEntriesBySetId(setId);
          expect(entries.length, 1);
          expect(entries.first.type, 'PLAN_DECLARED');
          expect(entries.first.contractId, contractId);
          expect(
            entries.first.eventId,
            isNotNull,
            reason: 'DB should assign a UUID eventId on insert',
          );
        },
      );

      test(
        '2. Chronological ordering: sequential appends return entries ordered by occurredAtUtc',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();

          final entry1 = SlaLedgerEntry(
            organizationId: PostgresTestConfig.testOrgId,
            type: 'EXECUTION_BOUND',
            setId: setId,
            contractId: contractId,
            planVersion: 1,
            occurredAtUtc: DateTime.now().toUtc().subtract(
              const Duration(seconds: 1),
            ),
          );

          final entry2 = SlaLedgerEntry(
            organizationId: PostgresTestConfig.testOrgId,
            type: 'EXECUTION_FINALIZED',
            setId: setId,
            contractId: contractId,
            planVersion: 1,
            occurredAtUtc: DateTime.now().toUtc(),
          );

          await repository.append(entry1);
          await repository.append(entry2);

          final entries = await repository.getEntriesBySetId(setId);
          expect(entries.length, 2);
          // getEntriesBySetId orders by occurred_at_utc ASC
          expect(
            entries.first.occurredAtUtc.isBefore(entries.last.occurredAtUtc),
            isTrue,
            reason: 'Ledger entries must be ordered chronologically',
          );
          expect(entries.first.type, 'EXECUTION_BOUND');
          expect(entries.last.type, 'EXECUTION_FINALIZED');
        },
      );

      test(
        '3. DB Constraints: Cannot UPDATE a ledger entry (RLS guard)',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();

          final entry = SlaLedgerEntry(
            organizationId: PostgresTestConfig.testOrgId,
            type: 'PLAN_DECLARED',
            setId: setId,
            contractId: contractId,
            planVersion: 1,
            occurredAtUtc: DateTime.now().toUtc(),
          );

          await repository.append(entry);

          // Get the persisted entry to know its UUID
          final entries = await repository.getEntriesBySetId(setId);
          final persistedEventId = entries.first.eventId!;

          // Direct UPDATE attempt via raw Supabase client (not via repository)
          await expectLater(
            () async => await client
                .from('sla_audit_ledger_v2')
                .update({'type': 'TAMPERED'})
                .eq('id', persistedEventId),
            throwsA(isA<PostgrestException>()),
            reason:
                'The database must reject UPDATEs on sla_audit_ledger_v2 (append-only)',
          );
        },
      );

      test(
        '4. DB Constraints: Cannot DELETE a ledger entry (RLS guard)',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();

          final entry = SlaLedgerEntry(
            organizationId: PostgresTestConfig.testOrgId,
            type: 'PLAN_DECLARED',
            setId: setId,
            contractId: contractId,
            planVersion: 1,
            occurredAtUtc: DateTime.now().toUtc(),
          );

          await repository.append(entry);

          // Get the persisted entry to know its UUID
          final entries = await repository.getEntriesBySetId(setId);
          final persistedEventId = entries.first.eventId!;

          // Direct DELETE attempt via raw Supabase client (not via repository)
          await expectLater(
            () async => await client
                .from('sla_audit_ledger_v2')
                .delete()
                .eq('id', persistedEventId),
            throwsA(isA<PostgrestException>()),
            reason:
                'The database must reject DELETEs on sla_audit_ledger_v2 (append-only)',
          );
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );

  // -------------------------------------------------------------------------
  // Grupo A — Unit: assertFields + parseUtc (sem banco de dados)
  // -------------------------------------------------------------------------
  group('Unit: assertFields — schema assertion (INV-18)', () {
    // Instantiation without a real client; only unit methods are called.
    // ignore: invalid_use_of_visible_for_testing_member
    final repo = PostgresSlaAuditLedgerRepository();

    for (final field in _requiredFields) {
      test('T05.$field: campo ausente lança IntegrityException', () {
        final row = _validRow()..remove(field);
        expect(
          () => repo.assertFields(row),
          throwsA(
            isA<IntegrityException>().having((e) => e.field, 'field', field),
          ),
        );
      });

      test('T05.$field: campo nulo lança IntegrityException', () {
        final row = _validRow()..[field] = null;
        expect(
          () => repo.assertFields(row),
          throwsA(
            isA<IntegrityException>().having((e) => e.field, 'field', field),
          ),
        );
      });
    }

    test('T05.valid: row completa não lança exceção', () {
      expect(() => repo.assertFields(_validRow()), returnsNormally);
    });
  });

  group('Unit: parseUtc — UTC enforcement (INV-9)', () {
    // ignore: invalid_use_of_visible_for_testing_member
    final repo = PostgresSlaAuditLedgerRepository();

    test('T05.parseUtc: null lança IntegrityException', () {
      expect(
        () => repo.parseUtc(null, 'occurred_at_utc'),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.field,
            'field',
            'occurred_at_utc',
          ),
        ),
      );
    });

    test('T05.parseUtc: tipo int lança IntegrityException', () {
      expect(
        () => repo.parseUtc(42, 'occurred_at_utc'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('T05.parseUtc: tipo Map lança IntegrityException', () {
      expect(
        () => repo.parseUtc({'k': 'v'}, 'occurred_at_utc'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('T05.parseUtc: string naive (sem Z) → DateTime UTC', () {
      final result = repo.parseUtc('2024-06-15T12:30:00', 'occurred_at_utc');
      expect(result.isUtc, isTrue);
      expect(result.hour, 12);
    });

    test('T05.parseUtc: string com Z já presente → DateTime UTC', () {
      final result = repo.parseUtc('2024-06-15T12:30:00Z', 'occurred_at_utc');
      expect(result.isUtc, isTrue);
      expect(result.hour, 12);
    });

    test('T05.parseUtc: string com offset +HH:mm → DateTime UTC', () {
      final result = repo.parseUtc(
        '2024-06-15T12:30:00+00:00',
        'occurred_at_utc',
      );
      expect(result.isUtc, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Grupo B — Integration: Suíte Forense T01-T08
  // -------------------------------------------------------------------------
  group(
    'Suíte Forense — Ledger Postgres (INV-1 / INV-7 / INV-9 / INV-19)',
    () {
      late SupabaseClient client;
      late PostgresSlaAuditLedgerRepository repository;
      const uuid = Uuid();

      setUpAll(() async {
        if (isRunning) {
          client = await PostgresTestConfig.createClient();
          await PostgresTestConfig.ensureSentinelOrg(client: client);
          repository = PostgresSlaAuditLedgerRepository(client);
        }
      });

      // T01 — append + getEntriesBySetId com organizationId explícito
      test(
        'T01: append + leitura com organizationId explícito retorna entrada correta',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();
          final entry = SlaLedgerEntry(
            organizationId: PostgresTestConfig.testOrgId,
            type: 'SANCTION_APPLIED',
            setId: setId,
            contractId: contractId,
            planVersion: 1,
            occurredAtUtc: DateTime.now().toUtc(),
            payload: {'penalty_cents': 5000},
          );

          await repository.append(entry);

          final entries = await repository.getEntriesBySetId(
            setId,
            organizationId: PostgresTestConfig.testOrgId,
          );
          expect(entries.length, 1);
          expect(entries.first.organizationId, PostgresTestConfig.testOrgId);
          expect(entries.first.type, 'SANCTION_APPLIED');
        },
      );

      // T02 — Isolamento de tenant via organizationId (INV-1)
      test(
        'T02 (INV-1): entrada do tenant legítimo não vaza para tenant adversário',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();
          final adversaryOrgId = uuid.v4();

          final entry = SlaLedgerEntry(
            organizationId: PostgresTestConfig.testOrgId,
            type: 'SANCTION_APPLIED',
            setId: setId,
            contractId: contractId,
            planVersion: 1,
            occurredAtUtc: DateTime.now().toUtc(),
          );

          await repository.append(entry);

          // Nominal: tenant legítimo vê a entrada.
          final legitimate = await repository.getEntriesBySetId(
            setId,
            organizationId: PostgresTestConfig.testOrgId,
          );
          expect(
            legitimate.length,
            1,
            reason: 'Tenant legítimo deve ver sua entrada',
          );

          // Real: tenant adversário recebe lista vazia.
          final adversary = await repository.getEntriesBySetId(
            setId,
            organizationId: adversaryOrgId,
          );
          expect(
            adversary,
            isEmpty,
            reason: 'Tenant adversário não deve ver entradas de outro org',
          );
        },
      );

      // T03 — getLastEntryId: null, por contractId, por org+contractId
      test(
        'T03: getLastEntryId retorna null para contractId inexistente',
        () async {
          final unknownContractId = uuid.v4();
          final result = await repository.getLastEntryId(
            contractId: unknownContractId,
          );
          expect(result, isNull);
        },
      );

      test(
        'T03: getLastEntryId retorna o ID da entrada mais recente filtrado por contractId',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();

          final entry = SlaLedgerEntry(
            organizationId: PostgresTestConfig.testOrgId,
            type: 'EXECUTION_BOUND',
            setId: setId,
            contractId: contractId,
            planVersion: 1,
            occurredAtUtc: DateTime.now().toUtc(),
          );

          final appendedId = await repository.append(entry);
          final lastId = await repository.getLastEntryId(
            organizationId: PostgresTestConfig.testOrgId,
            contractId: contractId,
          );

          expect(lastId, isNotNull);
          expect(lastId, equals(appendedId));
        },
      );

      // T04 — getEntriesBySetId com org errado → lista vazia (INV-1)
      test(
        'T04 (INV-1): getEntriesBySetId com organizationId errado retorna lista vazia',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();
          final wrongOrgId = uuid.v4();

          await repository.append(
            SlaLedgerEntry(
              organizationId: PostgresTestConfig.testOrgId,
              type: 'PLAN_DECLARED',
              setId: setId,
              contractId: contractId,
              planVersion: 1,
              occurredAtUtc: DateTime.now().toUtc(),
            ),
          );

          final result = await repository.getEntriesBySetId(
            setId,
            organizationId: wrongOrgId,
          );
          expect(result, isEmpty);
        },
      );

      // T06 — Limite de 64-bit: 2^53 - 1 (INV-19)
      test(
        'T06 (INV-19): payload com penalty_cents = 2^53-1 não perde precisão no roundtrip',
        () async {
          const maxSafeInt = 9007199254740991; // 2^53 - 1
          final setId = uuid.v4();
          final contractId = uuid.v4();

          await repository.append(
            SlaLedgerEntry(
              organizationId: PostgresTestConfig.testOrgId,
              type: 'SANCTION_APPLIED',
              setId: setId,
              contractId: contractId,
              planVersion: 1,
              occurredAtUtc: DateTime.now().toUtc(),
              payload: {'penalty_cents': maxSafeInt},
            ),
          );

          final entries = await repository.getEntriesBySetId(setId);
          expect(entries.first.payload['penalty_cents'], equals(maxSafeInt));
        },
      );

      // T07 — Sem drift de double para valores financeiros (INV-19)
      test(
        'T07 (INV-19): penalty_cents persistido como int 100 é recuperado como int, sem drift de double',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();

          await repository.append(
            SlaLedgerEntry(
              organizationId: PostgresTestConfig.testOrgId,
              type: 'SANCTION_APPLIED',
              setId: setId,
              contractId: contractId,
              planVersion: 1,
              occurredAtUtc: DateTime.now().toUtc(),
              payload: {'penalty_cents': 100},
            ),
          );

          final entries = await repository.getEntriesBySetId(setId);
          final recovered = entries.first.payload['penalty_cents'];
          expect(
            recovered,
            isA<int>(),
            reason: 'Valor financeiro deve ser int, nunca double',
          );
          expect(recovered, equals(100));
        },
      );

      // T08 — Tentativa de sobrescrita (Primary Key constraint / INV-7)
      test(
        'T08 (INV-7): inserção direta com UUID duplicado é rejeitada pelo banco (append-only)',
        () async {
          final setId = uuid.v4();
          final contractId = uuid.v4();
          final entry = SlaLedgerEntry(
            organizationId: PostgresTestConfig.testOrgId,
            type: 'PLAN_DECLARED',
            setId: setId,
            contractId: contractId,
            planVersion: 1,
            occurredAtUtc: DateTime.now().toUtc(),
          );

          final existingId = await repository.append(entry);

          // Tentativa de inserção com o mesmo UUID de primary key.
          await expectLater(
            () async => client.from('sla_audit_ledger_v2').insert({
              'id': existingId,
              'organization_id': PostgresTestConfig.testOrgId,
              'type': 'OVERWRITE_ATTEMPT',
              'contract_id': contractId,
              'plan_version': 1,
              'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
            }),
            throwsA(isA<PostgrestException>()),
            reason:
                'O banco deve rejeitar inserção com UUID duplicado via Primary Key constraint (INV-7)',
          );
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
