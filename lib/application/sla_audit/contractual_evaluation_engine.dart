import 'dart:async';
import 'package:uuid/uuid.dart';

import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/core/utils/geo_math.dart';
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state_repository.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration_repository.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace_repository.dart';
import 'package:veraprob/domain/sla_audit/engine_evaluation_result.dart';
import 'package:veraprob/domain/sla_audit/operational_alert_repository.dart';
import 'package:veraprob/domain/sla_audit/evidence_payload.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/sla_audit/late_arrival_window_policy.dart';
import 'package:veraprob/domain/sla_audit/asset_status.dart';
import 'package:veraprob/domain/sla_audit/asset_status_repository.dart';
import 'alert_derivation_service.dart';

/// Application Service: Reactive evaluation engine for contractual
/// service execution obligations.
///
/// Connects vehicle telemetry to [ContractualExecutionState] aggregates
/// via geofence detection and dwell-time validation.
class ContractualEvaluationEngine {
  final ContractualExecutionStateRepository _executionRepo;
  final PlanDeclarationRepository _planRepo;
  final SlaAuditLedgerRepository _ledgerRepo;
  final EvaluationTraceRepository _traceRepo;
  final OperationalAlertRepository? _alertRepo;
  final AssetStatusRepository? _assetStatusRepo;

  static const String currentEngineVersion = 'veraprob-core_v4';

  /// Tracks when a vehicle first entered a SET's geofence.
  /// Key: setId, Value: first entry timestamp.
  final Map<String, DateTime> _firstEntryTimestamps = {};

  /// Tracks the last known position of each vehicle per SET.
  /// Used for interpolated passage detection between outside→outside pings.
  /// Key: setId, Value: (lat, lng).
  final Map<String, ({double lat, double lng})> _lastPositions =
      {}; // Physical Metric - Double Required

  /// Cache for plan declarations to avoid hitting DB per ping.
  final Map<String, PlanDeclaration> _planCache = {};

  final IDateTimeProvider _clock;

  ContractualEvaluationEngine({
    required ContractualExecutionStateRepository executionRepo,
    required PlanDeclarationRepository planRepo,
    required SlaAuditLedgerRepository ledgerRepo,
    required EvaluationTraceRepository traceRepo,
    OperationalAlertRepository? alertRepo,
    AssetStatusRepository? assetStatusRepo,
    IDateTimeProvider? clock,
  }) : _executionRepo = executionRepo,
       _planRepo = planRepo,
       _ledgerRepo = ledgerRepo,
       _traceRepo = traceRepo,
       _alertRepo = alertRepo,
       _assetStatusRepo = assetStatusRepo,
       _clock = clock ?? BrazilDateTimeProvider();

  Future<RuleSnapshot> _getRuleSnapshot(
    String contractId,
    int version,
    String organizationId,
  ) async {
    final cacheKey = '${contractId}_$version';
    if (_planCache.containsKey(cacheKey)) {
      return _planCache[cacheKey]!.ruleSnapshot;
    }
    final plans = await _planRepo.findByContract(
      contractId,
      organizationId: organizationId,
    );
    final plan = plans.firstWhere((p) => p.planVersion == version);
    _planCache[cacheKey] = plan;
    return plan.ruleSnapshot;
  }

  // ── Method 1: Process Vehicle Telemetry ─────────────────

  Future<void> processVehicleState(
    VehicleOperationalState vehicleState, {
    DateTime? nowUtc,
    DateTime? receivedAtUtc,
    required String organizationId,
  }) async {
    // INV-12: Strictly use Event Time (gps_timestamp) for evaluation.
    // Falls back to processing time only if override [nowUtc] is provided.
    final now = nowUtc ?? vehicleState.lastRawPingAt;

    final activeStates = await _executionRepo.findActiveInWindow(
      now,
      organizationId: organizationId,
    );
    if (activeStates.isEmpty) return;

    final eligible = activeStates.where(
      (s) =>
          s.plannedVehicleId == null ||
          s.plannedVehicleId == vehicleState.vehicleId,
    );

    for (final state in eligible) {
      final rules = await _getRuleSnapshot(
        state.contractId,
        state.planVersion,
        state.organizationId,
      );

      // Grace period: skip SETs whose buffer window has not yet elapsed.
      // Grace period is read from the cached plan's shift patterns (Challenger approach —
      // no schema migration required). When all patterns share the same value, that value
      // is used. When patterns differ, we fall back to 0 (most conservative — engine
      // starts checking immediately, no false passes).
      final cacheKey = '${state.contractId}_${state.planVersion}';
      final gracePeriodMinutes = _getGracePeriodMinutes(_planCache[cacheKey]);
      if (gracePeriodMinutes > 0 &&
          now.isBefore(
            state.windowStartUtc.add(Duration(minutes: gracePeriodMinutes)),
          )) {
        continue;
      }

      // INV-12: 48h Late-Arrival Enforcement.
      // When receivedAtUtc is provided (only for lateArrival facts), enforce the
      // 48h reprocessing window. noShow and evidenceGap states past the cutoff
      // are final — the verdict cannot be overturned by a late fact.
      if (receivedAtUtc != null &&
          (state.status == ExecutionStatus.noShow ||
              state.status == ExecutionStatus.evidenceGap)) {
        if (!LateArrivalWindowPolicy.isWithinReprocessingWindow(
          windowEndUtc: state.windowEndUtc,
          receivedAtUtc: receivedAtUtc,
        )) {
          continue;
        }
      }

      // GPS Quality Filter: skip low-confidence / high-uncertainty pings.
      if (_isLowQualityPing(vehicleState, state)) continue;

      // INV-15: Inhibit evaluation if asset is in maintenance or offDuty.
      // Defense-in-depth — pipeline already checks, engine confirms.
      if (_assetStatusRepo != null) {
        final assetStatus = await _assetStatusRepo.getCurrentStatus(
          assetId: vehicleState.vehicleId,
          organizationId: organizationId,
        );
        if (assetStatus == AssetStatus.maintenance ||
            assetStatus == AssetStatus.offDuty) {
          final inhibitionEntry = SlaLedgerEntry(
            organizationId: state.organizationId,
            type: 'MAINTENANCE_INHIBITED',
            setId: state.setId,
            contractId: state.contractId,
            planVersion: state.planVersion,
            occurredAtUtc: now,
            payload: MaintenanceInhibitionEvidence(
              vehicleStatusAtEvaluation: assetStatus.name,
              inhibitionReason: 'MAINTENANCE_INHIBITION',
            ).toJson(),
          );
          await _ledgerRepo.append(inhibitionEntry);
          continue;
        }
      }

      // Deterministic deterministic execution order
      final sortedRules = rules.rules.toList()
        ..sort((a, b) {
          final cmp = a.evaluationOrder.compareTo(b.evaluationOrder);
          return cmp != 0 ? cmp : a.ruleId.compareTo(b.ruleId);
        });

      int requiredDwell = 30; // Default fallback
      final List<EvaluationDecision> decisions = [];

      for (final rule in sortedRules) {
        if (rule.ruleType == SlaRuleType.minGeofenceCoverage) {
          final dwellParam = rule.config['min_dwell_seconds'];
          if (dwellParam is int) requiredDwell = dwellParam;

          decisions.add(
            EvaluationDecision(
              ruleId: rule.ruleId,
              ruleType: rule.ruleType.value,
              ruleVersion: rule.ruleVersion,
              rulePriority: rule.evaluationOrder,
              outcome: 'EVALUATED_DWELL_REQUIREMENT',
              evidence: DwellRequirementEvidence(
                requiredDwellSeconds: requiredDwell,
                parameterSource: 'rule_config',
              ),
            ),
          );
        } else if (rule.ruleType == SlaRuleType.excessiveSpeed) {
          final maxSpeed = rule.config['max_speed_kmh'] as num?;
          final currentSpeed = vehicleState.smoothedSpeed;
          if (maxSpeed != null && currentSpeed > maxSpeed) {
            int fineCents = rule.config['fine_cents'] as int? ?? 150000;
            // INV: Severidade nunca ultrapassa 100 BPS (1%) do valor do contrato
            final maxCents = (state.contractualValue.cents * 100) ~/ 10000;
            if (fineCents > maxCents) fineCents = maxCents;

            final verdictEvidence = VerdictEvidence.create(
              clauseRef: rule.ruleId,
              ruleId: rule.ruleId,
              ruleVersion: rule.ruleVersion,
              primaryEvidenceLat: vehicleState.latitude,
              primaryEvidenceLng: vehicleState.longitude,
              primaryEvidenceTimestampUtc: now,
              deltaValue: currentSpeed - maxSpeed.toDouble(),
              thresholdValue: maxSpeed.toDouble(),
              fineCents: Money(fineCents),
              confidenceScore: 98,
            );

            final recommendedEvent = SanctionRecommendedEvent(
              organizationId: state.organizationId,
              occurredAtUtc: now,
              setId: state.setId,
              contractId: state.contractId,
              planVersion: state.planVersion,
              verdictEvidence: verdictEvidence,
            );

            await _ledgerRepo.append(
              SlaLedgerMapper.mapToEntry(recommendedEvent),
            );

            decisions.add(
              EvaluationDecision(
                ruleId: rule.ruleId,
                ruleType: rule.ruleType.value,
                ruleVersion: rule.ruleVersion,
                rulePriority: rule.evaluationOrder,
                outcome: 'SANCTION_RECOMMENDED',
                evidence: SpeedViolationEvidence(
                  actualSpeedKmh: currentSpeed,
                  limitSpeedKmh: maxSpeed.toDouble(),
                ),
              ),
            );
          }
        } else if (rule.ruleType == SlaRuleType.maxToleranceDelay) {
          final toleranceMinutes =
              rule.config['delay_tolerance_minutes'] as int? ?? 0;
          final penaltyPerMinuteCents =
              rule.config['penalty_per_minute_cents'] as int? ?? 0;
          final maxCapCents = rule.config['max_penalty_cap_cents'] as int?;

          final delayMinutes = now.difference(state.windowStartUtc).inMinutes;
          if (delayMinutes <= 0) continue;

          final billableMinutes = (delayMinutes - toleranceMinutes).clamp(
            0,
            delayMinutes,
          );
          if (billableMinutes == 0) continue;

          final grossCents = billableMinutes * penaltyPerMinuteCents;
          final finalCents = maxCapCents != null
              ? grossCents.clamp(0, maxCapCents)
              : grossCents;

          decisions.add(
            EvaluationDecision(
              ruleId: rule.ruleId,
              ruleType: rule.ruleType.value,
              ruleVersion: rule.ruleVersion,
              rulePriority: rule.evaluationOrder,
              outcome: 'DELAY_PENALTY_ASSESSED',
              evidence: DelayPenaltyEvidence(
                delayMinutes: delayMinutes,
                toleranceMinutes: toleranceMinutes,
                billableMinutes: billableMinutes,
                grossPenaltyCents: grossCents,
                finalPenaltyCents: finalCents,
                capApplied: maxCapCents != null && grossCents > maxCapCents,
              ),
            ),
          );
        }
      }

      final distance = GeoMath.haversineMeters(
        vehicleState.latitude,
        vehicleState.longitude,
        state.startLatitude,
        state.startLongitude,
      );

      final tracking = _firstEntryTimestamps.containsKey(state.setId);
      final insideGeofence = _isInsideWithHysteresis(
        distance,
        state.startRadiusMeters,
        tracking,
      );

      if (insideGeofence) {
        final firstEntry = _firstEntryTimestamps.putIfAbsent(
          state.setId,
          () => now,
        );
        if (now.isBefore(firstEntry)) continue;

        final dwellDuration = now.difference(firstEntry);

        if (dwellDuration.inSeconds >= requiredDwell) {
          // If already executed (from a previous fact), nothing to do.
          if (state.status == ExecutionStatus.executed) continue;

          state.bindExecution(
            vehicleId: vehicleState.vehicleId,
            latitude: vehicleState.latitude,
            longitude: vehicleState.longitude,
            timestampUtc: now,
          );

          // Generate outcome decision
          decisions.add(
            EvaluationDecision(
              ruleId: 'engine-core',
              ruleType: 'BIND_EXECUTION',
              ruleVersion: 1,
              rulePriority: 999,
              outcome: 'PASS',
              evidence: GeofenceBindingEvidence(
                distanceMeters: distance,
                allowedRadiusMeters: state.startRadiusMeters,
                actualDwellSeconds: dwellDuration.inSeconds,
                requiredDwellSeconds: requiredDwell,
              ),
            ),
          );

          await _commitEvaluationResults(state, now, decisions);
          _firstEntryTimestamps.remove(state.setId);
        }
      } else {
        final firstEntry = _firstEntryTimestamps[state.setId];
        if (firstEntry != null && now.isAfter(firstEntry)) {
          _firstEntryTimestamps.remove(state.setId);
        }

        // Check for interpolated passage (vehicle passed through geofence
        // between two outside pings)
        _checkInterpolatedPassage(vehicleState, state, now, decisions);
      }

      // Always update last known position (after all checks)
      _lastPositions[state.setId] = (
        lat: vehicleState.latitude,
        lng: vehicleState.longitude,
      );
    }
  }

  // ── Method 2: Sweep Expired Obligations ─────────────────

  Future<void> sweepExpiredObligations({
    DateTime? nowUtc,
    required String organizationId,
  }) async {
    final now = nowUtc ?? _clock.now();
    final expiredStates = await _executionRepo.findExpiredPending(
      now,
      organizationId: organizationId,
    );

    for (final state in expiredStates) {
      final rules = await _getRuleSnapshot(
        state.contractId,
        state.planVersion,
        state.organizationId,
      );

      final sortedRules = rules.rules.toList()
        ..sort((a, b) {
          final cmp = a.evaluationOrder.compareTo(b.evaluationOrder);
          return cmp != 0 ? cmp : a.ruleId.compareTo(b.ruleId);
        });

      final List<EvaluationDecision> decisions = [];
      String outcome = 'NO_SHOW_PENALTY';
      int? penaltyCents;

      for (final rule in sortedRules) {
        if (rule.ruleType == SlaRuleType.noShowPenalty) {
          penaltyCents =
              (state.contractualValue.cents * state.noShowPenaltyBps) ~/ 10000;

          // INV: Sanction severity never exceeds 100 BPS (1%) of contractual value
          final maxNoShowCents = (state.contractualValue.cents * 100) ~/ 10000;
          if (penaltyCents > maxNoShowCents) penaltyCents = maxNoShowCents;

          decisions.add(
            EvaluationDecision(
              ruleId: rule.ruleId,
              ruleType: rule.ruleType.value,
              ruleVersion: rule.ruleVersion,
              rulePriority: rule.evaluationOrder,
              outcome: 'PENALTY_ASSESSED',
              financialImpactCents: penaltyCents,
              evidence: PenaltyAssessedEvidence(
                penaltyAmountCents: penaltyCents,
              ),
            ),
          );
        }
      }

      state.markNoShow(now);

      decisions.add(
        EvaluationDecision(
          ruleId: 'engine-core',
          ruleType: 'EXPIRATION_SWEEP',
          ruleVersion: 1,
          rulePriority: 999,
          outcome: outcome,
          evidence: ExpirationSweepEvidence(
            scheduledWindowEndUtc: state.windowEndUtc.toIso8601String(),
            evaluatedAtUtc: now.toIso8601String(),
            expiredBySeconds: now.difference(state.windowEndUtc).inSeconds,
          ),
        ),
      );

      await _commitEvaluationResults(state, now, decisions);

      // INV-23: Emit SANCTION_RECOMMENDED when a penalty was assessed.
      // The engine RECOMMENDS — it never emits VERDICT_SEALED directly.
      // The DB trigger auto-populates sanction_review_queue on INSERT.
      if (penaltyCents != null && penaltyCents > 0) {
        // Build VerdictEvidence from the no-show context.
        // windowEndUtc serves as the primary evidence timestamp (the moment
        // the contractual obligation expired).
        final windowEndUtc = state.windowEndUtc.isUtc
            ? state.windowEndUtc
            : state.windowEndUtc.toUtc();

        final noShowRuleId = sortedRules
            .where((r) => r.ruleType == SlaRuleType.noShowPenalty)
            .map((r) => r.ruleId)
            .firstOrNull;
        final noShowRuleVersion = sortedRules
            .where((r) => r.ruleType == SlaRuleType.noShowPenalty)
            .map((r) => r.ruleVersion)
            .firstOrNull;

        if (noShowRuleId != null && noShowRuleVersion != null) {
          final verdictEvidence = VerdictEvidence.create(
            clauseRef: noShowRuleId,
            ruleId: noShowRuleId,
            ruleVersion: noShowRuleVersion,
            primaryEvidenceLat: state.startLatitude,
            primaryEvidenceLng: state.startLongitude,
            primaryEvidenceTimestampUtc: windowEndUtc,
            deltaValue: now.difference(state.windowEndUtc).inMinutes.toDouble(),
            thresholdValue: 0.0,
            fineCents: Money(penaltyCents),
            confidenceScore: 100,
            geofenceCenterLat: state.startLatitude,
            geofenceCenterLng: state.startLongitude,
            geofenceRadiusMeters: state.startRadiusMeters.toDouble(),
          );

          final recommendedEvent = SanctionRecommendedEvent(
            organizationId: state.organizationId,
            occurredAtUtc: now,
            setId: state.setId,
            contractId: state.contractId,
            planVersion: state.planVersion,
            verdictEvidence: verdictEvidence,
          );

          await _ledgerRepo.append(
            SlaLedgerMapper.mapToEntry(recommendedEvent),
          );
        }
      }
    }
  }

  // ── Persistence Helper ────────────────────────────────────

  /// Formally constructs the Triplet and routes it to repositories.
  Future<void> _commitEvaluationResults(
    ContractualExecutionState state,
    DateTime now,
    List<EvaluationDecision> decisions,
  ) async {
    await _executionRepo.save(state);

    // ── Pipeline: Ledger first → event_id → Trace ──────────
    // Persist ledger entries and capture the last event UUID
    // for causal linkage with the evaluation trace.
    String? triggeringEventId;
    for (final event in state.domainEvents) {
      final entry = SlaLedgerMapper.mapToEntry(event);
      triggeringEventId = await _ledgerRepo.append(entry);
    }

    // Construct the investigative trace anchored to the ledger event
    final trace = EvaluationTrace(
      id: const Uuid().v4(),
      organizationId: state.organizationId,
      entityId: state.setId,
      triggeringEventId: triggeringEventId ?? 'no-ledger-event',
      evaluatedAtUtc: now,
      engineVersion: currentEngineVersion,
      decisions: decisions,
    );

    // Form conceptual triplet (Financial Snapshot omitted here as it runs daily)
    final result = EngineEvaluationResult(executionState: state, trace: trace);

    // Persist trace
    await _traceRepo.save(result.trace);

    // ── Alert Derivation ──────────────────────────────────
    if (_alertRepo != null) {
      final alert = AlertDerivationService.deriveFrom(
        state: state,
        decisions: decisions,
        evaluatedAtUtc: now,
        triggeringEventId: triggeringEventId,
        traceId: trace.id,
      );
      if (alert != null) {
        await _alertRepo.save(alert);
      }
    }
  }

  // ── Grace Period Helper ──────────────────────────────────

  /// Returns the grace period (minutes) to apply before the engine starts
  /// evaluating a SET. Reads from the cached [PlanDeclaration] shift patterns.
  ///
  /// Contract: if all shift patterns share the same [gracePeriodMinutes] value,
  /// that value is returned. If patterns differ (edge case), returns 0 to avoid
  /// incorrectly suppressing evaluation for any SET.
  int _getGracePeriodMinutes(PlanDeclaration? plan) {
    if (plan == null || plan.shiftPatterns.isEmpty) return 0;
    final values = plan.shiftPatterns
        .map((p) => p.penalties.gracePeriodMinutes)
        .toSet();
    return values.length == 1 ? values.first : 0;
  }

  // ── GPS Quality Filter ──────────────────────────────────

  bool _isLowQualityPing(
    VehicleOperationalState v,
    ContractualExecutionState s,
  ) {
    if (v.confidence < 0.7) return true;
    final acc = v.accuracyMeters;
    if (acc != null && acc > s.startRadiusMeters / 2.0) return true;
    return false;
  }

  // ── Hysteresis ──────────────────────────────────────────

  bool _isInsideWithHysteresis(
    double distance, // Physical Metric - Double Required
    int radiusMeters,
    bool tracking,
  ) {
    if (!tracking) return distance <= radiusMeters; // Enter: strict
    return distance <= radiusMeters * 1.2; // Exit: hysteresis band
  }

  // ── Interpolated Passage ────────────────────────────────

  void _checkInterpolatedPassage(
    VehicleOperationalState v,
    ContractualExecutionState state,
    DateTime now,
    List<EvaluationDecision> decisions,
  ) {
    final last = _lastPositions[state.setId];
    if (last == null) return; // No prior position — nothing to interpolate

    final crosses = GeoMath.lineIntersectsCircle(
      last.lat,
      last.lng,
      v.latitude,
      v.longitude,
      state.startLatitude,
      state.startLongitude,
      state.startRadiusMeters.toDouble(),
    );
    if (!crosses) return;

    decisions.add(
      EvaluationDecision(
        ruleId: 'engine-core',
        ruleType: 'INTERPOLATED_PASSAGE',
        ruleVersion: 1,
        rulePriority: 998,
        outcome: 'INTERPOLATED_PASSAGE',
        evidence: InterpolatedPassageEvidence(
          fromLat: last.lat,
          fromLng: last.lng,
          toLat: v.latitude,
          toLng: v.longitude,
          geofenceCenterLat: state.startLatitude,
          geofenceCenterLng: state.startLongitude,
          geofenceRadiusMeters: state.startRadiusMeters.toDouble(),
        ),
      ),
    );
  }
}
