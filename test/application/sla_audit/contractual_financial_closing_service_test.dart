import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:busflow/application/sla_audit/contractual_financial_closing_service.dart';
import 'package:busflow/application/sla_audit/projections/contractual_financial_snapshot_generator.dart';
import 'package:busflow/core/time/brazil_time.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';

void main() {
  late InMemoryContractualExecutionStateRepository executionRepo;
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late ContractualFinancialSnapshotGenerator generator;
  late ContractualFinancialClosingService closingService;

  setUp(() {
    tz.initializeTimeZones();
    BrazilTime.ensureInitialized();
    executionRepo = InMemoryContractualExecutionStateRepository();
    snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    generator = ContractualFinancialSnapshotGenerator(
      executionRepo: executionRepo,
      snapshotRepo: snapshotRepo,
    );
    closingService = ContractualFinancialClosingService(generator: generator);
  });

  group('ContractualFinancialClosingService', () {
    test(
      'first onTick records current day without generating snapshot',
      () async {
        await closingService.onTick();

        expect(closingService.lastClosedOperationalDateUtc, isNotNull);

        final snapshots = await snapshotRepo.findAll();
        expect(snapshots, isEmpty);
      },
    );

    test('subsequent onTick on same day does not generate snapshot', () async {
      await closingService.onTick();
      await closingService.onTick();
      await closingService.onTick();

      final snapshots = await snapshotRepo.findAll();
      expect(snapshots, isEmpty);
    });

    // Note: Testing day transition would require mocking BrazilTime.nowBrazil()
    // which is currently static. This is a known limitation for unit testing
    // the actual transition logic. The generator itself is fully tested.
  });
}
