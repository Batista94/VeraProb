import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/domain/sla_audit/operational_alert_repository.dart';
import 'package:veraprob/domain/sla_audit/operational_zone_repository.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration_repository.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/domain/sla_audit/week_cycle.dart';
import 'package:veraprob/domain/shared/money.dart';

/// Application service responsible for projecting [ContractualServiceExecution]
/// instances from [ShiftPattern] recurrence rules.
///
/// **This is NOT a second evaluation engine.** It only generates discrete SETs
/// from abstract recurrence rules. The [ContractualEvaluationEngine] then
/// evaluates those SETs against telemetry, as before.
///
/// **Projection guarantees:**
/// - Deterministic: same [ShiftPattern] + same [operationalDate] â†’ same [setId].
/// - Idempotent: the DB unique constraint
///   `(plan_declaration_id, shift_pattern_index, operational_date)` prevents
///   duplicate inserts. This service uses `upsert` semantics at the repo level.
/// - Zone coordinates snapshotted at projection time: updating an
///   [OperationalZone] after projection does NOT change existing SETs.
///
/// **Ghost Day (B4 decision):**
/// If the projection fails for a past date, that day becomes a permanent gap.
/// [detectAndAlertGaps] generates a [OperationalAlert] of type PROJECTION_GAP
/// / severity CRITICAL for each missed past date. No retroactive backfill.
class ShiftProjectionService {
  final PlanDeclarationRepository _planRepo;
  final OperationalZoneRepository _zoneRepo;
  final OperationalAlertRepository _alertRepo;
  final IDateTimeProvider _dateTimeProvider;

  /// Default projection window in days (B1 decision: 30 days).
  static const int defaultProjectionDays = 30;

  ShiftProjectionService({
    required PlanDeclarationRepository planRepo,
    required OperationalZoneRepository zoneRepo,
    required OperationalAlertRepository alertRepo,
    required IDateTimeProvider dateTimeProvider,
  }) : _planRepo = planRepo,
       _zoneRepo = zoneRepo,
       _alertRepo = alertRepo,
       _dateTimeProvider = dateTimeProvider;

  // â”€â”€ Public API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Projects SETs for [plan] from [from] for [days] days.
  ///
  /// Called by [DeclareContractualPlanHandler] immediately after a shift-based
  /// plan is declared (eager projection of the first 30 days).
  ///
  /// [contractualValue] is the base financial value per SET, derived from the
  /// contract's rule snapshot by the caller. Must be > 0.
  ///
  /// Returns the list of projected SETs. The caller is responsible for
  /// persisting them via [ContractualExecutionStateRepository] or similar.
  ///
  /// Throws if any [OperationalZone] referenced by the plan cannot be found.
  Future<List<ContractualServiceExecution>> projectDays(
    PlanDeclaration plan, {
    required DateTime from,
    required Money contractualValue,
    int days = defaultProjectionDays,
  }) async {
    if (!plan.isShiftBased) return [];

    final projected = <ContractualServiceExecution>[];

    for (var i = 0; i < days; i++) {
      final date = from.toUtc().add(Duration(days: i));
      final dateOnly = DateTime.utc(date.year, date.month, date.day);

      for (final pattern in plan.shiftPatterns) {
        if (!pattern.runsOn(dateOnly.weekday)) continue;

        // Industrial cycle filter: skip dates outside the pattern's week slot.
        if (pattern.weekCycle != WeekCycle.everyWeek) {
          final anchor = plan.cycleAnchorDateUtc;
          if (anchor == null) {
            continue; // guard â€” should not happen after validation
          }
          final daysDiff = dateOnly.difference(anchor).inDays;
          final weekIndex = ((daysDiff ~/ 7) % 4 + 4) % 4;
          if (weekIndex != pattern.weekCycle.index - 1) continue;
        }

        final set = await _projectOneSet(
          plan: plan,
          pattern: pattern,
          operationalDate: dateOnly,
          contractualValue: contractualValue,
        );
        if (set != null) projected.add(set);
      }
    }

    return projected;
  }

  /// Ensures all active shift-based plans for [organizationId] have SETs
  /// projected for the next [days] days.
  ///
  /// Called on operator login (boot check â€” B1 decision).
  /// Silently skips dates that already have projected SETs (idempotent).
  /// For past dates with missing SETs, calls [detectAndAlertGaps].
  ///
  /// [contractualValue] is provided by the caller (e.g. boot service) from the
  /// contract's rate configuration. Each plan may ultimately have a different
  /// rate; Phase 5.8 wires the correct value per plan via the handler.
  Future<void> ensureProjected(
    String organizationId, {
    required Money contractualValue,
    int days = defaultProjectionDays,
  }) async {
    final plans = await _planRepo.findByOrganization(organizationId);
    final shiftPlans = plans.where((p) => p.isShiftBased);

    final now = _dateTimeProvider.nowUtc();

    for (final plan in shiftPlans) {
      // Project future days
      await projectDays(
        plan,
        from: now,
        contractualValue: contractualValue,
        days: days,
      );

      // Alert for past gaps
      await detectAndAlertGaps(plan, asOf: now);
    }
  }

  /// Detects past operational dates that should have had SETs (per shift
  /// pattern schedule) but have none recorded, and raises PROJECTION_GAP
  /// CRITICAL alerts for each missing day.
  ///
  /// **B4 decision:** gaps are permanent â€” no retroactive projection.
  Future<void> detectAndAlertGaps(
    PlanDeclaration plan, {
    required DateTime asOf,
  }) async {
    if (!plan.isShiftBased) return;

    for (final pattern in plan.shiftPatterns) {
      // Look back at most 30 days for gaps
      for (var i = 1; i <= defaultProjectionDays; i++) {
        final pastDate = DateTime.utc(
          asOf.year,
          asOf.month,
          asOf.day,
        ).subtract(Duration(days: i));

        if (!pattern.runsOn(pastDate.weekday)) continue;

        final setId = _computeProjectedSetId(plan.id, pattern.index, pastDate);

        final existingAlerts = await _alertRepo.findByEntityId(setId);
        if (existingAlerts.isNotEmpty) continue; // already alerted

        final dateLabel =
            '${pastDate.year}-${pastDate.month.toString().padLeft(2, '0')}-${pastDate.day.toString().padLeft(2, '0')}';

        await _alertRepo.save(
          OperationalAlert(
            id: const Uuid().v4(),
            organizationId: plan.organizationId,
            entityId: setId,
            contractId: plan.contractId,
            alertType: 'PROJECTION_GAP',
            severity: 'CRITICAL',
            triggeredAtUtc: _dateTimeProvider.nowUtc(),
            context: {
              'operationalDate': dateLabel,
              'planDeclarationId': plan.id,
              'shiftPatternIndex': pattern.index,
              'timezone': pattern.timezone,
              'message':
                  'Dia $dateLabel sem viagens programadas detectadas. '
                  'VerificaÃ§Ã£o manual necessÃ¡ria.',
            },
          ),
        );
      }
    }
  }

  // â”€â”€ Private helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<ContractualServiceExecution?> _projectOneSet({
    required PlanDeclaration plan,
    required ShiftPattern pattern,
    required DateTime operationalDate,
    required Money contractualValue,
  }) async {
    final location = tz.getLocation(pattern.timezone);

    // Resolve departure time (scheduled start)
    final depParts = pattern.departureTimeLocal.split(':');
    final depLocal = tz.TZDateTime(
      location,
      operationalDate.year,
      operationalDate.month,
      operationalDate.day,
      int.parse(depParts[0]),
      int.parse(depParts[1]),
    );

    // Resolve arrival time (scheduled end).
    // Overnight shifts cross midnight: arrival base date is D+1.
    final arrivalBaseDate = pattern.isOvernight
        ? operationalDate.add(const Duration(days: 1))
        : operationalDate;
    final arrParts = pattern.arrivalTimeLocal.split(':');
    final arrLocal = tz.TZDateTime(
      location,
      arrivalBaseDate.year,
      arrivalBaseDate.month,
      arrivalBaseDate.day,
      int.parse(arrParts[0]),
      int.parse(arrParts[1]),
    );

    final startUtc = depLocal.toUtc();
    final endUtc = arrLocal.toUtc();

    // Snapshot zone coordinates at projection time (B2 decision)
    final originZone = await _zoneRepo.findById(
      pattern.originZoneId,
      organizationId: plan.organizationId,
    );
    if (originZone == null) return null;

    final destZone = await _zoneRepo.findById(
      pattern.destinationZoneId,
      organizationId: plan.organizationId,
    );
    if (destZone == null) return null;

    // Geofence is optional at zone creation but required at projection time.
    // A zone without geofence cannot be used as origin/destination until an
    // operator configures its coordinates via the Advanced Geofence panel.
    if (originZone.geofence == null) {
      throw DomainException(
        'Zona "${originZone.name}" nÃ£o possui geofence configurado. '
        'Configure as coordenadas antes de projetar viagens.',
      );
    }
    if (destZone.geofence == null) {
      throw DomainException(
        'Zona "${destZone.name}" nÃ£o possui geofence configurado. '
        'Configure as coordenadas antes de projetar viagens.',
      );
    }

    return ContractualServiceExecution.createProjected(
      planDeclarationId: plan.id,
      shiftPatternIndex: pattern.index,
      operationalDate: operationalDate,
      scheduledStartTimeUtc: startUtc,
      scheduledEndTimeUtc: endUtc,
      // Origin snapshot
      originZoneId: originZone.id,
      startLatitude: originZone.geofence!.latitude,
      startLongitude: originZone.geofence!.longitude,
      startRadiusMeters: originZone.geofence!.radiusMeters,
      // Destination snapshot
      destinationZoneId: destZone.id,
      endLatitude: destZone.geofence!.latitude,
      endLongitude: destZone.geofence!.longitude,
      endRadiusMeters: destZone.geofence!.radiusMeters,
      // Financial â€” provided by caller from contract rule snapshot
      contractualValue: contractualValue,
      noShowPenaltyBps: pattern.penalties.noShowPenaltyBps,
      delayToleranceMinutes: pattern.penalties.delayToleranceMinutes,
      delayPenaltyPerMinute: pattern.penalties.delayPenaltyPerMinute,
      downgradePenaltyFlat: pattern.penalties.downgradePenaltyFlat,
    );
  }

  /// Computes the deterministic SET id for a projected SET.
  /// Mirrors [ContractualServiceExecution._generateProjectedSetId].
  static String _computeProjectedSetId(
    String planDeclarationId,
    int shiftPatternIndex,
    DateTime operationalDate,
  ) {
    final dateKey =
        '${operationalDate.year}-${operationalDate.month.toString().padLeft(2, '0')}-${operationalDate.day.toString().padLeft(2, '0')}';
    final input = '$planDeclarationId|$shiftPatternIndex|$dateKey';
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }
}
