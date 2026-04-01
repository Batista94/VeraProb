import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_plan_declaration_repository.dart';
import 'package:uuid/uuid.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();
  tz_data.initializeTimeZones();

  group(
    'PostgresPlanDeclarationRepository',
    () {
      late SupabaseClient client;
      late PostgresPlanDeclarationRepository repository;
      const uuid = Uuid();

      setUpAll(() async {
        if (isRunning) {
          client = await PostgresTestConfig.createClient();
          await PostgresTestConfig.ensureSentinelOrg(client: client);
          repository = PostgresPlanDeclarationRepository(client);
        }
      });

      test('save and findById - Manual Plan', () async {
        final contractId = uuid.v4();
        const organizationId = PostgresTestConfig.testOrgId;

        final service = ContractualServiceExecution.create(
          contractId: contractId,
          scheduledStartTimeUtc: DateTime.utc(2026, 4, 1, 8, 0),
          scheduledEndTimeUtc: DateTime.utc(2026, 4, 1, 9, 0),
          startLatitude: -23.5505,
          startLongitude: -46.6333,
          startRadiusMeters: 100,
          endLatitude: -23.5506,
          endLongitude: -46.6334,
          endRadiusMeters: 100,
          contractualValue: const Money(10000),
          noShowPenaltyMultiplier: 1.5,
        );

        final plan = PlanDeclaration.create(
          organizationId: organizationId,
          contractId: contractId,
          declaredAtUtc: DateTime.utc(2026, 3, 28, 20, 0),
          declaredByUserId: 'test-user',
          planVersion: 1,
          originalFileHash: 'hash-manual',
          ruleSnapshot: const RuleSnapshot([]),
          services: [service],
        );

        // 1. Save
        await repository.save(plan);

        // 2. Find by Id
        final loaded = await repository.findById(plan.id);
        expect(loaded, isNotNull);
        expect(loaded!.id, plan.id);
        expect(loaded.contractId, contractId);
        expect(loaded.services.length, 1);
        expect(loaded.services[0].setId, service.setId);
        expect(loaded.services[0].contractualValue.cents, 10000);
      });

      test('save and findByContract - B2B Plan (Shift Patterns)', () async {
        final contractId = uuid.v4();
        const organizationId = PostgresTestConfig.testOrgId;

        final pattern = ShiftPattern.create(
          index: 0,
          daysOfWeek: [DayOfWeek.monday, DayOfWeek.tuesday],
          arrivalTimeLocal: '08:00',
          departureTimeLocal: '07:00',
          timezone: 'America/Sao_Paulo',
          originZoneId: 'zone-a',
          destinationZoneId: 'zone-b',
          penalties: SLAPenalties.create(
            noShowPenaltyMultiplier: 1.5,
            delayToleranceMinutes: 15,
            delayPenaltyPerMinute: const Money(100),
            downgradePenaltyFlat: const Money(5000),
          ),
        );

        final plan = PlanDeclaration.createWithShiftPatterns(
          organizationId: organizationId,
          contractId: contractId,
          declaredAtUtc: DateTime.utc(2026, 3, 28, 21, 0),
          declaredByUserId: 'test-user-b2b',
          planVersion: 2,
          originalFileHash: 'hash-b2b',
          ruleSnapshot: const RuleSnapshot([]),
          shiftPatterns: [pattern],
        );

        await repository.save(plan);

        final contractPlans = await repository.findByContract(
          contractId,
          organizationId: organizationId,
        );

        expect(contractPlans.length, 1);
        expect(contractPlans[0].id, plan.id);
        expect(contractPlans[0].shiftPatterns.length, 1);
        expect(contractPlans[0].shiftPatterns[0].index, 0);
        expect(contractPlans[0].shiftPatterns[0].timezone, 'America/Sao_Paulo');
      });

      test('findByOrganization', () async {
        final organizationId = uuid.v4(); // Unique org to avoid pollution
        final contractId = uuid.v4();

        final service = ContractualServiceExecution.create(
          contractId: contractId,
          scheduledStartTimeUtc: DateTime.utc(2026, 5, 1, 10, 0),
          scheduledEndTimeUtc: DateTime.utc(2026, 5, 1, 11, 0),
          startLatitude: -23.5505,
          startLongitude: -46.6333,
          startRadiusMeters: 100,
          endLatitude: -23.5506,
          endLongitude: -46.6334,
          endRadiusMeters: 100,
          contractualValue: const Money(20000),
          noShowPenaltyMultiplier: 2.0,
        );

        final plan = PlanDeclaration.create(
          organizationId: organizationId,
          contractId: contractId,
          declaredAtUtc: DateTime.utc(2026, 3, 28, 22, 0),
          declaredByUserId: 'test-user-org',
          planVersion: 1,
          originalFileHash: 'hash-org',
          ruleSnapshot: const RuleSnapshot([]),
          services: [service],
        );

        await PostgresTestConfig.ensureSentinelOrg(
          client: client,
          id: organizationId,
        );
        await repository.save(plan);

        final orgPlans = await repository.findByOrganization(organizationId);
        expect(orgPlans.any((p) => p.id == plan.id), isTrue);
      });

      test('saveProjectedSets - Idempotency vs Update', () async {
        final contractId = uuid.v4();
        const organizationId = PostgresTestConfig.testOrgId;
        const z1 = '00000000-0000-0000-0000-0000000000a1';
        const z2 = '00000000-0000-0000-0000-0000000000b2';

        // Seed zones to satisfy FK constraints
        if (isRunning) {
          await client.from('operational_zones').upsert([
            {
              'id': z1,
              'organization_id': organizationId,
              'name': 'Zone A (Test ID)',
              'type': 'garagem',
            },
            {
              'id': z2,
              'organization_id': organizationId,
              'name': 'Zone B (Test ID)',
              'type': 'cliente',
            },
          ]);
        }

        // Plan with patterns
        final pattern = ShiftPattern.create(
          index: 0,
          daysOfWeek: [DayOfWeek.monday],
          arrivalTimeLocal: '09:00',
          departureTimeLocal: '08:00',
          timezone: 'UTC',
          originZoneId: z1,
          destinationZoneId: z2,
          penalties: SLAPenalties.create(
            noShowPenaltyMultiplier: 1.5,
            delayToleranceMinutes: 10,
            delayPenaltyPerMinute: const Money(50),
            downgradePenaltyFlat: const Money(1000),
          ),
        );

        final plan = PlanDeclaration.createWithShiftPatterns(
          organizationId: organizationId,
          contractId: contractId,
          declaredAtUtc: DateTime.utc(2026, 3, 28, 23, 0),
          declaredByUserId: 'test-user-proj',
          planVersion: 1,
          originalFileHash: 'hash-proj',
          ruleSnapshot: const RuleSnapshot([]),
          shiftPatterns: [pattern],
        );

        await repository.save(plan);

        // Simulated Projection for 2026-06-01 (a Monday)
        final projectedDate = DateTime.utc(2026, 6, 1);
        final projectedSet = ContractualServiceExecution.createProjected(
          planDeclarationId: plan.id,
          shiftPatternIndex: 0,
          operationalDate: projectedDate,
          scheduledStartTimeUtc: DateTime.utc(2026, 6, 1, 8, 0),
          scheduledEndTimeUtc: DateTime.utc(2026, 6, 1, 9, 0),
          originZoneId: z1,
          startLatitude: -23.1,
          startLongitude: -46.1,
          startRadiusMeters: 500,
          destinationZoneId: z2,
          endLatitude: -23.2,
          endLongitude: -46.2,
          endRadiusMeters: 500,
          contractualValue: const Money(5000),
          noShowPenaltyMultiplier: 1.5,
          delayToleranceMinutes: 10,
          delayPenaltyPerMinute: const Money(50),
          downgradePenaltyFlat: const Money(1000),
        );

        // 1. First save
        await repository.saveProjectedSets(plan.id, [
          projectedSet,
        ], organizationId: organizationId);

        final savedPlan = await repository.findById(plan.id);
        expect(savedPlan!.services.length, 1);
        expect(savedPlan.services[0].setId, projectedSet.setId);
        expect(savedPlan.services[0].operationalDate, equals(projectedDate));

        // 2. Upsert (Idempotency check) - should ignore duplicates if constraint matches
        await repository.saveProjectedSets(plan.id, [
          projectedSet,
        ], organizationId: organizationId);

        final savedPlan2 = await repository.findById(plan.id);
        expect(savedPlan2!.services.length, 1); // Still 1
      });

      test('save - Duplicate Version throws Exception', () async {
        final contractId = uuid.v4();
        const organizationId = PostgresTestConfig.testOrgId;

        final p1 = PlanDeclaration.create(
          organizationId: organizationId,
          contractId: contractId,
          declaredAtUtc: DateTime.now().toUtc(),
          declaredByUserId: 'u1',
          planVersion: 5,
          originalFileHash: 'h1',
          ruleSnapshot: const RuleSnapshot([]),
          services: [
            ContractualServiceExecution.create(
              contractId: contractId,
              scheduledStartTimeUtc: DateTime.now().toUtc(),
              scheduledEndTimeUtc: DateTime.now().toUtc().add(
                const Duration(hours: 1),
              ),
              startLatitude: 0,
              startLongitude: 0,
              startRadiusMeters: 1,
              endLatitude: 0,
              endLongitude: 0,
              endRadiusMeters: 1,
              contractualValue: const Money(1),
              noShowPenaltyMultiplier: 1,
            ),
          ],
        );

        await repository.save(p1);

        final p2 = PlanDeclaration.create(
          organizationId: organizationId,
          contractId: contractId,
          declaredAtUtc: DateTime.now().toUtc(),
          declaredByUserId: 'u1',
          planVersion: 5, // SAME VERSION
          originalFileHash: 'h2',
          ruleSnapshot: const RuleSnapshot([]),
          services: [
            ContractualServiceExecution.create(
              contractId: contractId,
              scheduledStartTimeUtc: DateTime.now().toUtc().add(
                const Duration(days: 1),
              ),
              scheduledEndTimeUtc: DateTime.now().toUtc().add(
                const Duration(days: 1, hours: 1),
              ),
              startLatitude: 0,
              startLongitude: 0,
              startRadiusMeters: 1,
              endLatitude: 0,
              endLongitude: 0,
              endRadiusMeters: 1,
              contractualValue: const Money(1),
              noShowPenaltyMultiplier: 1,
            ),
          ],
        );

        expect(repository.save(p2), throwsA(anything));
      });
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
