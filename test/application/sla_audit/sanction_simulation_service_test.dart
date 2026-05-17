import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/sanction_simulation_service.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contract_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

void main() {
  final nowUtc = DateTime.parse('2026-04-08T12:00:00Z').toUtc();
  late InMemoryContractRepository contractRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late SanctionSimulationService service;
  late FakeDateTimeProvider clock;

  const orgId = 'org-test-1';

  setUp(() {
    contractRepo = InMemoryContractRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    clock = FakeDateTimeProvider(nowUtc);
    service = SanctionSimulationService(
      ledger: ledger,
      contracts: contractRepo,
      clock: clock,
    );
  });

  Future<void> seedContract() async {
    final contract = Contract.create(
      organizationId: orgId,
      name: 'Contrato Simulação',
      contractorName: 'Trans Teste Ltda',
      validFromUtc: DateTime.utc(2026, 1, 1),
      validUntilUtc: DateTime.utc(2026, 12, 31),
      nowUtc: nowUtc,
    );
    await contractRepo.save(contract);
  }

  group('SanctionSimulationService', () {
    test(
      'simulateSpeedViolation throws when no contracts exist for the org',
      () async {
        expect(
          () => service.simulateSpeedViolation(
            organizationId: orgId,
            vehiclePlate: 'TEST-0001',
          ),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'simulateSpeedViolation appends a SANCTION_RECOMMENDED entry to the ledger',
      () async {
        await seedContract();
        final countBefore = ledger.entries.length;

        await service.simulateSpeedViolation(
          organizationId: orgId,
          vehiclePlate: 'TEST-0001',
          speed: 92.0,
          limit: 80.0,
        );

        expect(ledger.entries.length, greaterThan(countBefore));
      },
    );

    test('seedActiveSanctions appends two ledger entries', () async {
      await seedContract();

      await service.seedActiveSanctions(organizationId: orgId);

      expect(ledger.entries.length, 2);
    });
  });
}
