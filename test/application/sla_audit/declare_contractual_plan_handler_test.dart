import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/contractual_service_input.dart';
import 'package:veraprob/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:veraprob/application/sla_audit/declare_contractual_plan_handler.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule_repository.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/admin/in_memory_active_vehicle_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_operational_zone_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:timezone/data/latest.dart' as tz;

const _orgId = 'org-1';

void main() {
  // ── Shared fixtures ──────────────────────────────────────
  late InMemoryPlanDeclarationRepository repository;
  late InMemorySlaAuditLedgerRepository ledger;
  late InMemoryOperationalZoneRepository zoneRepository;
  late DeclareContractualPlanHandler handler;

  /// Creates a handler with a pre-populated zone (INV-18 happy path).
  /// [activeVehicleCount] controls the vehicle gate for shift-based tests.
  /// [zones] overrides the default zone repository when provided.
  DeclareContractualPlanHandler makeHandler({
    int activeVehicleCount = 1,
    InMemoryOperationalZoneRepository? zones,
  }) {
    return DeclareContractualPlanHandler(
      repository: repository,
      ledger: ledger,
      ruleRepository: MockContractualRuleRepository(),
      contractRepository: MockContractRepository(),
      zoneRepository: zones ?? zoneRepository,
      vehicleRepository: InMemoryActiveVehicleRepository(
        countsByOrg: {_orgId: activeVehicleCount},
      ),
    );
  }

  setUp(() async {
    tz.initializeTimeZones();
    repository = InMemoryPlanDeclarationRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    zoneRepository = InMemoryOperationalZoneRepository();

    // Pre-populate one zone so the INV-18 gate passes in all baseline tests.
    await zoneRepository.save(
      OperationalZone.create(
        organizationId: _orgId,
        name: 'Garagem Central',
        type: ZoneType.garagem,
      ),
    );

    handler = makeHandler();
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
    int contractualValueCents = 15000,
    int noShowPenaltyBps = 15000,
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
      contractualValueCents: contractualValueCents,
      noShowPenaltyBps: noShowPenaltyBps,
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
      organizationId: _orgId,
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
    test('happy path — aggregate created, persisted, event in ledger', () async {
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

      // Two entries appended: PLAN_DECLARED + CONTRACT_ACTIVATED (draft→active)
      expect(ledger.entries, hasLength(2));
      expect(ledger.entries.first.type, 'PLAN_DECLARED');
      expect(ledger.entries.last.type, 'CONTRACT_ACTIVATED');
    });

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

      final results = await repository.findByContract(
        'c-1',
        organizationId: _orgId,
      );
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
        final found = await repository.findByContract(
          '',
          organizationId: _orgId,
        );
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

      // Ledger received 2 events: PLAN_DECLARED + CONTRACT_ACTIVATED
      expect(ledger.entries, hasLength(2));
    });

    // ── INV-18: Engine Activation Gate ───────────────────
    group('INV-18 Engine Activation Gate', () {
      test(
        'throws DomainException when no operational zones exist for the org',
        () async {
          final emptyZones = InMemoryOperationalZoneRepository();
          final handlerWithNoZones = makeHandler(zones: emptyZones);

          await expectLater(
            () => handlerWithNoZones.handle(makeCommand()),
            throwsA(
              isA<DomainException>().having(
                (e) => e.message,
                'message',
                'No operational zones configured for this organization',
              ),
            ),
          );

          // Nothing persisted — gate fired before any write
          final found = await repository.findByContract(
            'contract-1',
            organizationId: _orgId,
          );
          expect(found, isEmpty);
          expect(ledger.entries, isEmpty);
        },
      );

      test(
        'throws DomainException when shift-based plan declared with no active vehicles',
        () async {
          final handlerNoVehicles = makeHandler(activeVehicleCount: 0);

          // Build a minimal but valid ShiftPattern (zone IDs only need to be non-empty;
          // existence is not validated at command time — that happens at projection time).
          final pattern = ShiftPattern.create(
            index: 0,
            daysOfWeek: [DayOfWeek.monday],
            departureTimeLocal: '07:00',
            arrivalTimeLocal: '08:00',
            timezone: 'America/Sao_Paulo',
            originZoneId: 'zone-origin',
            destinationZoneId: 'zone-destination',
            penalties: SLAPenalties.create(
              noShowPenaltyBps: 10000,
              delayToleranceMinutes: 15,
              delayPenaltyPerMinute: const Money(100),
              downgradePenaltyFlat: const Money(5000),
            ),
          );

          final shiftCommand = DeclareContractualPlanCommand(
            organizationId: _orgId,
            contractId: 'contract-1',
            declaredByUserId: 'user-1',
            planVersion: 1,
            originalFileHash: 'hash',
            declaredAtUtc: DateTime.utc(2026, 2, 25),
            shiftPatterns: [pattern],
            contractualValueCents: 10000,
          );

          await expectLater(
            () => handlerNoVehicles.handle(shiftCommand),
            throwsA(
              isA<DomainException>().having(
                (e) => e.message,
                'message',
                'No active vehicles found for this organization',
              ),
            ),
          );

          final found = await repository.findByContract(
            'contract-1',
            organizationId: _orgId,
          );
          expect(found, isEmpty);
          expect(ledger.entries, isEmpty);
        },
      );
    });
  });
}

class MockContractualRuleRepository implements ContractualRuleRepository {
  @override
  Future<RuleSnapshot> getActiveSnapshotForContract(
    String orgId,
    String contractId,
  ) async {
    return const RuleSnapshot([]);
  }

  @override
  Future<void> saveRule(ContractualRule rule) async {}
}

/// Returns a draft [Contract] for any non-empty contractId.
/// Allows the handler to validate and activate contracts during tests.
class MockContractRepository implements ContractRepository {
  @override
  Future<Contract?> findById(
    String id, {
    required String organizationId,
  }) async {
    if (id.isEmpty) return null;
    return Contract.reconstitute(
      id: id,
      organizationId: organizationId,
      name: 'Test Contract',
      contractorName: 'Test Contractor',
      validFromUtc: DateTime.utc(2026, 1, 1),
      validUntilUtc: DateTime.utc(2026, 12, 31),
      status: ContractStatus.draft,
      createdAtUtc: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<void> save(Contract contract) async {}

  @override
  Future<List<Contract>> findByOrganization(
    String organizationId, {
    ContractStatus? status,
  }) async {
    return [];
  }
}
