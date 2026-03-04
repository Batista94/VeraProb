import 'package:busflow/domain/sla_audit/sla_ledger_entry.dart';
import 'package:busflow/infrastructure/sla_audit/postgres_sla_audit_ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'postgres_test_config.dart';

void main() {
  group('FASE 5 - Ledger Repository Postgres Tests (sla_audit_ledger)', () {
    late SupabaseClient client;
    late PostgresSlaAuditLedgerRepository repository;
    final uuid = const Uuid();

    setUpAll(() async {
      client = await PostgresTestConfig.createClient();
      repository = PostgresSlaAuditLedgerRepository(client);
    });

    test(
      '1. Append entry (append-only via repository) works smoothly',
      () async {
        final setId = uuid.v4();
        final contractId = uuid.v4();
        final entry = SlaLedgerEntry(
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
          entries.first.id,
          isNotNull,
          reason: 'DB should assign monotonic id',
        );
      },
    );

    test(
      '2. Monotonic ordering: sequential appends return ordered IDs',
      () async {
        final setId = uuid.v4();
        final contractId = uuid.v4();

        final entry1 = SlaLedgerEntry(
          type: 'EXECUTION_BOUND',
          setId: setId,
          contractId: contractId,
          planVersion: 1,
          occurredAtUtc: DateTime.now().toUtc().subtract(
            const Duration(seconds: 1),
          ),
        );

        final entry2 = SlaLedgerEntry(
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
        // IDs are monotonically increasing (bigserial)
        expect(
          entries.first.id! < entries.last.id!,
          isTrue,
          reason: 'Ledger IDs must be monotonically increasing',
        );
      },
    );

    test('3. DB Constraints: Cannot UPDATE a ledger entry', () async {
      final setId = uuid.v4();
      final contractId = uuid.v4();

      final entry = SlaLedgerEntry(
        type: 'PLAN_DECLARED',
        setId: setId,
        contractId: contractId,
        planVersion: 1,
        occurredAtUtc: DateTime.now().toUtc(),
      );

      await repository.append(entry);

      // Get the persisted entry to know its ID
      final entries = await repository.getEntriesBySetId(setId);
      final persistedId = entries.first.id!;

      // Direct UPDATE attempt via raw Supabase client (not via repository)
      expect(
        () async => await client
            .from('sla_audit_ledger')
            .update({'type': 'TAMPERED'})
            .eq('id', persistedId),
        throwsA(isA<PostgrestException>()),
        reason:
            'The database must reject UPDATEs on sla_audit_ledger (append-only)',
      );
    });

    test('4. DB Constraints: Cannot DELETE a ledger entry', () async {
      final setId = uuid.v4();
      final contractId = uuid.v4();

      final entry = SlaLedgerEntry(
        type: 'PLAN_DECLARED',
        setId: setId,
        contractId: contractId,
        planVersion: 1,
        occurredAtUtc: DateTime.now().toUtc(),
      );

      await repository.append(entry);

      // Get the persisted entry to know its ID
      final entries = await repository.getEntriesBySetId(setId);
      final persistedId = entries.first.id!;

      // Direct DELETE attempt via raw Supabase client (not via repository)
      expect(
        () async => await client
            .from('sla_audit_ledger')
            .delete()
            .eq('id', persistedId),
        throwsA(isA<PostgrestException>()),
        reason:
            'The database must reject DELETEs on sla_audit_ledger (append-only)',
      );
    });
  });
}
