import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:veraprob/application/sla_audit/contractual_financial_closing_service.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_snapshot_generator.dart';
import 'package:veraprob/domain/shared/brazil_time.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import '../../mocks/fake_date_time_provider.dart';

void main() {
  late InMemoryContractualExecutionStateRepository executionRepo;
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late InMemorySlaAuditLedgerRepository ledgerRepo;
  late ContractualFinancialSnapshotGenerator generator;
  late ContractualFinancialClosingService closingService;
  late FakeDateTimeProvider clock;

  setUp(() {
    tz.initializeTimeZones();
    BrazilTime.ensureInitialized();
    clock = FakeDateTimeProvider(DateTime.utc(2026, 3, 2, 12, 0));
    executionRepo = InMemoryContractualExecutionStateRepository();
    snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    ledgerRepo = InMemorySlaAuditLedgerRepository();
    generator = ContractualFinancialSnapshotGenerator(
      executionRepo: executionRepo,
      snapshotRepo: snapshotRepo,
      ledgerRepo: ledgerRepo,
      clock: clock,
    );
    closingService = ContractualFinancialClosingService(generator: generator);
  });

  group('ContractualFinancialClosingService', () {
    test(
      'first onTick records current day without generating snapshot',
      () async {
        await closingService.onTick('org-1');

        expect(closingService.lastClosedOperationalDateUtc, isNotNull);

        final snapshots = await snapshotRepo.findAll(organizationId: 'org-1');
        expect(snapshots, isEmpty);
      },
    );

    test('subsequent onTick on same day does not generate snapshot', () async {
      await closingService.onTick('org-1');
      await closingService.onTick('org-1');
      await closingService.onTick('org-1');

      final snapshots = await snapshotRepo.findAll(organizationId: 'org-1');
      expect(snapshots, isEmpty);
    });

    // Note: Testing day transition would require mocking BrazilTime.nowBrazil()
    // which is currently static. This is a known limitation for unit testing
    // the actual transition logic. The generator itself is fully tested.
  });
}
