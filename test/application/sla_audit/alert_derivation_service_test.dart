import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/alert_derivation_service.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace.dart';
import 'package:veraprob/domain/sla_audit/evidence_payload.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';

void main() {
  final now = DateTime.utc(2024, 6, 1, 10);
  final windowStart = now.subtract(const Duration(hours: 2));
  final windowEnd = now.subtract(const Duration(hours: 1));

  ContractualExecutionState makeState(ExecutionStatus targetStatus) {
    final state = ContractualExecutionState.create(
      organizationId: 'org-1',
      setId: 'set-1',
      contractId: 'contract-1',
      planVersion: 1,
      startLatitude: -23.5,
      startLongitude: -46.6,
      startRadiusMeters: 100,
      contractualValue: const Money(50000),
      noShowPenaltyBps: 15000,
      windowStartUtc: windowStart,
      windowEndUtc: windowEnd,
    );

    switch (targetStatus) {
      case ExecutionStatus.executed:
        state.bindExecution(
          vehicleId: 'v1',
          latitude: -23.5,
          longitude: -46.6,
          timestampUtc: now,
        );
        break;
      case ExecutionStatus.noShow:
        state.markNoShow(now);
        break;
      case ExecutionStatus.evidenceGap:
        state.markEvidenceGap(now);
        break;
      case ExecutionStatus.pending:
        break;
      case ExecutionStatus.inhibited:
        break;
    }

    return state;
  }

  EvaluationDecision makeDecision({int? penaltyCents}) => EvaluationDecision(
    ruleId: 'rule-1',
    ruleType: 'SPEED_LIMIT',
    ruleVersion: 1,
    rulePriority: 10,
    outcome: penaltyCents != null ? 'PENALTY_APPLIED' : 'COMPLIANT',
    financialImpactCents: penaltyCents,
    evidence: const GenericEvidencePayload({}),
  );

  group('AlertDerivationService.deriveFrom', () {
    test('noShow state → CRITICAL alert type NO_SHOW', () {
      final alert = AlertDerivationService.deriveFrom(
        state: makeState(ExecutionStatus.noShow),
        decisions: [],
        evaluatedAtUtc: now,
      );
      expect(alert, isNotNull);
      expect(alert!.alertType, 'NO_SHOW');
      expect(alert.severity, 'CRITICAL');
    });

    test('evidenceGap state → WARNING alert type EVIDENCE_GAP', () {
      final alert = AlertDerivationService.deriveFrom(
        state: makeState(ExecutionStatus.evidenceGap),
        decisions: [],
        evaluatedAtUtc: now,
      );
      expect(alert, isNotNull);
      expect(alert!.alertType, 'EVIDENCE_GAP');
      expect(alert.severity, 'WARNING');
    });

    test('executed with penalty → HIGH alert type PENALTY_APPLIED', () {
      final alert = AlertDerivationService.deriveFrom(
        state: makeState(ExecutionStatus.executed),
        decisions: [makeDecision(penaltyCents: 15000)],
        evaluatedAtUtc: now,
      );
      expect(alert, isNotNull);
      expect(alert!.alertType, 'PENALTY_APPLIED');
      expect(alert.severity, 'HIGH');
    });

    test('executed with no penalty → null (no alert)', () {
      final alert = AlertDerivationService.deriveFrom(
        state: makeState(ExecutionStatus.executed),
        decisions: [makeDecision()],
        evaluatedAtUtc: now,
      );
      expect(alert, isNull);
    });

    test('pending state → null (no alert)', () {
      final alert = AlertDerivationService.deriveFrom(
        state: makeState(ExecutionStatus.pending),
        decisions: [],
        evaluatedAtUtc: now,
      );
      expect(alert, isNull);
    });

    test('alert has correct organizationId and contractId', () {
      final state = makeState(ExecutionStatus.noShow);
      final alert = AlertDerivationService.deriveFrom(
        state: state,
        decisions: [],
        evaluatedAtUtc: now,
        triggeringEventId: 'evt-1',
        traceId: 'trace-1',
      );
      expect(alert!.organizationId, state.organizationId);
      expect(alert.contractId, state.contractId);
      expect(alert.triggeringEventId, 'evt-1');
      expect(alert.traceId, 'trace-1');
    });

    test('context includes driver_id and driver_name when provided', () {
      final alert = AlertDerivationService.deriveFrom(
        state: makeState(ExecutionStatus.noShow),
        decisions: [],
        evaluatedAtUtc: now,
        driverId: 'driver-abc',
        driverName: 'João Silva',
      );
      expect(alert!.context['driver_id'], 'driver-abc');
      expect(alert.context['driver_name'], 'João Silva');
    });

    test('context omits driver fields when null', () {
      final alert = AlertDerivationService.deriveFrom(
        state: makeState(ExecutionStatus.noShow),
        decisions: [],
        evaluatedAtUtc: now,
      );
      expect(alert!.context.containsKey('driver_id'), isFalse);
      expect(alert.context.containsKey('driver_name'), isFalse);
    });

    test('driver enrichment works for all alert types', () {
      final gap = AlertDerivationService.deriveFrom(
        state: makeState(ExecutionStatus.evidenceGap),
        decisions: [],
        evaluatedAtUtc: now,
        driverId: 'd-1',
      );
      expect(gap!.context['driver_id'], 'd-1');

      final penalty = AlertDerivationService.deriveFrom(
        state: makeState(ExecutionStatus.executed),
        decisions: [makeDecision(penaltyCents: 5000)],
        evaluatedAtUtc: now,
        driverId: 'd-2',
        driverName: 'Maria',
      );
      expect(penalty!.context['driver_id'], 'd-2');
      expect(penalty.context['driver_name'], 'Maria');
    });
  });
}
