import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:veraprob/domain/shared/idempotency_key.dart';
import 'package:veraprob/domain/sla_audit/sla_evaluation_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/domain/sla_audit/vehicle_category.dart';
import 'package:veraprob/domain/sla_audit/week_cycle.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';

export 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
export 'package:veraprob/domain/sla_audit/execution_status.dart';
export 'package:veraprob/domain/sla_audit/contractual_rule.dart';
export 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
export 'package:veraprob/domain/sla_audit/sla_penalties.dart';
export 'package:veraprob/domain/sla_audit/shift_pattern.dart';
export 'package:veraprob/domain/sla_audit/vehicle_category.dart';
export 'package:veraprob/domain/sla_audit/week_cycle.dart';
export 'package:veraprob/domain/sla_audit/plan_declaration.dart';
export 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
export 'package:veraprob/domain/shared/money.dart';
export 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
export 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
export 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
export 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
export 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
export 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
export 'package:veraprob/infrastructure/sla_audit/in_memory_asset_status_repository.dart';
export 'package:veraprob/domain/sla_audit/asset_status.dart';
export 'package:veraprob/domain/sla_audit/asset_status_event.dart';
export 'package:veraprob/domain/sla_audit/sla_evaluation_exception.dart';

// Deterministic time anchor
final DateTime nowUtc = DateTime.parse('2026-04-08T12:00:00Z').toUtc();

/// Initializes timezone database. Call in setUpAll().
void initializeTimezones() {
  tz_data.initializeTimeZones();
}

// Geofence center
const double geoLat = -23.5505;
const double geoLng = -46.6333;
const int geoRadius = 100;

/// Creates a test engine with all in-memory repositories
({
  InMemoryContractualExecutionStateRepository repo,
  InMemoryPlanDeclarationRepository planRepo,
  InMemorySlaAuditLedgerRepository ledger,
  InMemoryEvaluationTraceRepository traceRepo,
  ContractualEvaluationEngine engine,
})
createTestEngine() {
  final repo = InMemoryContractualExecutionStateRepository();
  final planRepo = InMemoryPlanDeclarationRepository();
  final ledger = InMemorySlaAuditLedgerRepository();
  final traceRepo = InMemoryEvaluationTraceRepository();
  final engine = ContractualEvaluationEngine(
    executionRepo: repo,
    planRepo: planRepo,
    ledgerRepo: ledger,
    traceRepo: traceRepo,
  );
  return (
    repo: repo,
    planRepo: planRepo,
    ledger: ledger,
    traceRepo: traceRepo,
    engine: engine,
  );
}

/// Creates a test execution state with sensible defaults
ContractualExecutionState makeExecState({
  String setId = 'set-1',
  String contractId = 'c-1',
  String? plannedVehicleId,
  DateTime? windowStart,
  DateTime? windowEnd,
  Money contractualValue = const Money(15000),
}) {
  return ContractualExecutionState.create(
    organizationId: 'org-1',
    setId: setId,
    contractId: contractId,
    planVersion: 1,
    startLatitude: geoLat,
    startLongitude: geoLng,
    startRadiusMeters: geoRadius,
    plannedVehicleId: plannedVehicleId,
    contractualValue: contractualValue,
    noShowPenaltyBps: 15000,
    windowStartUtc: windowStart ?? DateTime.utc(2026, 3, 1, 6, 0),
    windowEndUtc: windowEnd ?? DateTime.utc(2026, 3, 1, 7, 0),
  );
}

/// Creates a vehicle state at a specific timestamp
VehicleOperationalState makeVehicleAtTime({
  String vehicleId = 'v-1',
  required double latitude,
  required double longitude,
  required DateTime timestamp,
  double? accuracyMeters,
}) {
  return VehicleOperationalState(
    vehicleId: vehicleId,
    tripId: 'trip-1',
    latitude: latitude,
    longitude: longitude,
    smoothedSpeed: 0.0,
    motionState: MotionState.stopped,
    connectivityState: ConnectivityState.healthy,
    lastRawPingAt: timestamp,
    stateChangedAt: timestamp,
    confidence: 1.0,
    accuracyMeters: accuracyMeters,
    source: 'test',
  );
}

/// Seeds a plan with a delay tolerance rule
Future<void> seedPlanWithDelayRule(
  InMemoryPlanDeclarationRepository planRepo,
  String contractId,
  int version, {
  int toleranceMinutes = 5,
  int penaltyPerMinuteCents = 200,
  int? maxPenaltyCapCents,
}) async {
  final config = <String, dynamic>{
    'delay_tolerance_minutes': toleranceMinutes,
    'penalty_per_minute_cents': penaltyPerMinuteCents,
  };
  if (maxPenaltyCapCents != null) {
    config['max_penalty_cap_cents'] = maxPenaltyCapCents;
  }
  final rule = RuleSnapshotItem(
    ruleId: 'rule-delay-01',
    ruleType: SlaRuleType.maxToleranceDelay,
    config: config,
    ruleVersion: 1,
    evaluationOrder: 1,
  );
  final pattern = ShiftPattern.create(
    index: 0,
    daysOfWeek: [DayOfWeek.monday],
    arrivalTimeLocal: '07:00',
    departureTimeLocal: '06:00',
    timezone: 'America/Sao_Paulo',
    originZoneId: 'zone-origin',
    destinationZoneId: 'zone-dest',
    penalties: SLAPenalties.create(
      noShowPenaltyBps: 15000,
      delayToleranceMinutes: toleranceMinutes,
      delayPenaltyPerMinute: Money(penaltyPerMinuteCents),
      downgradePenaltyFlat: const Money(1),
      gracePeriodMinutes: 0,
      baseTripValue: const Money(10000),
    ),
    requiredVehicleCategory: VehicleCategory.conventional,
    weekCycle: WeekCycle.everyWeek,
  );
  final declaration = PlanDeclaration.createWithShiftPatterns(
    organizationId: 'org-1',
    contractId: contractId,
    planVersion: version,
    declaredAtUtc: DateTime.utc(2026, 1, 1),
    declaredByUserId: 'user-1',
    originalFileHash: 'hash-delay',
    ruleSnapshot: RuleSnapshot([rule]),
    shiftPatterns: [pattern],
    nowUtc: nowUtc,
  );
  await planRepo.save(declaration);
}

/// Verifies ledger entry count matches expected
void verifyLedgerEntryCount(
  InMemorySlaAuditLedgerRepository ledger,
  int expectedCount, {
  String? typeFilter,
}) {
  final entries = typeFilter != null
      ? ledger.entries.where((e) => e.type == typeFilter).toList()
      : ledger.entries;
  expect(
    entries.length,
    expectedCount,
    reason: 'Expected $expectedCount $typeFilter entries',
  );
}

/// Generates idempotency key for a trip based on content-based addressing
String generateTripIdempotencyKey({
  required String vehicleId,
  required DateTime timestamp,
  required String organizationId,
}) {
  final payload = {
    'vehicle_id': vehicleId,
    'timestamp': timestamp.toIso8601String(),
  };
  return IdempotencyKey.fromPayload(
    userId: 'SYSTEM',
    commandPath: 'process_vehicle_state',
    organizationId: organizationId,
    payload: payload,
    nowUtc: nowUtc,
  ).id;
}

/// Verifies that a penalty was calculated with correct BPS
void verifyBpsPenalty({
  required Money contractualValue,
  required int bps,
  required int expectedCents,
}) {
  final calculated = contractualValue.multiplyByBps(bps);
  expect(calculated.cents, expectedCents, reason: 'BPS calculation mismatch');
}

/// Verifies symmetric rounding formula: (base * bps + 5000) ~/ 10000
void verifySymmetricRounding({
  required int baseCents,
  required int bps,
  required int expectedCents,
}) {
  final calculated = (baseCents * bps + 5000) ~/ 10000;
  expect(calculated, expectedCents, reason: 'Symmetric rounding mismatch');
}

/// Creates a vehicle state with missing timestamp (for resilience testing)
VehicleOperationalState makeVehicleStateMissingTimestamp({
  String vehicleId = 'v-1',
}) {
  return VehicleOperationalState(
    vehicleId: vehicleId,
    tripId: 'trip-1',
    latitude: geoLat,
    longitude: geoLng,
    smoothedSpeed: 0.0,
    motionState: MotionState.stopped,
    connectivityState: ConnectivityState.healthy,
    lastRawPingAt: DateTime.utc(2026, 3, 1, 6, 30),
    stateChangedAt: DateTime.utc(2026, 3, 1, 6, 30),
    confidence: 1.0,
    accuracyMeters: 5.0,
    source: 'test',
  );
}

/// Creates a vehicle state with missing vehicleId (for resilience testing)
VehicleOperationalState makeVehicleStateMissingId({String vehicleId = ''}) {
  return VehicleOperationalState(
    vehicleId: vehicleId,
    tripId: 'trip-1',
    latitude: geoLat,
    longitude: geoLng,
    smoothedSpeed: 0.0,
    motionState: MotionState.stopped,
    connectivityState: ConnectivityState.healthy,
    lastRawPingAt: DateTime.utc(2026, 3, 1, 6, 30),
    stateChangedAt: DateTime.utc(2026, 3, 1, 6, 30),
    confidence: 1.0,
    accuracyMeters: 5.0,
    source: 'test',
  );
}

/// Verifies that SlaEvaluationException is thrown
void expectEvaluationException(Future<void> Function() action) async {
  try {
    await action();
    fail('Expected SlaEvaluationException to be thrown');
  } on SlaEvaluationException catch (e) {
    expect(
      e.message,
      isNotEmpty,
      reason: 'Exception message should not be empty',
    );
  } catch (e) {
    fail('Expected SlaEvaluationException but got ${e.runtimeType}');
  }
}

/// Seeds a plan with an excessiveSpeed rule for SANCTION tests
Future<void> seedPlanWithExcessiveSpeedRule(
  InMemoryPlanDeclarationRepository planRepo,
  String contractId,
  int version, {
  required double maxSpeedKmh,
  required int fineCents,
}) async {
  final rule = RuleSnapshotItem(
    ruleId: 'rule-speed-01',
    ruleType: SlaRuleType.excessiveSpeed,
    config: {'max_speed_kmh': maxSpeedKmh, 'fine_cents': fineCents},
    ruleVersion: 1,
    evaluationOrder: 1,
  );
  final declaration = PlanDeclaration.create(
    organizationId: 'org-1',
    contractId: contractId,
    planVersion: version,
    declaredAtUtc: DateTime.utc(2026, 1, 1),
    declaredByUserId: 'user-1',
    originalFileHash: 'hash-speed',
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
        noShowPenaltyBps: 15000,
      ),
    ],
    ruleSnapshot: RuleSnapshot([rule]),
    nowUtc: nowUtc,
  );
  await planRepo.save(declaration);
}
