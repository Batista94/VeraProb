import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_vehicle_infraction_recurrence_repository.dart';

import '../postgres/postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'WS-6 — PostgresVehicleInfractionRecurrenceRepository',
    () {
      late SupabaseClient client;
      late PostgresVehicleInfractionRecurrenceRepository repository;
      const uuid = Uuid();

      // Stable plate used across tests that need cross-query isolation
      final otherOrgId = uuid.v4();

      setUpAll(() async {
        client = await PostgresTestConfig.createClient();
        await PostgresTestConfig.ensureSentinelOrg(client: client);
        // Ensure a second org for tenant-isolation tests
        await PostgresTestConfig.ensureSentinelOrg(
          client: client,
          id: otherOrgId,
          name: 'Other Org',
        );
        repository = PostgresVehicleInfractionRecurrenceRepository(client);
      });

      // ── Helper to insert a raw sanction_review_queue row ────────────────
      Future<String> insertQueueRow({
        required String vehiclePlate,
        required DateTime createdAtUtc,
        String? organizationId,
        String? clauseRef,
      }) async {
        final id = uuid.v4();
        final org = organizationId ?? PostgresTestConfig.testOrgId;
        final evidence = VerdictEvidence.create(
          clauseRef: clauseRef ?? 'ATR-01',
          ruleId: 'rule-test',
          ruleVersion: 1,
          primaryEvidenceLat: -23.55,
          primaryEvidenceLng: -46.63,
          primaryEvidenceTimestampUtc: createdAtUtc,
          deltaValue: 5.0,
          thresholdValue: 0.0,
          fineCents: const Money(10000),
          confidenceScore: 100,
        );

        await client.from('sanction_review_queue').insert({
          'id': id,
          'organization_id': org,
          'ledger_entry_id': uuid.v4(),
          'set_id': uuid.v4(),
          'contract_id': uuid.v4(),
          'vehicle_plate': vehiclePlate,
          'verdict_evidence': evidence.toJson(),
          'status': 'pending',
          'created_at': createdAtUtc.toIso8601String(),
        });

        return id;
      }

      test('1. Returns empty list when no rows match the plate', () async {
        final result = await repository.findByPlateInMonth(
          organizationId: PostgresTestConfig.testOrgId,
          vehiclePlate: 'ZZZ-9999',
          referenceUtc: DateTime.now().toUtc(),
          excludeQueueEntryId: uuid.v4(),
        );

        expect(result, isEmpty);
      });

      test('2. Returns same-month rows for the plate', () async {
        final plate = 'TST-${uuid.v4().substring(0, 4).toUpperCase()}';
        final now = DateTime.now().toUtc();
        // Use fixed offsets from month-start to avoid crossing month boundaries
        final monthStart = DateTime.utc(now.year, now.month, 1);
        final id1 = await insertQueueRow(
          vehiclePlate: plate,
          createdAtUtc: monthStart.add(const Duration(hours: 2)),
        );
        final id2 = await insertQueueRow(
          vehiclePlate: plate,
          createdAtUtc: monthStart.add(const Duration(hours: 4)),
        );

        final result = await repository.findByPlateInMonth(
          organizationId: PostgresTestConfig.testOrgId,
          vehiclePlate: plate,
          referenceUtc: now,
          excludeQueueEntryId: uuid.v4(), // exclude nonexistent → include all
        );

        final ids = result.map((e) => e.id).toSet();
        expect(ids, containsAll([id1, id2]));
      });

      test('3. Excludes the current queue entry ID from results', () async {
        final plate = 'EXC-${uuid.v4().substring(0, 4).toUpperCase()}';
        final now = DateTime.now().toUtc();
        final monthStart = DateTime.utc(now.year, now.month, 1);
        final priorId = await insertQueueRow(
          vehiclePlate: plate,
          createdAtUtc: monthStart.add(const Duration(hours: 1)),
        );
        final currentId = await insertQueueRow(
          vehiclePlate: plate,
          createdAtUtc: monthStart.add(const Duration(hours: 2)),
        );

        final result = await repository.findByPlateInMonth(
          organizationId: PostgresTestConfig.testOrgId,
          vehiclePlate: plate,
          referenceUtc: now,
          excludeQueueEntryId: currentId,
        );

        final ids = result.map((e) => e.id).toSet();
        expect(ids, contains(priorId));
        expect(ids, isNot(contains(currentId)));
      });

      test('4. Ignores rows from a different calendar month', () async {
        final plate = 'MON-${uuid.v4().substring(0, 4).toUpperCase()}';
        final now = DateTime.now().toUtc();

        // Row in a different month (30 days ago — safe: always different month
        // unless today is day 1; use month-start arithmetic to be deterministic)
        final prevMonthStart = DateTime.utc(
          now.month == 1 ? now.year - 1 : now.year,
          now.month == 1 ? 12 : now.month - 1,
          15,
        );
        await insertQueueRow(vehiclePlate: plate, createdAtUtc: prevMonthStart);
        final thisMonthId = await insertQueueRow(
          vehiclePlate: plate,
          createdAtUtc: now.subtract(const Duration(hours: 2)),
        );

        final result = await repository.findByPlateInMonth(
          organizationId: PostgresTestConfig.testOrgId,
          vehiclePlate: plate,
          referenceUtc: now,
          excludeQueueEntryId: uuid.v4(),
        );

        final ids = result.map((e) => e.id).toSet();
        // Only the current-month row is returned
        expect(ids, equals({thisMonthId}));
      });

      test('5. Tenant isolation: cross-org rows are invisible', () async {
        final plate = 'ISO-${uuid.v4().substring(0, 4).toUpperCase()}';
        final now = DateTime.now().toUtc();

        // Insert one row under testOrgId and one under otherOrgId
        final ownId = await insertQueueRow(
          vehiclePlate: plate,
          createdAtUtc: now.subtract(const Duration(hours: 3)),
        );
        await insertQueueRow(
          vehiclePlate: plate,
          createdAtUtc: now.subtract(const Duration(hours: 2)),
          organizationId: otherOrgId,
        );

        final result = await repository.findByPlateInMonth(
          organizationId: PostgresTestConfig.testOrgId,
          vehiclePlate: plate,
          referenceUtc: now,
          excludeQueueEntryId: uuid.v4(),
        );

        final ids = result.map((e) => e.id).toSet();
        expect(
          ids,
          equals({ownId}),
          reason: 'Must not see rows from other organizations (INV-1)',
        );
      });

      test('6. Results are ordered by created_at ascending', () async {
        final plate = 'ORD-${uuid.v4().substring(0, 4).toUpperCase()}';
        final now = DateTime.now().toUtc();
        final monthStart = DateTime.utc(now.year, now.month, 1);
        final id1 = await insertQueueRow(
          vehiclePlate: plate,
          createdAtUtc: monthStart.add(const Duration(hours: 1)),
        );
        final id2 = await insertQueueRow(
          vehiclePlate: plate,
          createdAtUtc: monthStart.add(const Duration(hours: 3)),
        );
        final id3 = await insertQueueRow(
          vehiclePlate: plate,
          createdAtUtc: monthStart.add(const Duration(hours: 5)),
        );

        final result = await repository.findByPlateInMonth(
          organizationId: PostgresTestConfig.testOrgId,
          vehiclePlate: plate,
          referenceUtc: now,
          excludeQueueEntryId: uuid.v4(),
        );

        final ids = result.map((e) => e.id).toList();
        expect(
          ids,
          equals([id1, id2, id3]),
          reason: 'Results must be ordered oldest-first',
        );
      });

      test(
        '7. Returned entries carry correct vehiclePlate and UTC timestamps',
        () async {
          final plate = 'CHK-${uuid.v4().substring(0, 4).toUpperCase()}';
          final ts = DateTime.utc(
            DateTime.now().toUtc().year,
            DateTime.now().toUtc().month,
            10,
            14,
            30,
          );
          await insertQueueRow(
            vehiclePlate: plate,
            createdAtUtc: ts,
            clauseRef: 'VEL-02',
          );

          final result = await repository.findByPlateInMonth(
            organizationId: PostgresTestConfig.testOrgId,
            vehiclePlate: plate,
            referenceUtc: DateTime.now().toUtc(),
            excludeQueueEntryId: uuid.v4(),
          );

          expect(result, hasLength(1));
          final entry = result.first;
          expect(entry.vehiclePlate, equals(plate));
          expect(
            entry.createdAtUtc.isUtc,
            isTrue,
            reason: 'createdAtUtc must be UTC (INV-9)',
          );
          expect(entry.verdictEvidence.clauseRef, equals('VEL-02'));
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
