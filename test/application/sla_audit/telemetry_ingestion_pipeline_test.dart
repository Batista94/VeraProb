import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:veraprob/application/sla_audit/telemetry_ingestion_pipeline.dart';
import 'package:veraprob/domain/sla_audit/asset_status.dart';
import 'package:veraprob/domain/sla_audit/asset_status_event.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_asset_status_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  // ── Geofence: São Paulo downtown ──────────────────────────────────────────
  const geoLat = -23.5505;
  const geoLng = -46.6333;
  const geoRadius = 100; // meters

  // Coords that are clearly inside the geofence (same point)
  const insideLat = geoLat;
  const insideLng = geoLng;

  late InMemoryContractualExecutionStateRepository execRepo;
  late InMemoryPlanDeclarationRepository planRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late InMemoryAssetStatusRepository statusRepo;
  late ContractualEvaluationEngine engine;
  late TelemetryIngestionPipeline pipeline;

  setUp(() {
    execRepo = InMemoryContractualExecutionStateRepository();
    planRepo = InMemoryPlanDeclarationRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    statusRepo = InMemoryAssetStatusRepository();
    final traceRepo = InMemoryEvaluationTraceRepository();

    engine = ContractualEvaluationEngine(
      executionRepo: execRepo,
      planRepo: planRepo,
      ledgerRepo: ledger,
      traceRepo: traceRepo,
    );

    pipeline = TelemetryIngestionPipeline(
      engine: engine,
      assetStatusRepo: statusRepo,
    );
  });

  // ── Helpers ────────────────────────────────────────────────────────────────

  CanonicalFact makeFact({
    String orgId = 'org-1',
    String assetId = 'asset-1',
    String deviceId = 'DEV-001',
    required DateTime gpsTimestamp,
    double lat = insideLat,
    double lng = insideLng,
    int? speedCms = 0,
    IngestionIntegrityFlag flag = IngestionIntegrityFlag.ok,
    DateTime? receivedAtUtc,
  }) {
    return CanonicalFact.create(
      organizationId: orgId,
      rawPayloadId: 'raw-1',
      assetId: assetId,
      deviceId: deviceId,
      sourceAdapter: 'SASCAR_V1',
      receivedAtUtc: receivedAtUtc ?? gpsTimestamp,
      gpsTimestamp: gpsTimestamp,
      lat: lat,
      lng: lng,
      speedCms: speedCms,
      integrityFlag: flag,
    );
  }

  ContractualExecutionState makeExecState({
    String setId = 'set-1',
    String contractId = 'c-1',
    DateTime? windowStart,
    DateTime? windowEnd,
  }) {
    return ContractualExecutionState.create(
      organizationId: 'org-1',
      setId: setId,
      contractId: contractId,
      planVersion: 1,
      startLatitude: geoLat,
      startLongitude: geoLng,
      startRadiusMeters: geoRadius,
      contractualValue: const Money(15000),
      noShowPenaltyMultiplier: 1.5,
      windowStartUtc: windowStart ?? DateTime.utc(2026, 3, 1, 6, 0),
      windowEndUtc: windowEnd ?? DateTime.utc(2026, 3, 1, 7, 0),
    );
  }

  Future<void> seedPlan(String contractId) async {
    final plan = PlanDeclaration.create(
      organizationId: 'org-1',
      contractId: contractId,
      planVersion: 1,
      declaredAtUtc: DateTime.utc(2026, 1, 1),
      declaredByUserId: 'user-1',
      originalFileHash: 'hash-1',
      services: [
        ContractualServiceExecution.create(
          contractId: contractId,
          scheduledStartTimeUtc: DateTime.utc(2026, 3, 1, 6, 0),
          scheduledEndTimeUtc: DateTime.utc(2026, 3, 1, 7, 0),
          startLatitude: geoLat,
          startLongitude: geoLng,
          startRadiusMeters: geoRadius,
          endLatitude: -23.5600,
          endLongitude: -46.6400,
          endRadiusMeters: 100,
          contractualValue: const Money(15000),
          noShowPenaltyMultiplier: 1.5,
        ),
      ],
      ruleSnapshot: const RuleSnapshot([]),
    );
    await planRepo.save(plan);
  }

  // ── 6.5.2: Chronological ordering ─────────────────────────────────────────
  group('6.5.2 — Chronological Chaos Tolerance', () {
    test('facts arrive out-of-order but are processed chronologically', () async {
      final state = makeExecState(
        windowStart: DateTime.utc(2026, 3, 1, 6, 0),
        windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
      );
      await execRepo.save(state);
      await seedPlan('c-1');

      // Deliberately submit facts out of arrival order
      final t1 = DateTime.utc(2026, 3, 1, 6, 0, 30); // inside window
      final t2 = DateTime.utc(2026, 3, 1, 6, 0, 10); // earlier, inside window
      final t3 = DateTime.utc(2026, 3, 1, 6, 0, 50); // latest, inside window

      final facts = [
        makeFact(gpsTimestamp: t3), // arrives first but latest GPS time
        makeFact(gpsTimestamp: t1),
        makeFact(gpsTimestamp: t2), // earliest GPS, arrives last
      ];

      final result = await pipeline.process(facts, organizationId: 'org-1');

      // All 3 are at the same position (inside geofence) — pipeline processes OK
      expect(result.totalReceived, 3);
      expect(result.skippedByIntegrityFlag, 0);
      expect(result.skippedByKinematicJump, 0);
    });

    test('late arrival facts (gpsTimestamp 4h before received) are processed', () async {
      final state = makeExecState(
        windowStart: DateTime.utc(2026, 3, 1, 6, 0),
        windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
      );
      await execRepo.save(state);
      await seedPlan('c-1');

      final gpsTime = DateTime.utc(2026, 3, 1, 6, 30); // inside window
      final arrivedAt = DateTime.utc(2026, 3, 1, 10, 30); // 4h later

      final lateFact = makeFact(
        gpsTimestamp: gpsTime,
        receivedAtUtc: arrivedAt,
        flag: IngestionIntegrityFlag.lateArrival,
      );

      final result = await pipeline.process([lateFact], organizationId: 'org-1');

      expect(result.processed, 1); // lateArrival is eligible
      expect(result.lateArrivalCount, 1);
      expect(result.lateArrivalAssetIds, contains('asset-1'));
    });

    test('futureTimestamp facts are skipped', () async {
      final futureFact = makeFact(
        gpsTimestamp: DateTime.utc(2026, 3, 1, 6, 0),
        flag: IngestionIntegrityFlag.futureTimestamp,
      );

      final result = await pipeline.process([futureFact], organizationId: 'org-1');

      expect(result.processed, 0);
      expect(result.skippedByIntegrityFlag, 1);
    });

    test('nullIsland facts are skipped', () async {
      final nullIslandFact = makeFact(
        gpsTimestamp: DateTime.utc(2026, 3, 1, 6, 0),
        lat: 0.0,
        lng: 0.0,
        flag: IngestionIntegrityFlag.nullIsland,
      );

      final result = await pipeline.process([nullIslandFact], organizationId: 'org-1');

      expect(result.processed, 0);
      expect(result.skippedByIntegrityFlag, 1);
    });

    test('result totals: processed + skipped = totalReceived', () async {
      final facts = [
        makeFact(gpsTimestamp: DateTime.utc(2026, 3, 1, 6, 0)),
        makeFact(
          gpsTimestamp: DateTime.utc(2026, 3, 1, 6, 1),
          flag: IngestionIntegrityFlag.futureTimestamp,
        ),
        makeFact(
          gpsTimestamp: DateTime.utc(2026, 3, 1, 6, 2),
          flag: IngestionIntegrityFlag.nullIsland,
          lat: 0.0,
          lng: 0.0,
        ),
      ];

      final result = await pipeline.process(facts, organizationId: 'org-1');

      expect(result.totalReceived, 3);
      expect(
        result.processed +
            result.skippedByIntegrityFlag +
            result.skippedByKinematicJump +
            result.skippedByAssetStatus,
        3,
      );
    });
  });

  // ── 6.5.3: Asset State Machine ─────────────────────────────────────────────
  group('6.5.3 — Asset State Machine', () {
    test('MAINTENANCE asset: facts are skipped, zero SLA penalties', () async {
      // Put asset into maintenance
      await statusRepo.append(
        AssetStatusEvent.create(
          organizationId: 'org-1',
          assetId: 'asset-1',
          newStatus: AssetStatus.maintenance,
          previousStatus: AssetStatus.active,
          occurredAtUtc: DateTime.utc(2026, 3, 1, 5, 0),
          triggeredBy: 'dispatcher',
          reason: 'Preventive maintenance',
        ),
      );

      final state = makeExecState(
        windowStart: DateTime.utc(2026, 3, 1, 6, 0),
        windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
      );
      await execRepo.save(state);
      await seedPlan('c-1');

      // Facts arrive while vehicle is inside geofence during its window
      final facts = [
        makeFact(gpsTimestamp: DateTime.utc(2026, 3, 1, 6, 0)),
        makeFact(gpsTimestamp: DateTime.utc(2026, 3, 1, 6, 1)),
        makeFact(gpsTimestamp: DateTime.utc(2026, 3, 1, 6, 2)),
      ];

      final result = await pipeline.process(facts, organizationId: 'org-1');

      expect(result.skippedByAssetStatus, 3);
      expect(result.processed, 0);

      // Verify no verdict was written to the ledger
      expect(ledger.entries, isEmpty);
    });

    test('OFF_DUTY asset: facts are skipped', () async {
      await statusRepo.append(
        AssetStatusEvent.create(
          organizationId: 'org-1',
          assetId: 'asset-1',
          newStatus: AssetStatus.offDuty,
          previousStatus: AssetStatus.active,
          occurredAtUtc: DateTime.utc(2026, 3, 1, 0, 0),
          triggeredBy: 'SYSTEM',
        ),
      );

      final facts = [
        makeFact(gpsTimestamp: DateTime.utc(2026, 3, 1, 6, 0)),
      ];

      final result = await pipeline.process(facts, organizationId: 'org-1');

      expect(result.skippedByAssetStatus, 1);
      expect(result.processed, 0);
    });

    test('ACTIVE asset (default — no events): facts are processed normally', () async {
      // No status events — defaults to ACTIVE
      final state = makeExecState();
      await execRepo.save(state);
      await seedPlan('c-1');

      final facts = [
        makeFact(gpsTimestamp: DateTime.utc(2026, 3, 1, 6, 0)),
      ];

      final result = await pipeline.process(facts, organizationId: 'org-1');

      expect(result.skippedByAssetStatus, 0);
      expect(result.processed, 1);
    });

    test('AssetStatusEvent: throws on same-status transition', () {
      expect(
        () => AssetStatusEvent.create(
          organizationId: 'org-1',
          assetId: 'asset-1',
          newStatus: AssetStatus.active,
          previousStatus: AssetStatus.active, // same!
          occurredAtUtc: DateTime.utc(2026, 3, 1),
          triggeredBy: 'user',
        ),
        throwsA(isA()),
      );
    });

    test('AssetStatusEvent: throws on non-UTC timestamp', () {
      expect(
        () => AssetStatusEvent.create(
          organizationId: 'org-1',
          assetId: 'asset-1',
          newStatus: AssetStatus.maintenance,
          previousStatus: AssetStatus.active,
          occurredAtUtc: DateTime(2026, 3, 1), // local time!
          triggeredBy: 'user',
        ),
        throwsA(isA()),
      );
    });

    test('status history replay: last event wins', () async {
      // active → maintenance → active
      await statusRepo.append(AssetStatusEvent.create(
        organizationId: 'org-1',
        assetId: 'asset-1',
        newStatus: AssetStatus.maintenance,
        previousStatus: AssetStatus.active,
        occurredAtUtc: DateTime.utc(2026, 3, 1, 8, 0),
        triggeredBy: 'user',
      ));
      await statusRepo.append(AssetStatusEvent.create(
        organizationId: 'org-1',
        assetId: 'asset-1',
        newStatus: AssetStatus.active,
        previousStatus: AssetStatus.maintenance,
        occurredAtUtc: DateTime.utc(2026, 3, 1, 16, 0),
        triggeredBy: 'user',
        reason: 'Maintenance complete',
      ));

      final status = await statusRepo.getCurrentStatus(
        assetId: 'asset-1',
        organizationId: 'org-1',
      );

      expect(status, AssetStatus.active);
    });
  });

  // ── 6.5.4: Kinematic Noise Filter ──────────────────────────────────────────
  group('6.5.4 — Kinematic Noise Filter (sequential Haversine)', () {
    test('GPS jitter jump of ~200m is discarded, surrounding valid points pass', () async {
      // t1: valid position inside geofence
      // t2: GPS jitter — "jumps" 200m away at same speed (impossible)
      // t3: returns to valid position (proves t2 was noise, not real movement)

      final t1 = DateTime.utc(2026, 3, 1, 6, 0, 0);
      final t2 = DateTime.utc(2026, 3, 1, 6, 0, 1); // 1 second later
      final t3 = DateTime.utc(2026, 3, 1, 6, 0, 2);

      final facts = [
        makeFact(gpsTimestamp: t1, lat: insideLat, lng: insideLng),
        // Jump ~200m in 1 second = 720 km/h — physically impossible
        makeFact(
          gpsTimestamp: t2,
          lat: insideLat + 0.0018, // ~200m north
          lng: insideLng,
        ),
        makeFact(gpsTimestamp: t3, lat: insideLat, lng: insideLng),
      ];

      final result = await pipeline.process(facts, organizationId: 'org-1');

      expect(result.skippedByKinematicJump, 1); // t2 discarded
      expect(result.processed, 2); // t1 and t3 pass
    });

    test('same timestamp but displaced > 5m is discarded', () async {
      final t = DateTime.utc(2026, 3, 1, 6, 0, 0);

      final facts = [
        makeFact(gpsTimestamp: t, lat: insideLat, lng: insideLng),
        // Same timestamp, but 10m away — hardware glitch
        makeFact(
          gpsTimestamp: t,
          lat: insideLat + 0.0001, // ~11m north
          lng: insideLng,
        ),
      ];

      final result = await pipeline.process(facts, organizationId: 'org-1');

      expect(result.skippedByKinematicJump, 1);
    });

    test('normal movement at 80 km/h passes the filter', () async {
      // 80 km/h = 22.2 m/s → in 5 seconds = ~111m
      final t1 = DateTime.utc(2026, 3, 1, 6, 0, 0);
      final t2 = DateTime.utc(2026, 3, 1, 6, 0, 5); // 5s later

      final facts = [
        makeFact(gpsTimestamp: t1, lat: insideLat, lng: insideLng),
        // ~111m in 5 seconds = 80 km/h — valid
        makeFact(
          gpsTimestamp: t2,
          lat: insideLat,
          lng: insideLng + 0.001, // ~111m east
        ),
      ];

      final result = await pipeline.process(facts, organizationId: 'org-1');

      expect(result.skippedByKinematicJump, 0);
      expect(result.processed, 2);
    });

    test('different devices do not share kinematic state', () async {
      // Device A and Device B both have facts at same timestamps
      // A jump for device A should not affect device B's filter
      final t1 = DateTime.utc(2026, 3, 1, 6, 0, 0);
      final t2 = DateTime.utc(2026, 3, 1, 6, 0, 1);

      final facts = [
        // Device A: valid
        makeFact(deviceId: 'DEV-A', assetId: 'asset-a', gpsTimestamp: t1),
        // Device A: kinematic jump
        makeFact(
          deviceId: 'DEV-A',
          assetId: 'asset-a',
          gpsTimestamp: t2,
          lat: insideLat + 0.002, // ~220m in 1s = impossible
          lng: insideLng,
        ),
        // Device B: valid — should NOT be affected by Device A's state
        makeFact(deviceId: 'DEV-B', assetId: 'asset-b', gpsTimestamp: t1),
        makeFact(deviceId: 'DEV-B', assetId: 'asset-b', gpsTimestamp: t2),
      ];

      final result = await pipeline.process(facts, organizationId: 'org-1');

      expect(result.skippedByKinematicJump, 1); // only Device A's t2
      expect(result.processed, 3); // Device A t1 + Device B t1 + Device B t2
    });
  });
}
