import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/shared/money.dart';

// ── Test Helpers ──────────────────────────────────────────────────────────

/// Valid constants for test fixtures.
const validContractId = 'contract-001';
final validStartTime = DateTime.utc(2026, 3, 15, 8, 0);
final validEndTime = DateTime.utc(2026, 3, 15, 9, 0);
const validStartLat = -23.5505;
const validStartLng = -46.6333;
const validEndLat = -23.5600;
const validEndLng = -46.6400;
const validRadius = 100;
const validContractualValue = Money(15000);
const validNoShowBps = 15000;

ContractualServiceExecution makeManualExecution({
  String contractId = validContractId,
  DateTime? scheduledStartTimeUtc,
  DateTime? scheduledEndTimeUtc,
  double startLatitude = validStartLat,
  double startLongitude = validStartLng,
  int startRadiusMeters = validRadius,
  double endLatitude = validEndLat,
  double endLongitude = validEndLng,
  int endRadiusMeters = validRadius,
  String? plannedVehicleId,
  Money? contractualValue,
  int noShowPenaltyBps = validNoShowBps,
}) {
  return ContractualServiceExecution.create(
    contractId: contractId,
    scheduledStartTimeUtc: scheduledStartTimeUtc ?? validStartTime,
    scheduledEndTimeUtc: scheduledEndTimeUtc ?? validEndTime,
    startLatitude: startLatitude,
    startLongitude: startLongitude,
    startRadiusMeters: startRadiusMeters,
    endLatitude: endLatitude,
    endLongitude: endLongitude,
    endRadiusMeters: endRadiusMeters,
    plannedVehicleId: plannedVehicleId,
    contractualValue: contractualValue ?? validContractualValue,
    noShowPenaltyBps: noShowPenaltyBps,
  );
}

ContractualServiceExecution makeProjectedExecution({
  String planDeclarationId = 'plan-001',
  int shiftPatternIndex = 0,
  DateTime? operationalDate,
  DateTime? scheduledStartTimeUtc,
  DateTime? scheduledEndTimeUtc,
  String originZoneId = 'zone-origin',
  double startLatitude = validStartLat,
  double startLongitude = validStartLng,
  int startRadiusMeters = validRadius,
  String destinationZoneId = 'zone-dest',
  double endLatitude = validEndLat,
  double endLongitude = validEndLng,
  int endRadiusMeters = validRadius,
  Money? contractualValue,
  int noShowPenaltyBps = validNoShowBps,
  int delayToleranceMinutes = 5,
  Money delayPenaltyPerMinute = const Money(50),
  Money downgradePenaltyFlat = const Money(5000),
  String? plannedVehicleId,
}) {
  return ContractualServiceExecution.createProjected(
    planDeclarationId: planDeclarationId,
    shiftPatternIndex: shiftPatternIndex,
    operationalDate: operationalDate ?? DateTime.utc(2026, 3, 15),
    scheduledStartTimeUtc: scheduledStartTimeUtc ?? validStartTime,
    scheduledEndTimeUtc: scheduledEndTimeUtc ?? validEndTime,
    originZoneId: originZoneId,
    startLatitude: startLatitude,
    startLongitude: startLongitude,
    startRadiusMeters: startRadiusMeters,
    destinationZoneId: destinationZoneId,
    endLatitude: endLatitude,
    endLongitude: endLongitude,
    endRadiusMeters: endRadiusMeters,
    contractualValue: contractualValue ?? validContractualValue,
    noShowPenaltyBps: noShowPenaltyBps,
    delayToleranceMinutes: delayToleranceMinutes,
    delayPenaltyPerMinute: delayPenaltyPerMinute,
    downgradePenaltyFlat: downgradePenaltyFlat,
    plannedVehicleId: plannedVehicleId,
  );
}
