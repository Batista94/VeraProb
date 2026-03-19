import 'dart:async';
import 'dart:math';
import 'package:uuid/uuid.dart';

import '../../application/sla_audit/sla_ledger_mapper.dart';
import '../../domain/entities/vehicle_operational_state.dart';
import '../../domain/sla_audit/contractual_execution_state.dart';
import '../../domain/sla_audit/execution_status.dart';
import '../../domain/sla_audit/contractual_rule.dart';
import '../../domain/sla_audit/contractual_execution_state_repository.dart';
import '../../domain/sla_audit/plan_declaration.dart';
import '../../domain/sla_audit/plan_declaration_repository.dart';
import '../../domain/sla_audit/rule_snapshot.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import '../../domain/sla_audit/evaluation_trace.dart';
import '../../domain/sla_audit/evaluation_trace_repository.dart';
import '../../domain/sla_audit/engine_evaluation_result.dart';
import '../../domain/sla_audit/operational_alert_repository.dart';
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

  static const String currentEngineVersion = 'PactaFlow-core_v3';

  /// Tracks when a vehicle first entered a SET's geofence.
  /// Key: setId, Value: first entry timestamp.
  final Map<String, DateTime> _firstEntryTimestamps = {};

  /// Cache for plan declarations to avoid hitting DB per ping.
  final Map<String, PlanDeclaration> _planCache = {};

  ContractualEvaluationEngine({
    required ContractualExecutionStateRepository executionRepo,
    required PlanDeclarationRepository planRepo,
    required SlaAuditLedgerRepository ledgerRepo,
    required EvaluationTraceRepository traceRepo,
    OperationalAlertRepository? alertRepo,
  }) : _executionRepo = executionRepo,
       _planRepo = planRepo,
       _ledgerRepo = ledgerRepo,
       _traceRepo = traceRepo,
       _alertRepo = alertRepo;

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
    required String organizationId,
  }) async {
    // INV-12: Strictly use Event Time (gps_timestamp) for evaluation.
    // Falls back to processing time only if override [nowUtc] is provided.
    final now = nowUtc ?? vehicleState.lastRawPingAt;

    final pendingStates = await _executionRepo.findPendingInWindow(
      now,
      organizationId: organizationId,
    );
    if (pendingStates.isEmpty) return;

    final eligible = pendingStates.where(
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
              evidence: {
                'required_dwell_seconds': requiredDwell,
                'parameter_source': 'rule_config',
              },
            ),
          );
        }
      }

      final distance = _haversineMeters(
        vehicleState.latitude,
        vehicleState.longitude,
        state.startLatitude,
        state.startLongitude,
      );

      final insideGeofence = distance <= state.startRadiusMeters;

      if (insideGeofence) {
        final firstEntry = _firstEntryTimestamps.putIfAbsent(
          state.setId,
          () => now,
        );
        if (now.isBefore(firstEntry)) continue;

        final dwellDuration = now.difference(firstEntry);

        if (dwellDuration.inSeconds >= requiredDwell) {
          if (state.status != ExecutionStatus.pending) continue;

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
              evidence: {
                'distance_meters': distance,
                'allowed_radius_meters': state.startRadiusMeters,
                'actual_dwell_seconds': dwellDuration.inSeconds,
                'required_dwell_seconds': requiredDwell,
              },
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
      }
    }
  }

  // ── Method 2: Sweep Expired Obligations ─────────────────

  Future<void> sweepExpiredObligations({
    DateTime? nowUtc,
    required String organizationId,
  }) async {
    final now = nowUtc ?? DateTime.now().toUtc();
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
          final amount = rule.config['penalty_amount_cents'];
          if (amount is int) penaltyCents = amount;

          decisions.add(
            EvaluationDecision(
              ruleId: rule.ruleId,
              ruleType: rule.ruleType.value,
              ruleVersion: rule.ruleVersion,
              rulePriority: rule.evaluationOrder,
              outcome: 'PENALTY_ASSESSED',
              financialImpactCents: penaltyCents,
              evidence: {'penalty_amount_cents': penaltyCents},
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
          evidence: {
            'scheduled_window_end_utc': state.windowEndUtc.toIso8601String(),
            'evaluated_at_utc': now.toIso8601String(),
            'expired_by_seconds': now.difference(state.windowEndUtc).inSeconds,
          },
        ),
      );

      await _commitEvaluationResults(state, now, decisions);
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

  // ── Haversine ───────────────────────────────────────────

  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusM = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}
