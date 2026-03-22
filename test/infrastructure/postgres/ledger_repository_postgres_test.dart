import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sla_audit_ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'postgres_test_config.dart';

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
}
