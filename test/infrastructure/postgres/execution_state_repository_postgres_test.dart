import 'package:pactaflow/domain/sla_audit/contractual_execution_state.dart';
import 'package:pactaflow/domain/shared/money.dart';
import 'package:pactaflow/infrastructure/sla_audit/postgres_contractual_execution_state_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'postgres_test_config.dart';

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
          repository = PostgresContractualExecutionStateRepository(client);
        }
      });

      test('1. Insert and full domain reconstitution cycle works', () async {
        final setId = uuid.v4();
        final contractId = uuid.v4();

        final state = ContractualExecutionState.create(organizationId: 'org-1', 
          setId: setId,
          contractId: contractId,
          planVersion: 1,
          startLatitude: -23.5505,
          startLongitude: -46.6333,
          startRadiusMeters: 50,
          plannedVehicleId: 'veh-01',
          contractualValue: Money.fromDouble(1500.0), // R$ 15,00
          noShowPenaltyMultiplier: 1.5,
          windowStartUtc: DateTime.now().toUtc().subtract(
            const Duration(minutes: 10),
          ),
          windowEndUtc: DateTime.now().toUtc().add(const Duration(minutes: 50)),
        );

        // Mutates to executed state to test bindings
        final executionTime = DateTime.now().toUtc();
        state.bindExecution(
          vehicleId: 'veh-01',
          latitude: -23.5506,
          longitude: -46.6334,
          timestampUtc: executionTime,
        );

        // Save aggregate
        expect(
          () async => await repository.save(state),
          returnsNormally,
          reason:
              'The state should be persisted successfully in the DB natively',
        );

        // Find By Id
        final loadedState = await repository.findBySetId(state.setId);

        expect(loadedState, isNotNull);
        expect(loadedState!.id, state.id);
        expect(loadedState.setId, setId);
        expect(loadedState.contractId, contractId);
        expect(loadedState.status.name, 'executed');

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

          final state1 = ContractualExecutionState.create(organizationId: 'org-1', 
            setId: uuid.v4(),
            contractId: contractId,
            planVersion: 1,
            startLatitude: -23.5505,
            startLongitude: -46.6333,
            startRadiusMeters: 50,
            contractualValue: Money.fromDouble(1000.0),
            noShowPenaltyMultiplier: 1.5,
            windowStartUtc: DateTime.now().toUtc().subtract(
              const Duration(minutes: 10),
            ),
            windowEndUtc: DateTime.now().toUtc().add(
              const Duration(minutes: 50),
            ),
          );

          final state2 = ContractualExecutionState.create(organizationId: 'org-1', 
            setId: uuid.v4(),
            contractId: uuid.v4(), // Different contract
            planVersion: 1,
            startLatitude: -23.5505,
            startLongitude: -46.6333,
            startRadiusMeters: 50,
            contractualValue: Money.fromDouble(1000.0),
            noShowPenaltyMultiplier: 1.5,
            windowStartUtc: DateTime.now().toUtc().subtract(
              const Duration(minutes: 10),
            ),
            windowEndUtc: DateTime.now().toUtc().add(
              const Duration(minutes: 50),
            ),
          );

          await repository.save(state1);
          await repository.save(state2);

          final contractStates = await repository.findByContract(contractId, organizationId: 'org-1');

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
