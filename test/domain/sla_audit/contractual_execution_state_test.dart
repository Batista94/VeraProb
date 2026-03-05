import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/domain/sla_audit/contractual_execution_state.dart';
import 'package:busflow/domain/sla_audit/domain_exception.dart';
import 'package:busflow/domain/sla_audit/execution_events.dart';
import 'package:busflow/domain/sla_audit/execution_status.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';

void main() {
  // ── Helpers ──────────────────────────────────────────────
  ContractualExecutionState makeState({
    String setId = 'set-1',
    String contractId = 'contract-1',
    double startLat = -23.5505,
    double startLng = -46.6333,
    int startRadius = 100,
    String? plannedVehicleId,
    DateTime? windowStart,
    DateTime? windowEnd,
    double contractualValue = 150.0,
    double noShowPenaltyMultiplier = 1.5,
  }) {
    final start = windowStart ?? DateTime.utc(2026, 3, 1, 6, 0);
    final end = windowEnd ?? DateTime.utc(2026, 3, 1, 7, 0);
    return ContractualExecutionState.create(organizationId: 'org-1', 
      setId: setId,
      contractId: contractId,
      planVersion: 1,
      startLatitude: startLat,
      startLongitude: startLng,
      startRadiusMeters: startRadius,
      plannedVehicleId: plannedVehicleId,
      contractualValue: contractualValue,
      noShowPenaltyMultiplier: noShowPenaltyMultiplier,
      windowStartUtc: start,
      windowEndUtc: end,
    );
  }

  // ── Aggregate Tests ─────────────────────────────────────
  group('ContractualExecutionState', () {
    test('create() initializes with pending status', () {
      final state = makeState();

      expect(state.id, isNotEmpty);
      expect(state.setId, 'set-1');
      expect(state.contractId, 'contract-1');
      expect(state.status, ExecutionStatus.pending);
      expect(state.boundVehicleId, isNull);
      expect(state.bindingTimestampUtc, isNull);
      expect(state.bindingLatitude, isNull);
      expect(state.bindingLongitude, isNull);
      expect(state.finalizedAtUtc, isNull);
      expect(state.domainEvents, isEmpty);
    });

    test('throws on invalid time window (end <= start)', () {
      final t = DateTime.utc(2026, 3, 1, 6, 0);

      expect(
        () => ContractualExecutionState.create(organizationId: 'org-1', 
          setId: 'set-1',
          contractId: 'c-1',
          planVersion: 1,
          startLatitude: -23.55,
          startLongitude: -46.63,
          startRadiusMeters: 100,
          contractualValue: 100.0,
          noShowPenaltyMultiplier: 1.0,
          windowStartUtc: t,
          windowEndUtc: t,
        ),
        throwsA(isA<DomainException>()),
      );

      expect(
        () => ContractualExecutionState.create(organizationId: 'org-1', 
          setId: 'set-1',
          contractId: 'c-1',
          planVersion: 1,
          startLatitude: -23.55,
          startLongitude: -46.63,
          startRadiusMeters: 100,
          contractualValue: 100.0,
          noShowPenaltyMultiplier: 1.0,
          windowStartUtc: t,
          windowEndUtc: t.subtract(const Duration(minutes: 1)),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('bindExecution transitions to executed with evidence', () {
      final state = makeState();
      final bindTime = DateTime.utc(2026, 3, 1, 6, 30);

      state.bindExecution(
        vehicleId: 'v-42',
        latitude: -23.55,
        longitude: -46.63,
        timestampUtc: bindTime,
      );

      expect(state.status, ExecutionStatus.executed);
      expect(state.boundVehicleId, 'v-42');
      expect(state.bindingLatitude, -23.55);
      expect(state.bindingLongitude, -46.63);
      expect(state.bindingTimestampUtc, bindTime);
      expect(state.finalizedAtUtc, bindTime);
      expect(state.lastEvaluatedAtUtc, bindTime);
    });

    test('bindExecution emits ExecutionBoundEvent', () {
      final state = makeState();

      state.bindExecution(
        vehicleId: 'v-42',
        latitude: -23.55,
        longitude: -46.63,
        timestampUtc: DateTime.utc(2026, 3, 1, 6, 30),
      );

      expect(state.domainEvents, hasLength(1));
      final event = state.domainEvents.first;
      expect(event, isA<ExecutionBoundEvent>());

      final bound = event as ExecutionBoundEvent;
      expect(bound.setId, 'set-1');
      expect(bound.contractId, 'contract-1');
      expect(bound.vehicleId, 'v-42');
    });

    test('cannot bindExecution after already executed', () {
      final state = makeState();
      state.bindExecution(
        vehicleId: 'v-1',
        latitude: -23.55,
        longitude: -46.63,
        timestampUtc: DateTime.utc(2026, 3, 1, 6, 30),
      );

      expect(
        () => state.bindExecution(
          vehicleId: 'v-2',
          latitude: -23.56,
          longitude: -46.64,
          timestampUtc: DateTime.utc(2026, 3, 1, 6, 45),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('markNoShow works when window has expired', () {
      final state = makeState(windowEnd: DateTime.utc(2026, 3, 1, 7, 0));
      final afterWindow = DateTime.utc(2026, 3, 1, 7, 1);

      state.markNoShow(afterWindow);

      expect(state.status, ExecutionStatus.noShow);
      expect(state.finalizedAtUtc, afterWindow);
      expect(state.boundVehicleId, isNull);
    });

    test('markNoShow emits NoShowDeclaredEvent', () {
      final state = makeState();
      final afterWindow = DateTime.utc(2026, 3, 1, 7, 1);

      state.markNoShow(afterWindow);

      expect(state.domainEvents, hasLength(1));
      expect(state.domainEvents.first, isA<NoShowDeclaredEvent>());
    });

    test('markNoShow rejected before window expires', () {
      final state = makeState(windowEnd: DateTime.utc(2026, 3, 1, 7, 0));
      final beforeWindow = DateTime.utc(2026, 3, 1, 6, 59);

      expect(
        () => state.markNoShow(beforeWindow),
        throwsA(isA<DomainException>()),
      );
      expect(state.status, ExecutionStatus.pending);
    });

    test('markEvidenceGap works correctly', () {
      final state = makeState();
      final now = DateTime.utc(2026, 3, 1, 6, 45);

      state.markEvidenceGap(now);

      expect(state.status, ExecutionStatus.evidenceGap);
      expect(state.finalizedAtUtc, now);
    });

    test('markEvidenceGap emits EvidenceGapDeclaredEvent', () {
      final state = makeState();

      state.markEvidenceGap(DateTime.utc(2026, 3, 1, 6, 45));

      expect(state.domainEvents, hasLength(1));
      expect(state.domainEvents.first, isA<EvidenceGapDeclaredEvent>());
    });

    test('no transitions allowed after finalization (executed)', () {
      final state = makeState();
      state.bindExecution(
        vehicleId: 'v-1',
        latitude: -23.55,
        longitude: -46.63,
        timestampUtc: DateTime.utc(2026, 3, 1, 6, 30),
      );

      expect(
        () => state.markNoShow(DateTime.utc(2026, 3, 1, 8, 0)),
        throwsA(isA<DomainException>()),
      );
      expect(
        () => state.markEvidenceGap(DateTime.utc(2026, 3, 1, 8, 0)),
        throwsA(isA<DomainException>()),
      );
    });

    test('no transitions allowed after finalization (noShow)', () {
      final state = makeState();
      state.markNoShow(DateTime.utc(2026, 3, 1, 7, 1));

      expect(
        () => state.bindExecution(
          vehicleId: 'v-1',
          latitude: -23.55,
          longitude: -46.63,
          timestampUtc: DateTime.utc(2026, 3, 1, 7, 5),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('updateEvaluationTimestamp updates without state change', () {
      final state = makeState();
      final t = DateTime.utc(2026, 3, 1, 6, 30);

      state.updateEvaluationTimestamp(t);

      expect(state.lastEvaluatedAtUtc, t);
      expect(state.status, ExecutionStatus.pending);
      expect(state.domainEvents, isEmpty);
    });

    test('domainEvents list is unmodifiable', () {
      final state = makeState();
      state.bindExecution(
        vehicleId: 'v-1',
        latitude: -23.55,
        longitude: -46.63,
        timestampUtc: DateTime.utc(2026, 3, 1, 6, 30),
      );

      expect(
        () => state.domainEvents.add(state.domainEvents.first),
        throwsUnsupportedError,
      );
    });

    test('equality based on id only', () {
      final a = makeState(setId: 'set-a');
      final b = makeState(setId: 'set-b');

      // Different instances with different ids
      expect(a == b, isFalse);
      // Same instance
      expect(a == a, isTrue);
    });
  });

  // ── Repository Tests ────────────────────────────────────
  group('InMemoryContractualExecutionStateRepository', () {
    late InMemoryContractualExecutionStateRepository repo;

    setUp(() {
      repo = InMemoryContractualExecutionStateRepository();
    });

    test('save and findBySetId', () async {
      final state = makeState(setId: 'set-x');
      await repo.save(state);

      final found = await repo.findBySetId('set-x');
      expect(found, isNotNull);
      expect(found!.id, state.id);
    });

    test('findBySetId returns null when not found', () async {
      final found = await repo.findBySetId('nonexistent');
      expect(found, isNull);
    });

    test('save overwrites existing entry', () async {
      final state = makeState(setId: 'set-x');
      await repo.save(state);

      state.bindExecution(
        vehicleId: 'v-1',
        latitude: -23.55,
        longitude: -46.63,
        timestampUtc: DateTime.utc(2026, 3, 1, 6, 30),
      );
      await repo.save(state);

      final found = await repo.findBySetId('set-x');
      expect(found!.status, ExecutionStatus.executed);
    });

    test('findPendingByContractAndTime filters correctly', () async {
      // Pending, in window
      final inWindow = makeState(
        setId: 'in-window',
        contractId: 'c-1',
        windowStart: DateTime.utc(2026, 3, 1, 6, 0),
        windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
      );
      await repo.save(inWindow);

      // Pending, outside window
      final outsideWindow = makeState(
        setId: 'outside-window',
        contractId: 'c-1',
        windowStart: DateTime.utc(2026, 3, 1, 8, 0),
        windowEnd: DateTime.utc(2026, 3, 1, 9, 0),
      );
      await repo.save(outsideWindow);

      // Different contract
      final diffContract = makeState(
        setId: 'diff-contract',
        contractId: 'c-other',
        windowStart: DateTime.utc(2026, 3, 1, 6, 0),
        windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
      );
      await repo.save(diffContract);

      // Executed (not pending)
      final executed = makeState(
        setId: 'executed-one',
        contractId: 'c-1',
        windowStart: DateTime.utc(2026, 3, 1, 6, 0),
        windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
      );
      executed.bindExecution(
        vehicleId: 'v-1',
        latitude: -23.55,
        longitude: -46.63,
        timestampUtc: DateTime.utc(2026, 3, 1, 6, 30),
      );
      await repo.save(executed);

      final results = await repo.findPendingByContractAndTime(
        'c-1',
        DateTime.utc(2026, 3, 1, 6, 30),
      );

      expect(results, hasLength(1));
      expect(results.first.setId, 'in-window');
    });
  });
}
