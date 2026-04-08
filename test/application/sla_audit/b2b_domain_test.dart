import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/application/sla_audit/shift_projection_service.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule_repository.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/domain/sla_audit/operational_alert_repository.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_operational_zone_repository.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  group('Phase 5.10 - In-Memory B2B Domain & Projection Validation', () {
    late ShiftProjectionService projectionService;
    late InMemoryPlanDeclarationRepository planRepo;
    late InMemoryOperationalZoneRepository zoneRepo;

    final baseDate = DateTime.utc(2026, 3, 3); // Tuesday
    const testOrgId = 'org-b2b';
    const testContractId = 'c-b2b-01';

    setUp(() {
      tz.initializeTimeZones();
      zoneRepo = InMemoryOperationalZoneRepository();
      planRepo = InMemoryPlanDeclarationRepository();

      projectionService = ShiftProjectionService(
        planRepo: planRepo,
        zoneRepo: zoneRepo,
        alertRepo: MockAlertRepo(),
        dateTimeProvider: BrazilDateTimeProvider(),
      );
    });

    test(
      'Scenario 5.5 & 5.6: Determinism and Indempotency (Generation)',
      () async {
        // Setup Zones
        final z1 = OperationalZone.create(
          organizationId: testOrgId,
          name: 'Z1',
          type: ZoneType.garagem,
          geofence: const GeofenceConfiguration(
            latitude: 10,
            longitude: 10,
            radiusMeters: 50,
          ),
        );
        final z2 = OperationalZone.create(
          organizationId: testOrgId,
          name: 'Z2',
          type: ZoneType.cliente,
          geofence: const GeofenceConfiguration(
            latitude: 20,
            longitude: 20,
            radiusMeters: 50,
          ),
        );
        await zoneRepo.save(z1);
        await zoneRepo.save(z2);

        final pattern = ShiftPattern.create(
          index: 0,
          daysOfWeek: [DayOfWeek.tuesday],
          departureTimeLocal: '08:00',
          arrivalTimeLocal: '17:00',
          timezone: 'America/Sao_Paulo',
          originZoneId: z1.id,
          destinationZoneId: z2.id,
          penalties: SLAPenalties.create(
            noShowPenaltyBps: 10000,
            delayToleranceMinutes: 15,
            delayPenaltyPerMinute: const Money(100),
            downgradePenaltyFlat: const Money(5000),
          ),
        );

        final plan = PlanDeclaration.createWithShiftPatterns(
          organizationId: testOrgId,
          contractId: testContractId,
          planVersion: 1,
          declaredByUserId: 'admin',
          originalFileHash: 'hash',
          declaredAtUtc: baseDate,
          ruleSnapshot: const RuleSnapshot([]),
          shiftPatterns: [pattern],
        );

        // Gen 1
        final sets1 = await projectionService.projectDays(
          plan,
          from: baseDate,
          contractualValue: const Money(10000),
          days: 7,
        );

        // Gen 2 (Same everything - simulate idempotency of generation fn)
        final sets2 = await projectionService.projectDays(
          plan,
          from: baseDate,
          contractualValue: const Money(10000),
          days: 7,
        );

        // Assert Determinism
        expect(sets1.length, 1, reason: '1 Tuesday in 7 days');
        expect(sets2.length, 1);
        expect(
          sets1.first.setId,
          sets2.first.setId,
          reason: 'SHA-256 must be identical',
        );

        // Assert Snapshot Isolation (Scenario 5.7)
        expect(sets1.first.startLatitude, 10.0);

        // Mutate Zone
        final mutatedZ1 = OperationalZone.reconstitute(
          id: z1.id,
          organizationId: z1.organizationId,
          name: z1.name,
          type: z1.type,
          geofence: GeofenceConfiguration(
            latitude: 99.9, // Changed
            longitude: z1.geofence!.longitude,
            radiusMeters: z1.geofence!.radiusMeters,
          ),
        );
        await zoneRepo.save(mutatedZ1);

        // Sets already generated MUST retain original coords
        expect(sets1.first.startLatitude, 10.0, reason: 'Snapshot preserved');
      },
    );

    test('Scenario 5.8: Invalid Timezone throws DomainException', () {
      expect(
        () => ShiftPattern.create(
          index: 0,
          daysOfWeek: [DayOfWeek.monday],
          departureTimeLocal: '08:00',
          arrivalTimeLocal: '17:00',
          timezone: 'Invalid/Timezone',
          originZoneId: 'z1',
          destinationZoneId: 'z2',
          penalties: SLAPenalties.create(
            noShowPenaltyBps: 10000,
            delayToleranceMinutes: 15,
            delayPenaltyPerMinute: const Money(100),
            downgradePenaltyFlat: const Money(100),
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test(
      'Scenario 5.11: Extreme Timezone Offset (+14) normalization',
      () async {
        final z1 = OperationalZone.create(
          organizationId: testOrgId,
          name: 'Z-Line',
          type: ZoneType.garagem,
          geofence: const GeofenceConfiguration(
            latitude: 10,
            longitude: 10,
            radiusMeters: 50,
          ),
        );
        await zoneRepo.save(z1);

        final pattern = ShiftPattern.create(
          index: 0,
          daysOfWeek: [DayOfWeek.monday],
          departureTimeLocal: '00:30', // Very early Monday
          arrivalTimeLocal: '01:30',
          timezone: 'Pacific/Kiritimati', // UTC+14
          originZoneId: z1.id,
          destinationZoneId: z1.id,
          penalties: SLAPenalties.create(
            noShowPenaltyBps: 10000,
            delayToleranceMinutes: 15,
            delayPenaltyPerMinute: const Money(100),
            downgradePenaltyFlat: const Money(100),
          ),
        );

        final plan = PlanDeclaration.createWithShiftPatterns(
          organizationId: testOrgId,
          contractId: 'c-tz',
          planVersion: 1,
          declaredByUserId: 'admin',
          originalFileHash: 'hash',
          declaredAtUtc: baseDate,
          ruleSnapshot: const RuleSnapshot([]),
          shiftPatterns: [pattern],
        );

        // Monday 2026-03-02
        final monday = DateTime.utc(2026, 3, 2);
        final sets = await projectionService.projectDays(
          plan,
          from: monday,
          contractualValue: const Money(10000),
          days: 1,
        );

        expect(sets.length, 1);
        // Monday 00:30 at UTC+14 is actually Sunday 10:30 UTC
        // 00:30 - 14:00 = 10:30 (previous day)
        expect(
          sets.first.scheduledStartTimeUtc.day,
          1,
          reason: 'Must normalize to previous day in UTC',
        );
        expect(sets.first.scheduledStartTimeUtc.hour, 10);
        expect(sets.first.scheduledStartTimeUtc.minute, 30);
      },
    );
  });
}

class MockAlertRepo implements OperationalAlertRepository {
  @override
  Future<String> save(OperationalAlert alert) async => alert.id;
  @override
  Future<void> update(OperationalAlert alert) async {}
  @override
  Future<List<OperationalAlert>> findByEntityId(String entityId) async => [];
  Future<List<OperationalAlert>> findByOrganization(
    String orgId, {
    String? severity,
    String? status,
  }) async => [];
  @override
  Future<List<OperationalAlert>> findActive(String organizationId) async => [];
  @override
  Future<OperationalAlert?> findById(String id) async => null;
}

class MockRuleRepo implements ContractualRuleRepository {
  @override
  Future<RuleSnapshot> getActiveSnapshotForContract(
    String orgId,
    String contractId,
  ) async => const RuleSnapshot([]);
  @override
  Future<void> saveRule(ContractualRule rule) async {}
}

class MockContractRepo implements ContractRepository {
  final String orgId;
  final String contractId;
  MockContractRepo(this.orgId, this.contractId);

  @override
  Future<Contract?> findById(
    String id, {
    required String organizationId,
  }) async {
    if (id == contractId && organizationId == orgId) {
      return Contract.reconstitute(
        id: contractId,
        organizationId: orgId,
        name: 'Test',
        contractorName: 'Tester',
        validFromUtc: DateTime.utc(2026),
        validUntilUtc: DateTime.utc(2027),
        status: ContractStatus.active,
        createdAtUtc: DateTime.utc(2026),
      );
    }
    return null;
  }

  @override
  Future<void> save(Contract contract) async {}
  @override
  Future<List<Contract>> findByOrganization(
    String orgId, {
    ContractStatus? status,
  }) async => [];
}
