import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:pactaflow/application/sla_audit/shift_projection_service.dart';
import 'package:pactaflow/domain/sla_audit/domain_exception.dart';
import 'package:pactaflow/domain/sla_audit/contractual_service_execution.dart';
import 'package:pactaflow/domain/sla_audit/operational_zone.dart';
import 'package:pactaflow/domain/sla_audit/plan_declaration.dart';
import 'package:pactaflow/domain/sla_audit/rule_snapshot.dart';
import 'package:pactaflow/domain/sla_audit/shift_pattern.dart';
import 'package:pactaflow/domain/sla_audit/sla_penalties.dart';
import 'package:pactaflow/domain/shared/money.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_operational_alert_repository.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_operational_zone_repository.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  // ── Shared fixtures ──────────────────────────────────────

  const orgId = 'org-projection-test';
  const contractId = 'contract-proj-1';

  // Monday 2026-03-09
  final monday = DateTime.utc(2026, 3, 9);

  OperationalZone makeZone({
    String name = 'Garagem Central',
    double lat = -23.5505,
    double lng = -46.6333,
    int radius = 200,
  }) {
    return OperationalZone.create(
      organizationId: orgId,
      name: name,
      type: ZoneType.garagem,
      geofence: GeofenceConfiguration(
        latitude: lat,
        longitude: lng,
        radiusMeters: radius,
      ),
    );
  }

  SLAPenalties makePenalties() {
    return SLAPenalties.create(
      noShowPenaltyMultiplier: 1.5,
      delayToleranceMinutes: 10,
      delayPenaltyPerMinute: const Money(100),
      downgradePenaltyFlat: const Money(5000),
    );
  }

  Future<(PlanDeclaration, OperationalZone, OperationalZone, ShiftProjectionService,
      InMemoryPlanDeclarationRepository)> makeSetup({
    List<DayOfWeek>? days,
    String departure = '06:30',
    String arrival = '07:00',
  }) async {
    final origin = makeZone(name: 'Origem');
    final dest = makeZone(name: 'Destino', lat: -23.56, lng: -46.64);

    final zoneRepo = InMemoryOperationalZoneRepository();
    await zoneRepo.save(origin);
    await zoneRepo.save(dest);

    final pattern = ShiftPattern.create(
      index: 0,
      daysOfWeek: days ?? [DayOfWeek.monday, DayOfWeek.tuesday, DayOfWeek.wednesday,
                           DayOfWeek.thursday, DayOfWeek.friday],
      arrivalTimeLocal: arrival,
      departureTimeLocal: departure,
      timezone: 'America/Sao_Paulo',
      originZoneId: origin.id,
      destinationZoneId: dest.id,
      penalties: makePenalties(),
    );

    final plan = PlanDeclaration.createWithShiftPatterns(
      organizationId: orgId,
      contractId: contractId,
      declaredAtUtc: DateTime.utc(2026, 3, 1),
      declaredByUserId: 'user-1',
      planVersion: 1,
      originalFileHash: 'abc123',
      ruleSnapshot: const RuleSnapshot([]),
      shiftPatterns: [pattern],
    );

    final planRepo = InMemoryPlanDeclarationRepository();
    await planRepo.save(plan);

    final alertRepo = InMemoryOperationalAlertRepository();

    final service = ShiftProjectionService(
      planRepo: planRepo,
      zoneRepo: zoneRepo,
      alertRepo: alertRepo,
    );

    return (plan, origin, dest, service, planRepo);
  }

  // ── Tests ────────────────────────────────────────────────

  group('ShiftProjectionService', () {
    test('5.1 — projectDays returns empty list for non-shift-based plan', () async {
      final manualPlan = PlanDeclaration.create(
        organizationId: orgId,
        contractId: contractId,
        declaredAtUtc: DateTime.utc(2026, 3, 1),
        declaredByUserId: 'user-1',
        planVersion: 1,
        originalFileHash: 'abc',
        ruleSnapshot: const RuleSnapshot([]),
        services: [
          ContractualServiceExecution.create(
            contractId: contractId,
            scheduledStartTimeUtc: DateTime.utc(2026, 3, 9, 9, 0),
            scheduledEndTimeUtc: DateTime.utc(2026, 3, 9, 10, 0),
            startLatitude: -23.5505,
            startLongitude: -46.6333,
            startRadiusMeters: 200,
            endLatitude: -23.56,
            endLongitude: -46.64,
            endRadiusMeters: 200,
            contractualValue: const Money(15000),
            noShowPenaltyMultiplier: 1.5,
          ),
        ],
      );

      final service = ShiftProjectionService(
        planRepo: InMemoryPlanDeclarationRepository(),
        zoneRepo: InMemoryOperationalZoneRepository(),
        alertRepo: InMemoryOperationalAlertRepository(),
      );

      final sets = await service.projectDays(
        manualPlan,
        from: monday,
        contractualValue: const Money(15000),
      );

      expect(sets, isEmpty);
    });

    test('5.2 — projectDays generates a SET for each matching weekday', () async {
      final (plan, _, _, service, planRepo) = await makeSetup(
        days: [DayOfWeek.monday, DayOfWeek.wednesday, DayOfWeek.friday],
      );

      // 7 days from Monday: Mon 09, Tue 10, Wed 11, Thu 12, Fri 13, Sat 14, Sun 15
      final sets = await service.projectDays(
        plan,
        from: monday,
        contractualValue: const Money(15000),
        days: 7,
      );

      // Should generate Mon, Wed, Fri = 3 SETs
      expect(sets.length, 3);

      // All SETs are projected
      expect(sets.every((s) => s.isProjected), isTrue);

      // All SETs have the correct shiftPatternIndex
      expect(sets.every((s) => s.shiftPatternIndex == 0), isTrue);
    });

    test('5.3 — determinism: same plan + pattern + date → same setId', () async {
      final (plan, _, _, service, _) = await makeSetup();

      final sets1 = await service.projectDays(
        plan,
        from: monday,
        contractualValue: const Money(15000),
        days: 1,
      );
      final sets2 = await service.projectDays(
        plan,
        from: monday,
        contractualValue: const Money(15000),
        days: 1,
      );

      expect(sets1.length, 1);
      expect(sets2.length, 1);
      expect(sets1.first.setId, equals(sets2.first.setId));
    });

    test('5.4 — idempotency: saveProjectedSets twice does not duplicate', () async {
      final (plan, _, _, service, planRepo) = await makeSetup();

      final sets = await service.projectDays(
        plan,
        from: monday,
        contractualValue: const Money(15000),
        days: 1,
      );

      await planRepo.saveProjectedSets(plan.id, sets);
      await planRepo.saveProjectedSets(plan.id, sets); // second save

      final stored = planRepo.projectedSetsFor(plan.id);
      expect(stored.length, 1); // no duplicates
    });

    test('5.5 — zone coordinate snapshot: zone update after projection does not affect existing SET', () async {
      final origin = makeZone(name: 'Origem', lat: -23.5505, lng: -46.6333);
      final dest = makeZone(name: 'Destino', lat: -23.56, lng: -46.64);

      final zoneRepo = InMemoryOperationalZoneRepository();
      await zoneRepo.save(origin);
      await zoneRepo.save(dest);

      final pattern = ShiftPattern.create(
        index: 0,
        daysOfWeek: [DayOfWeek.monday],
        arrivalTimeLocal: '07:00',
        departureTimeLocal: '06:30',
        timezone: 'America/Sao_Paulo',
        originZoneId: origin.id,
        destinationZoneId: dest.id,
        penalties: makePenalties(),
      );

      final plan = PlanDeclaration.createWithShiftPatterns(
        organizationId: orgId,
        contractId: contractId,
        declaredAtUtc: DateTime.utc(2026, 3, 1),
        declaredByUserId: 'user-1',
        planVersion: 2,
        originalFileHash: 'abc456',
        ruleSnapshot: const RuleSnapshot([]),
        shiftPatterns: [pattern],
      );

      final service = ShiftProjectionService(
        planRepo: InMemoryPlanDeclarationRepository(),
        zoneRepo: zoneRepo,
        alertRepo: InMemoryOperationalAlertRepository(),
      );

      final sets = await service.projectDays(
        plan,
        from: monday,
        contractualValue: const Money(15000),
        days: 1,
      );

      expect(sets.length, 1);
      final originalLat = sets.first.startLatitude;

      // "Update" zone by saving a new version — but SET already snapshotted
      final updatedOrigin = OperationalZone.reconstitute(
        id: origin.id,
        organizationId: origin.organizationId,
        name: origin.name,
        type: origin.type,
        geofence: GeofenceConfiguration(
          latitude: 99.0, // different lat
          longitude: origin.geofence!.longitude,
          radiusMeters: origin.geofence!.radiusMeters,
        ),
      );
      await zoneRepo.save(updatedOrigin);

      // Original SET keeps old coordinates
      expect(sets.first.startLatitude, equals(originalLat));
      expect(sets.first.startLatitude, isNot(99.0));
    });

    test('5.6 — SLA penalties are snapshotted onto projected SET', () async {
      final (plan, _, _, service, _) = await makeSetup();

      final sets = await service.projectDays(
        plan,
        from: monday,
        contractualValue: const Money(15000),
        days: 1,
      );

      expect(sets.length, 1);
      final set = sets.first;
      expect(set.delayToleranceMinutes, equals(10));
      expect(set.delayPenaltyPerMinute?.cents, equals(100));
      expect(set.downgradePenaltyFlat?.cents, equals(5000));
      expect(set.noShowPenaltyMultiplier, equals(1.5));
    });

    test('5.7 — detectAndAlertGaps raises PROJECTION_GAP for each past missing day', () async {
      final origin = makeZone(name: 'GapOrigin');
      final dest = makeZone(name: 'GapDest', lat: -23.56, lng: -46.64);

      final zoneRepo = InMemoryOperationalZoneRepository();
      await zoneRepo.save(origin);
      await zoneRepo.save(dest);

      final pattern = ShiftPattern.create(
        index: 0,
        daysOfWeek: [DayOfWeek.monday], // only Mondays
        arrivalTimeLocal: '07:00',
        departureTimeLocal: '06:30',
        timezone: 'America/Sao_Paulo',
        originZoneId: origin.id,
        destinationZoneId: dest.id,
        penalties: makePenalties(),
      );

      final plan = PlanDeclaration.createWithShiftPatterns(
        organizationId: orgId,
        contractId: contractId,
        declaredAtUtc: DateTime.utc(2026, 2, 1),
        declaredByUserId: 'user-1',
        planVersion: 3,
        originalFileHash: 'gaphash',
        ruleSnapshot: const RuleSnapshot([]),
        shiftPatterns: [pattern],
      );

      final alertRepo = InMemoryOperationalAlertRepository();

      final service = ShiftProjectionService(
        planRepo: InMemoryPlanDeclarationRepository(),
        zoneRepo: zoneRepo,
        alertRepo: alertRepo,
      );

      // asOf = Wednesday 2026-03-11 — last Monday was 2026-03-09 (yesterday)
      final asOf = DateTime.utc(2026, 3, 11);
      await service.detectAndAlertGaps(plan, asOf: asOf);

      final alerts = await alertRepo.findActive(orgId);
      expect(alerts, isNotEmpty);
      expect(alerts.every((a) => a.alertType == 'PROJECTION_GAP'), isTrue);
      expect(alerts.every((a) => a.severity == 'CRITICAL'), isTrue);
      expect(alerts.every((a) => a.contractId == contractId), isTrue);
    });

    test('5.8 — detectAndAlertGaps is idempotent (no duplicate alerts)', () async {
      final (plan, _, _, service, _) = await makeSetup(
        days: [DayOfWeek.monday],
      );

      final asOf = DateTime.utc(2026, 3, 11); // Wednesday, so Monday is a gap

      // Fetch alert repo from service internals via the builder closure trick:
      // We rebuild with a shared alertRepo to inspect it.
      final alertRepo = InMemoryOperationalAlertRepository();
      final service2 = ShiftProjectionService(
        planRepo: InMemoryPlanDeclarationRepository(),
        zoneRepo: InMemoryOperationalZoneRepository(),
        alertRepo: alertRepo,
      );

      // Need zones in the repo for gap detection (only needs setId — no zone lookup)
      await service2.detectAndAlertGaps(plan, asOf: asOf);
      await service2.detectAndAlertGaps(plan, asOf: asOf); // second run

      final alerts = await alertRepo.findActive(orgId);
      // Deduplication: each missing Monday should only have 1 alert
      final entityIds = alerts.map((a) => a.entityId).toList();
      expect(entityIds.toSet().length, equals(entityIds.length));
    });

    test('5.9 — skip days when zone not found returns null (no crash)', () async {
      final pattern = ShiftPattern.create(
        index: 0,
        daysOfWeek: [DayOfWeek.monday],
        arrivalTimeLocal: '07:00',
        departureTimeLocal: '06:30',
        timezone: 'America/Sao_Paulo',
        originZoneId: 'nonexistent-zone-id',
        destinationZoneId: 'another-nonexistent-zone-id',
        penalties: makePenalties(),
      );

      final plan = PlanDeclaration.createWithShiftPatterns(
        organizationId: orgId,
        contractId: contractId,
        declaredAtUtc: DateTime.utc(2026, 3, 1),
        declaredByUserId: 'user-1',
        planVersion: 4,
        originalFileHash: 'notfoundhash',
        ruleSnapshot: const RuleSnapshot([]),
        shiftPatterns: [pattern],
      );

      final service = ShiftProjectionService(
        planRepo: InMemoryPlanDeclarationRepository(),
        zoneRepo: InMemoryOperationalZoneRepository(), // empty — zones not found
        alertRepo: InMemoryOperationalAlertRepository(),
      );

      final sets = await service.projectDays(
        plan,
        from: monday,
        contractualValue: const Money(15000),
        days: 1,
      );

      // Zone not found → _projectOneSet returns null → skip gracefully
      expect(sets, isEmpty);
    });

    test('5.10 — overnight shift: isOvernight is true when departure > arrival', () {
      final pattern = ShiftPattern.create(
        index: 0,
        daysOfWeek: [DayOfWeek.monday],
        departureTimeLocal: '22:00',
        arrivalTimeLocal: '02:00',
        timezone: 'America/Sao_Paulo',
        originZoneId: 'z1',
        destinationZoneId: 'z2',
        penalties: makePenalties(),
      );

      expect(pattern.isOvernight, isTrue);
    });

    test('5.11 — daytime shift: isOvernight is false when departure < arrival', () {
      final pattern = ShiftPattern.create(
        index: 0,
        daysOfWeek: [DayOfWeek.monday],
        departureTimeLocal: '06:30',
        arrivalTimeLocal: '07:00',
        timezone: 'America/Sao_Paulo',
        originZoneId: 'z1',
        destinationZoneId: 'z2',
        penalties: makePenalties(),
      );

      expect(pattern.isOvernight, isFalse);
    });

    test('5.12 — zero-duration shift throws DomainException', () {
      expect(
        () => ShiftPattern.create(
          index: 0,
          daysOfWeek: [DayOfWeek.monday],
          departureTimeLocal: '08:00',
          arrivalTimeLocal: '08:00',
          timezone: 'America/Sao_Paulo',
          originZoneId: 'z1',
          destinationZoneId: 'z2',
          penalties: makePenalties(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('5.14 — SLAPenalties: new fields have correct defaults and survive JSON roundtrip', () {
      // Backward compat: existing call sites without new fields still work
      final penalties = SLAPenalties.create(
        noShowPenaltyMultiplier: 1.5,
        delayToleranceMinutes: 10,
        delayPenaltyPerMinute: const Money(100),
        downgradePenaltyFlat: const Money(5000),
      );

      expect(penalties.noShowThresholdMinutes, 60);
      expect(penalties.earlyArrivalToleranceMinutes, 5);
      expect(penalties.dwellTimeMinutes, 3);

      // toJson includes all 7 fields
      final json = penalties.toJson();
      expect(json['noShowThresholdMinutes'], 60);
      expect(json['earlyArrivalToleranceMinutes'], 5);
      expect(json['dwellTimeMinutes'], 3);

      // fromJson roundtrip preserves values
      final restored = SLAPenalties.fromJson(json);
      expect(restored, equals(penalties));

      // fromJson backward compat: old JSON without new fields falls back to defaults
      final oldJson = {
        'noShowPenaltyMultiplier': 1.5,
        'delayToleranceMinutes': 10,
        'delayPenaltyPerMinuteCents': 100,
        'downgradePenaltyFlatCents': 5000,
        // new fields absent — should default
      };
      final restoredOld = SLAPenalties.fromJson(oldJson);
      expect(restoredOld.noShowThresholdMinutes, 60);
      expect(restoredOld.earlyArrivalToleranceMinutes, 5);
      expect(restoredOld.dwellTimeMinutes, 3);

      // Custom values are stored and restored correctly
      final custom = SLAPenalties.create(
        noShowPenaltyMultiplier: 2.0,
        delayToleranceMinutes: 15,
        delayPenaltyPerMinute: const Money(200),
        downgradePenaltyFlat: const Money(10000),
        noShowThresholdMinutes: 90,
        earlyArrivalToleranceMinutes: 10,
        dwellTimeMinutes: 5,
      );
      final customJson = custom.toJson();
      final customRestored = SLAPenalties.fromJson(customJson);
      expect(customRestored.noShowThresholdMinutes, 90);
      expect(customRestored.earlyArrivalToleranceMinutes, 10);
      expect(customRestored.dwellTimeMinutes, 5);
    });

    test('5.13 — overnight D+1: projected SET ends on next day in UTC', () async {
      final origin = makeZone(name: 'Origem Noturna');
      final dest = makeZone(name: 'Destino Noturno', lat: -23.56, lng: -46.64);

      final zoneRepo = InMemoryOperationalZoneRepository();
      await zoneRepo.save(origin);
      await zoneRepo.save(dest);

      // Departure 22:00, arrival 02:00 next day (America/Sao_Paulo = UTC-3)
      // Expected UTC: departure = 01:00 UTC (Mon), arrival = 05:00 UTC (Tue)
      final overnightPattern = ShiftPattern.create(
        index: 0,
        daysOfWeek: [DayOfWeek.monday],
        departureTimeLocal: '22:00',
        arrivalTimeLocal: '02:00',
        timezone: 'America/Sao_Paulo',
        originZoneId: origin.id,
        destinationZoneId: dest.id,
        penalties: makePenalties(),
      );

      final plan = PlanDeclaration.createWithShiftPatterns(
        organizationId: orgId,
        contractId: contractId,
        declaredAtUtc: DateTime.utc(2026, 3, 1),
        declaredByUserId: 'user-1',
        planVersion: 5,
        originalFileHash: 'overnight-hash',
        ruleSnapshot: const RuleSnapshot([]),
        shiftPatterns: [overnightPattern],
      );

      final service = ShiftProjectionService(
        planRepo: InMemoryPlanDeclarationRepository(),
        zoneRepo: zoneRepo,
        alertRepo: InMemoryOperationalAlertRepository(),
      );

      // Monday 2026-03-09
      final sets = await service.projectDays(
        plan,
        from: monday,
        contractualValue: const Money(15000),
        days: 1,
      );

      expect(sets.length, 1);
      final set = sets.first;

      // Start: Monday 22:00 local (UTC-3) = Monday 01:00 UTC (next calendar day)
      expect(set.scheduledStartTimeUtc.weekday, DateTime.tuesday,
          reason: 'departure UTC lands on Tuesday (UTC)');
      expect(set.scheduledStartTimeUtc.hour, 1);

      // End: Tuesday 02:00 local (UTC-3) = Tuesday 05:00 UTC
      expect(set.scheduledEndTimeUtc.weekday, DateTime.tuesday,
          reason: 'arrival must be D+1 in local time');
      expect(set.scheduledEndTimeUtc.hour, 5);

      // End must be after start
      expect(
        set.scheduledEndTimeUtc.isAfter(set.scheduledStartTimeUtc),
        isTrue,
        reason: 'D+1 arrival must be strictly after departure',
      );
    });
  });
}
