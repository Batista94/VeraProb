import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  group('Event Sourcing Replay', () {
    test('Can rebuild execution outcome exclusively from ledger events', () async {
      final ledgerRepo = InMemorySlaAuditLedgerRepository();
      final execRepo = InMemoryContractualExecutionStateRepository();

      // 1. Initial State
      final originalState = ContractualExecutionState.create(
        organizationId: 'org-1',
        setId: 'set-1',
        contractId: 'c-1',
        planVersion: 1,
        startLatitude: -23.5,
        startLongitude: -46.6,
        startRadiusMeters: 100,
        contractualValue: Money.fromDouble(150.0),
        noShowPenaltyMultiplier: 1.5,
        windowStartUtc: DateTime.utc(2026, 3, 1, 6, 0),
        windowEndUtc: DateTime.utc(2026, 3, 1, 7, 0),
      );

      // Save base state
      await execRepo.save(originalState);

      // 2. Business action execution
      originalState.bindExecution(
        vehicleId: 'v-1',
        latitude: -23.5,
        longitude: -46.6,
        timestampUtc: DateTime.utc(2026, 3, 1, 6, 30),
      );

      for (final event in originalState.domainEvents) {
        await ledgerRepo.append(SlaLedgerMapper.mapToEntry(event));
      }

      // 3. Clear execution repo (except for base config which is typically immutable or fetched)
      // We will re-create the base state simulating fetching the pending starting state
      final reconstructedExecRepo =
          InMemoryContractualExecutionStateRepository();

      final baseState = ContractualExecutionState.create(
        organizationId: 'org-1',
        setId: 'set-1',
        contractId: 'c-1',
        planVersion: 1,
        startLatitude: -23.5,
        startLongitude: -46.6,
        startRadiusMeters: 100,
        contractualValue: Money.fromDouble(150.0),
        noShowPenaltyMultiplier: 1.5,
        windowStartUtc: DateTime.utc(2026, 3, 1, 6, 0),
        windowEndUtc: DateTime.utc(2026, 3, 1, 7, 0),
      );

      // 4. Rebuild From Ledger
      final allEntries = await ledgerRepo.getEntriesBySetId('set-1');
      ContractualExecutionState rebuiltState = baseState;

      for (final entry in allEntries) {
        if (entry.type == 'EXECUTION_BOUND') {
          rebuiltState = ContractualExecutionState.reconstitute(
            organizationId: 'org-1',
            id: rebuiltState.id,
            setId: rebuiltState.setId,
            contractId: rebuiltState.contractId,
            planVersion: rebuiltState.planVersion,
            startLatitude: rebuiltState.startLatitude,
            startLongitude: rebuiltState.startLongitude,
            startRadiusMeters: rebuiltState.startRadiusMeters,
            plannedVehicleId: rebuiltState.plannedVehicleId,
            contractualValue: rebuiltState.contractualValue,
            noShowPenaltyMultiplier: rebuiltState.noShowPenaltyMultiplier,
            windowStartUtc: rebuiltState.windowStartUtc,
            windowEndUtc: rebuiltState.windowEndUtc,
            status: ExecutionStatus.executed, // Updated
            createdAtUtc: rebuiltState.createdAtUtc,
            lastEvaluatedAtUtc: entry.occurredAtUtc,
            statusLastUpdatedAtUtc: entry.occurredAtUtc,
            finalizedAtUtc: entry.occurredAtUtc,
            boundVehicleId: entry.payload['vehicle_id'] as String?,
            bindingTimestampUtc: DateTime.parse(
              entry.payload['binding_timestamp_utc'] as String,
            ),
            bindingLatitude: entry.payload['latitude'] as double?,
            bindingLongitude: entry.payload['longitude'] as double?,
          );
        } else if (entry.type == 'NO_SHOW_DECLARED') {
          rebuiltState = ContractualExecutionState.reconstitute(
            organizationId: 'org-1',
            id: rebuiltState.id,
            setId: rebuiltState.setId,
            contractId: rebuiltState.contractId,
            planVersion: rebuiltState.planVersion,
            startLatitude: rebuiltState.startLatitude,
            startLongitude: rebuiltState.startLongitude,
            startRadiusMeters: rebuiltState.startRadiusMeters,
            plannedVehicleId: rebuiltState.plannedVehicleId,
            contractualValue: rebuiltState.contractualValue,
            noShowPenaltyMultiplier: rebuiltState.noShowPenaltyMultiplier,
            windowStartUtc: rebuiltState.windowStartUtc,
            windowEndUtc: rebuiltState.windowEndUtc,
            status: ExecutionStatus.noShow, // Updated
            createdAtUtc: rebuiltState.createdAtUtc,
            lastEvaluatedAtUtc: entry.occurredAtUtc,
            statusLastUpdatedAtUtc: entry.occurredAtUtc,
            finalizedAtUtc: entry.occurredAtUtc,
          );
        }
      }

      await reconstructedExecRepo.save(rebuiltState);

      // 5. Verification
      final finalState = await reconstructedExecRepo.findBySetId('set-1');

      expect(finalState, isNotNull);
      expect(finalState!.setId, 'set-1');
      expect(finalState.status, ExecutionStatus.executed);
      expect(finalState.boundVehicleId, 'v-1');
      expect(finalState.bindingTimestampUtc, DateTime.utc(2026, 3, 1, 6, 30));
    });

    test(
      'QA Módulo 13 - Can perfectly rebuild a No-Show execution from ledger',
      () async {
        final ledgerRepo = InMemorySlaAuditLedgerRepository();
        final execRepo = InMemoryContractualExecutionStateRepository();

        // 1. Initial State
        final originalState = ContractualExecutionState.create(
          organizationId: 'org-1',
          setId: 'set-noshow',
          contractId: 'c-1',
          planVersion: 1,
          startLatitude: -23.5,
          startLongitude: -46.6,
          startRadiusMeters: 100,
          contractualValue: Money.fromDouble(150.0),
          noShowPenaltyMultiplier: 1.5,
          windowStartUtc: DateTime.utc(2026, 3, 1, 6, 0),
          windowEndUtc: DateTime.utc(2026, 3, 1, 7, 0),
        );

        // Save base state
        await execRepo.save(originalState);

        // 2. Business action execution (Time passed without vehicle)
        originalState.markNoShow(DateTime.utc(2026, 3, 1, 7, 1));

        for (final event in originalState.domainEvents) {
          await ledgerRepo.append(SlaLedgerMapper.mapToEntry(event));
        }

        // 3. Clear execution repo memory
        final reconstructedExecRepo =
            InMemoryContractualExecutionStateRepository();

        // Mock Base fetch
        final baseState = ContractualExecutionState.create(
          organizationId: 'org-1',
          setId: 'set-noshow',
          contractId: 'c-1',
          planVersion: 1,
          startLatitude: -23.5,
          startLongitude: -46.6,
          startRadiusMeters: 100,
          contractualValue: Money.fromDouble(150.0),
          noShowPenaltyMultiplier: 1.5,
          windowStartUtc: DateTime.utc(2026, 3, 1, 6, 0),
          windowEndUtc: DateTime.utc(2026, 3, 1, 7, 0),
        );

        // 4. Rebuild From Ledger
        final allEntries = await ledgerRepo.getEntriesBySetId('set-noshow');
        ContractualExecutionState rebuiltState = baseState;

        for (final entry in allEntries) {
          if (entry.type == 'NO_SHOW_DECLARED') {
            rebuiltState = ContractualExecutionState.reconstitute(
              organizationId: 'org-1',
              id: rebuiltState.id,
              setId: rebuiltState.setId,
              contractId: rebuiltState.contractId,
              planVersion: rebuiltState.planVersion,
              startLatitude: rebuiltState.startLatitude,
              startLongitude: rebuiltState.startLongitude,
              startRadiusMeters: rebuiltState.startRadiusMeters,
              plannedVehicleId: rebuiltState.plannedVehicleId,
              contractualValue: rebuiltState.contractualValue,
              noShowPenaltyMultiplier: rebuiltState.noShowPenaltyMultiplier,
              windowStartUtc: rebuiltState.windowStartUtc,
              windowEndUtc: rebuiltState.windowEndUtc,
              status: ExecutionStatus.noShow,
              createdAtUtc: rebuiltState.createdAtUtc,
              lastEvaluatedAtUtc: entry.occurredAtUtc,
              statusLastUpdatedAtUtc: entry.occurredAtUtc,
              finalizedAtUtc: entry.occurredAtUtc,
            );
          }
        }

        await reconstructedExecRepo.save(rebuiltState);

        // 5. Verification
        final finalState = await reconstructedExecRepo.findBySetId(
          'set-noshow',
        );

        expect(finalState, isNotNull);
        expect(finalState!.setId, 'set-noshow');
        expect(finalState.status, ExecutionStatus.noShow);
        expect(finalState.finalizedAtUtc, DateTime.utc(2026, 3, 1, 7, 1));
        expect(finalState.boundVehicleId, isNull);
      },
    );
  });
}
