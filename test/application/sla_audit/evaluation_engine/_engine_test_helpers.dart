import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/domain/sla_audit/vehicle_category.dart';
import 'package:veraprob/domain/sla_audit/week_cycle.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/domain/shared/money.dart';

// Re-export types that test files need for assertions/construction
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
export 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
export 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
export 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
export 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';

// ── Deterministic time anchor (INV-9) ──────────────────────
final DateTime nowUtc = DateTime.parse('2026-04-08T12:00:00Z').toUtc();

// ── Geofence center ────────────────────────────────────────
const double geoLat = -23.5505;
const double geoLng = -46.6333;
const int geoRadius = 100;

/// Initializes timezone database. Call in setUpAll().
void initializeTimezones() {
  tz_data.initializeTimeZones();
}

/// Provisions a standard set of in-memory repositories and engine.
/// Returns a record containing all instances for easy destructuring.
({
  InMemoryContractualExecutionStateRepository repo,
  InMemoryPlanDeclarationRepository planRepo,
  InMemorySlaAuditLedgerRepository ledger,
  InMemoryEvaluationTraceRepository traceRepo,
  ContractualEvaluationEngine engine,
}) createEngine() {
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

/// Creates a [ContractualExecutionState] with sensible defaults.
/// All financial values remain as int (cents) per INV-2.
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

/// Seeds a basic plan declaration with an empty rule snapshot.
Future<void> seedPlan(
  InMemoryPlanDeclarationRepository planRepo,
  String contractId,
  int version,
) async {
  final declaration = PlanDeclaration.create(
    organizationId: 'org-1',
    contractId: contractId,
    planVersion: version,
    declaredAtUtc: DateTime.utc(2026, 1, 1),
    declaredByUserId: 'user-1',
    originalFileHash: 'hash-1',
    services: [
      ContractualServiceExecution.create(
        contractId: contractId,
        scheduledStartTimeUtc: DateTime.utc(2026, 3, 1, 6, 0),
        scheduledEndTimeUtc: DateTime.utc(2026, 3, 1, 7, 0),
        startLatitude: -23.5505,
        startLongitude: -46.6333,
        startRadiusMeters: 100,
        endLatitude: -23.5600,
        endLongitude: -46.6400,
        endRadiusMeters: 100,
        contractualValue: const Money(15000),
        noShowPenaltyBps: 15000,
      ),
    ],
    ruleSnapshot: const RuleSnapshot([]),
    nowUtc: nowUtc,
  );
  await planRepo.save(declaration);
}

/// Seeds a plan declaration with specific [RuleSnapshotItem] rules.
Future<void> seedPlanWithRules(
  InMemoryPlanDeclarationRepository planRepo,
  String contractId,
  int version,
  List<RuleSnapshotItem> rules,
) async {
  final declaration = PlanDeclaration.create(
    organizationId: 'org-1',
    contractId: contractId,
    planVersion: version,
    declaredAtUtc: DateTime.utc(2026, 1, 1),
    declaredByUserId: 'user-1',
    originalFileHash: 'hash-rules',
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
    ruleSnapshot: RuleSnapshot(rules),
    nowUtc: nowUtc,
  );
  await planRepo.save(declaration);
}

/// Seeds a plan with a [ShiftPattern] that has [gracePeriodMinutes].
Future<void> seedPlanWithGracePeriod(
  InMemoryPlanDeclarationRepository planRepo,
  String contractId,
  int version,
  int gracePeriodMinutes,
) async {
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
      delayToleranceMinutes: 5,
      delayPenaltyPerMinute: const Money(100),
      downgradePenaltyFlat: const Money(5000),
      gracePeriodMinutes: gracePeriodMinutes,
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
    originalFileHash: 'hash-grace',
    ruleSnapshot: const RuleSnapshot([]),
    shiftPatterns: [pattern],
    nowUtc: nowUtc,
  );
  await planRepo.save(declaration);
}

/// Seeds a plan with a no-show penalty rule for SANCTION tests.
Future<void> seedPlanWithPenaltyRule(
  InMemoryPlanDeclarationRepository planRepo,
  String contractId,
  int version, {
  int penaltyCents = 150000,
}) async {
  final rule = RuleSnapshotItem(
    ruleId: 'rule-no-show-01',
    ruleType: SlaRuleType.noShowPenalty,
    config: {'penalty_amount_cents': penaltyCents},
    ruleVersion: 1,
    evaluationOrder: 1,
  );
  final declaration = PlanDeclaration.create(
    organizationId: 'org-1',
    contractId: contractId,
    planVersion: version,
    declaredAtUtc: DateTime.utc(2026, 1, 1),
    declaredByUserId: 'user-1',
    originalFileHash: 'hash-penalty',
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

/// Creates a [VehicleOperationalState] with sensible defaults.
/// Uses DateTime.utc() per INV-9.
VehicleOperationalState makeVehicleState({
  String vehicleId = 'v-1',
  double latitude = geoLat,
  double longitude = geoLng,
}) {
  return VehicleOperationalState(
    vehicleId: vehicleId,
    tripId: 'trip-1',
    latitude: latitude,
    longitude: longitude,
    smoothedSpeed: 0.0,
    motionState: MotionState.stopped,
    connectivityState: ConnectivityState.healthy,
    lastRawPingAt: DateTime.utc(2026, 3, 1, 6, 30),
    stateChangedAt: DateTime.utc(2026, 3, 1, 6, 30),
    confidence: 1.0,
    source: 'test',
  );
}
