import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/application/sla_audit/contractual_service_input.dart';
import 'package:busflow/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:busflow/application/sla_audit/declare_contractual_plan_handler.dart';
import 'package:busflow/domain/sla_audit/domain_exception.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

void main() {
  // ── Shared fixtures ──────────────────────────────────────
  late InMemoryPlanDeclarationRepository repository;
  late InMemorySlaAuditLedgerRepository ledger;
  late DeclareContractualPlanHandler handler;

  setUp(() {
    repository = InMemoryPlanDeclarationRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    handler = DeclareContractualPlanHandler(
      repository: repository,
      ledger: ledger,
    );
  });

  ContractualServiceInput makeInput({
    DateTime? start,
    DateTime? end,
    double startLat = -23.5505,
    double startLng = -46.6333,
    int startRadius = 100,
    double endLat = -23.5600,
    double endLng = -46.6400,
    int endRadius = 100,
    double contractualValue = 150.0,
    double noShowPenaltyMultiplier = 1.5,
  }) {
    final s = start ?? DateTime.utc(2026, 3, 1, 6, 0);
    final e = end ?? s.add(const Duration(hours: 1));
    return ContractualServiceInput(
      scheduledStartTimeUtc: s,
      scheduledEndTimeUtc: e,
      startLatitude: startLat,
      startLongitude: startLng,
      startRadiusMeters: startRadius,
      endLatitude: endLat,
      endLongitude: endLng,
      endRadiusMeters: endRadius,
      contractualValue: contractualValue,
      noShowPenaltyMultiplier: noShowPenaltyMultiplier,
    );
  }

  DeclareContractualPlanCommand makeCommand({
    String contractId = 'contract-1',
    String userId = 'user-1',
    int version = 1,
    String hash = 'abc123hash',
    DateTime? declaredAt,
    List<ContractualServiceInput>? services,
  }) {
    return DeclareContractualPlanCommand(
      contractId: contractId,
      declaredByUserId: userId,
      planVersion: version,
      originalFileHash: hash,
      declaredAtUtc: declaredAt ?? DateTime.utc(2026, 2, 25),
      services: services ?? [makeInput()],
    );
  }

  // ── Tests ────────────────────────────────────────────────
  group('DeclareContractualPlanHandler', () {
    test(
      'happy path — aggregate created, persisted, event in ledger',
      () async {
        final plan = await handler.handle(makeCommand());

        // Aggregate was created with correct fields
        expect(plan.id, isNotEmpty);
        expect(plan.contractId, 'contract-1');
        expect(plan.declaredByUserId, 'user-1');
        expect(plan.planVersion, 1);
        expect(plan.services, hasLength(1));

        // Aggregate was persisted
        final persisted = await repository.findById(plan.id);
        expect(persisted, isNotNull);
        expect(persisted!.id, plan.id);

        // Exactly one entry was appended to the ledger
        expect(ledger.entries, hasLength(1));
        expect(ledger.entries.first.type, 'PLAN_DECLARED');
      },
    );

    test('persistence — findById returns saved aggregate', () async {
      final plan = await handler.handle(makeCommand());

      final found = await repository.findById(plan.id);
      expect(found, isNotNull);
      expect(found!.contractId, plan.contractId);
      expect(found.originalFileHash, plan.originalFileHash);
      expect(found.services, hasLength(plan.services.length));
    });

    test('findByContract — returns all declarations for a contract', () async {
      await handler.handle(
        makeCommand(
          contractId: 'c-1',
          services: [makeInput(start: DateTime.utc(2026, 3, 1, 6, 0))],
        ),
      );
      await handler.handle(
        makeCommand(
          contractId: 'c-1',
          version: 2,
          services: [makeInput(start: DateTime.utc(2026, 3, 1, 8, 0))],
        ),
      );
      await handler.handle(
        makeCommand(
          contractId: 'c-other',
          services: [makeInput(start: DateTime.utc(2026, 3, 1, 10, 0))],
        ),
      );

      final results = await repository.findByContract('c-1');
      expect(results, hasLength(2));
      expect(results.every((p) => p.contractId == 'c-1'), isTrue);
    });

    test(
      'DomainException propagation — nothing persisted on invalid input',
      () async {
        final invalidCommand = makeCommand(contractId: '');

        expect(
          () => handler.handle(invalidCommand),
          throwsA(isA<DomainException>()),
        );

        // Repository should be empty
        final found = await repository.findByContract('');
        expect(found, isEmpty);

        // Ledger should be empty
        expect(ledger.entries, isEmpty);
      },
    );

    test('multiple services — all SETs created from inputs', () async {
      final services = [
        makeInput(start: DateTime.utc(2026, 3, 1, 6, 0)),
        makeInput(start: DateTime.utc(2026, 3, 1, 8, 0)),
        makeInput(start: DateTime.utc(2026, 3, 1, 10, 0)),
      ];

      final plan = await handler.handle(makeCommand(services: services));

      expect(plan.services, hasLength(3));

      // All SETs should be unique
      final setIds = plan.services.map((s) => s.setId).toSet();
      expect(setIds, hasLength(3));

      // Ledger received exactly 1 event
      expect(ledger.entries, hasLength(1));
    });
  });
}
