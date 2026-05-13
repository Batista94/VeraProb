import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contractual_execution_state_repository.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../postgres/postgres_test_config.dart';

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'FASE 5 - Execution State Repository Postgres Tests (execution_states)',
    () {
      late SupabaseClient client;
      late PostgresContractualExecutionStateRepository repository;
      const uuid = Uuid();

      setUpAll(() async {
        if (isRunning) {
          client = await PostgresTestConfig.createClient();
          await PostgresTestConfig.ensureSentinelOrg(client: client);
          repository = PostgresContractualExecutionStateRepository(
            client,
            UtcDateTimeProvider(),
          );
        }
      });

      test('1. Insert and full domain reconstitution cycle works', () async {
        final setId = uuid.v4();
        final contractId = uuid.v4();

        // Seed causal linkage prerequisite (plan_declaration + service_execution)
        await PostgresTestConfig.seedServiceExecution(
          client,
          setId: setId,
          contractId: contractId,
        );

        final state = ContractualExecutionState.create(
          organizationId: PostgresTestConfig.testOrgId,
          setId: setId,
          contractId: contractId,
          planVersion: 1,
          startLatitude: -23.5505,
          startLongitude: -46.6333,
          startRadiusMeters: 50,
          plannedVehicleId: 'veh-01',
          contractualValue: const Money(150000),
          noShowPenaltyBps: 15000,
          windowStartUtc: DateTime.now().toUtc().subtract(
            const Duration(minutes: 10),
          ),
          windowEndUtc: DateTime.now().toUtc().add(const Duration(minutes: 50)),
        );

        // Mutates to executed state to test bindings
        final executionTime = DateTime.utc(2026, 4, 8, 12, 0, 0);
        state.bindExecution(
          vehicleId: 'veh-01',
          latitude: -23.5506,
          longitude: -46.6334,
          timestampUtc: executionTime,
        );

        // Save aggregate
        await repository.save(state);

        // Find By Id
        final loadedState = await repository.findBySetId(state.setId);

        expect(loadedState, isNotNull);
        expect(loadedState!.id, state.id);
        expect(loadedState.setId, setId);
        expect(loadedState.contractId, contractId);
        expect(loadedState.status.name, 'completed');

        // Binding checks
        expect(loadedState.boundVehicleId, 'veh-01');

        // Reconstituted Dates often lose nanosecond precision when going to DB. Assure exact matching or near delta matching.
        expect(
          loadedState.bindingTimestampUtc!
              .difference(executionTime)
              .inMilliseconds
              .abs(),
          lessThan(
            100,
          ), // Allowing ms difference due to timestamp truncating in PostgreSQL
        );
      });

      test(
        '2. Finding Active By Contract returns properly saved aggregate',
        () async {
          final contractId = uuid.v4();
          final setId1 = uuid.v4();
          final setId2 = uuid.v4();
          final contractId2 = uuid.v4();

          // Seed causal linkage prerequisites
          await PostgresTestConfig.seedServiceExecution(
            client,
            setId: setId1,
            contractId: contractId,
          );
          await PostgresTestConfig.seedServiceExecution(
            client,
            setId: setId2,
            contractId: contractId2,
          );

          final state1 = ContractualExecutionState.create(
            organizationId: PostgresTestConfig.testOrgId,
            setId: setId1,
            contractId: contractId,
            planVersion: 1,
            startLatitude: -23.5505,
            startLongitude: -46.6333,
            startRadiusMeters: 50,
            contractualValue: const Money(100000),
            noShowPenaltyBps: 15000,
            windowStartUtc: DateTime.now().toUtc().subtract(
              const Duration(minutes: 10),
            ),
            windowEndUtc: DateTime.now().toUtc().add(
              const Duration(minutes: 50),
            ),
          );

          final state2 = ContractualExecutionState.create(
            organizationId: PostgresTestConfig.testOrgId,
            setId: setId2,
            contractId: contractId2, // Different contract
            planVersion: 1,
            startLatitude: -23.5505,
            startLongitude: -46.6333,
            startRadiusMeters: 50,
            contractualValue: const Money(100000),
            noShowPenaltyBps: 15000,
            windowStartUtc: DateTime.now().toUtc().subtract(
              const Duration(minutes: 10),
            ),
            windowEndUtc: DateTime.now().toUtc().add(
              const Duration(minutes: 50),
            ),
          );

          await repository.save(state1);
          await repository.save(state2);

          final contractStates = await repository.findByContract(
            contractId,
            organizationId: PostgresTestConfig.testOrgId,
          );

          expect(contractStates.isNotEmpty, isTrue);
          expect(
            contractStates.every((s) => s.contractId == contractId),
            isTrue,
          );
          expect(contractStates.any((s) => s.id == state1.id), isTrue);
          expect(
            contractStates.any((s) => s.id == state2.id),
            isFalse,
          ); // Should not bring state2
        },
      );
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
