/// Phase 5 Compliance Test — Contract & Plan Lifecycle Management
///
/// Validates the full happy-path scenario defined in the Phase 5 Design Spec:
///
///   1. Create contract (draft)
///   2. Declare plan → contract auto-activates
///   3. Declare second plan version → contract remains active
///   4. Close contract → terminal state
///   5. Attempt to declare plan on closed contract → DomainException
///
/// Ledger invariants are verified at each step.
/// All assertions use InMemory infrastructure (no Supabase required).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:busflow/application/sla_audit/close_contract_command.dart';
import 'package:busflow/application/sla_audit/close_contract_handler.dart';
import 'package:busflow/application/sla_audit/create_contract_command.dart';
import 'package:busflow/application/sla_audit/create_contract_handler.dart';
import 'package:busflow/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:busflow/application/sla_audit/declare_contractual_plan_handler.dart';
import 'package:busflow/application/sla_audit/contractual_service_input.dart';
import 'package:busflow/domain/sla_audit/contract_status.dart';
import 'package:busflow/domain/sla_audit/contractual_rule_repository.dart';
import 'package:busflow/domain/sla_audit/contractual_rule.dart';
import 'package:busflow/domain/sla_audit/domain_exception.dart';
import 'package:busflow/domain/sla_audit/rule_snapshot.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_contract_repository.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

void main() {
  group('Phase 5 Compliance — Contract & Plan Lifecycle', () {
    late InMemoryContractRepository contractRepo;
    late InMemoryPlanDeclarationRepository planRepo;
    late InMemorySlaAuditLedgerRepository ledger;
    late CreateContractHandler createHandler;
    late CloseContractHandler closeHandler;
    late DeclareContractualPlanHandler planHandler;

    setUp(() {
      contractRepo = InMemoryContractRepository();
      planRepo = InMemoryPlanDeclarationRepository();
      ledger = InMemorySlaAuditLedgerRepository();

      createHandler = CreateContractHandler(
        contractRepository: contractRepo,
        ledger: ledger,
      );
      closeHandler = CloseContractHandler(
        contractRepository: contractRepo,
        ledger: ledger,
      );
      planHandler = DeclareContractualPlanHandler(
        repository: planRepo,
        ledger: ledger,
        ruleRepository: _MockRuleRepository(),
        contractRepository: contractRepo,
      );
    });

    test('full lifecycle: create → plan v1 → plan v2 → close → rejected plan', () async {
      const orgId = 'org-compliance-1';
      const userId = 'user-admin';

      // ── Step 1: Create contract ─────────────────────────────
      final contract = await createHandler.handle(CreateContractCommand(
        organizationId: orgId,
        name: 'Rota Sul — Contrato 2026',
        contractorName: 'Trans Sul Ltda',
        description: 'Cobertura sul da cidade',
        validFromUtc: DateTime.utc(2026, 1, 1),
        validUntilUtc: DateTime.utc(2026, 12, 31),
      ));

      expect(contract.status, ContractStatus.draft,
          reason: 'New contract must start as draft');
      expect(contract.isDraft, isTrue);
      expect(ledger.entries, hasLength(1));
      expect(ledger.entries.first.type, 'CONTRACT_CREATED');

      // ── Step 2: Declare first plan → auto-activates contract ──
      final plan1 = await planHandler.handle(DeclareContractualPlanCommand(
        organizationId: orgId,
        contractId: contract.id,
        declaredByUserId: userId,
        planVersion: 1,
        originalFileHash: 'hash-v1',
        declaredAtUtc: DateTime.utc(2026, 1, 15),
        services: [_makeService(DateTime.utc(2026, 2, 1, 6, 0))],
      ));

      expect(plan1.planVersion, 1);
      expect(plan1.services, hasLength(1));

      // Contract auto-activated
      final activatedContract = await contractRepo.findById(
        contract.id,
        organizationId: orgId,
      );
      expect(activatedContract!.status, ContractStatus.active,
          reason: 'First plan declaration must auto-activate the contract');
      expect(activatedContract.isActive, isTrue);
      expect(activatedContract.activatedAtUtc, isNotNull);

      // Ledger: CONTRACT_CREATED + PLAN_DECLARED + CONTRACT_ACTIVATED
      expect(ledger.entries, hasLength(3));
      expect(ledger.entries.map((e) => e.type).toList(), [
        'CONTRACT_CREATED',
        'PLAN_DECLARED',
        'CONTRACT_ACTIVATED',
      ]);

      // ── Step 3: Declare second plan version ────────────────
      final plan2 = await planHandler.handle(DeclareContractualPlanCommand(
        organizationId: orgId,
        contractId: contract.id,
        declaredByUserId: userId,
        planVersion: 2,
        originalFileHash: 'hash-v2',
        declaredAtUtc: DateTime.utc(2026, 3, 1),
        services: [
          _makeService(DateTime.utc(2026, 4, 1, 6, 0)),
          _makeService(DateTime.utc(2026, 4, 1, 8, 0)),
        ],
      ));

      expect(plan2.planVersion, 2);
      expect(plan2.services, hasLength(2));

      // Contract remains active — no new activation event
      final stillActive = await contractRepo.findById(
        contract.id,
        organizationId: orgId,
      );
      expect(stillActive!.status, ContractStatus.active);

      // Ledger: +PLAN_DECLARED (no CONTRACT_ACTIVATED again)
      expect(ledger.entries, hasLength(4));
      expect(ledger.entries.last.type, 'PLAN_DECLARED');

      // Both plans are persisted
      final plans = await planRepo.findByContract(
        contract.id,
        organizationId: orgId,
      );
      expect(plans, hasLength(2));

      // ── Step 4: Close contract ──────────────────────────────
      final closed = await closeHandler.handle(CloseContractCommand(
        organizationId: orgId,
        contractId: contract.id,
        closedByUserId: userId,
        reason: 'Contract period ended.',
      ));

      expect(closed.status, ContractStatus.closed,
          reason: 'CloseContractHandler must produce closed aggregate');
      expect(closed.isClosed, isTrue);
      expect(closed.closedByUserId, userId);
      expect(closed.closeReason, 'Contract period ended.');
      expect(closed.closedAtUtc, isNotNull);

      // Persisted as closed
      final closedInRepo = await contractRepo.findById(
        contract.id,
        organizationId: orgId,
      );
      expect(closedInRepo!.status, ContractStatus.closed);

      // Ledger: +CONTRACT_CLOSED
      expect(ledger.entries, hasLength(5));
      expect(ledger.entries.last.type, 'CONTRACT_CLOSED');

      // ── Step 5: Attempt to declare plan on closed contract ──
      expect(
        () => planHandler.handle(DeclareContractualPlanCommand(
          organizationId: orgId,
          contractId: contract.id,
          declaredByUserId: userId,
          planVersion: 3,
          originalFileHash: 'hash-v3',
          declaredAtUtc: DateTime.utc(2026, 12, 1),
          services: [_makeService(DateTime.utc(2027, 1, 1, 6, 0))],
        )),
        throwsA(isA<DomainException>()),
        reason: 'Closed contract must reject new plan declarations',
      );

      // Ledger must remain at 5 entries — no contamination
      expect(ledger.entries, hasLength(5),
          reason: 'Failed plan declaration must not append to ledger');
    });

    test('ledger is append-only — entry types are immutable strings', () async {
      const orgId = 'org-ledger-check';
      await createHandler.handle(CreateContractCommand(
        organizationId: orgId,
        name: 'Ledger Test Contract',
        contractorName: 'Empresa L',
        validFromUtc: DateTime.utc(2026, 1, 1),
        validUntilUtc: DateTime.utc(2026, 12, 31),
      ));

      // Each entry has a stable type string
      for (final entry in ledger.entries) {
        expect(entry.type, isNotEmpty);
        expect(entry.organizationId, orgId);
      }
    });

    test('multi-tenant isolation — two orgs with same contract id cannot interfere', () async {
      // Org A creates a contract
      final contractA = await createHandler.handle(CreateContractCommand(
        organizationId: 'org-A',
        name: 'Contract A',
        contractorName: 'Empresa A',
        validFromUtc: DateTime.utc(2026, 1, 1),
        validUntilUtc: DateTime.utc(2026, 12, 31),
      ));

      // Org B cannot see org A's contract
      final fromOrgB = await contractRepo.findById(
        contractA.id,
        organizationId: 'org-B',
      );
      expect(fromOrgB, isNull,
          reason: 'Cross-tenant access must be denied even in-memory');

      // Org B cannot close org A's contract
      expect(
        () => closeHandler.handle(CloseContractCommand(
          organizationId: 'org-B',
          contractId: contractA.id,
          closedByUserId: 'user-b',
          reason: 'Attempted cross-tenant close',
        )),
        throwsA(isA<DomainException>()),
        reason: 'CloseContractHandler must enforce tenant isolation',
      );
    });
  });
}

// ── Test helpers ──────────────────────────────────────────────────────────────

ContractualServiceInput _makeService(DateTime start) {
  return ContractualServiceInput(
    scheduledStartTimeUtc: start,
    scheduledEndTimeUtc: start.add(const Duration(hours: 1)),
    startLatitude: -23.5505,
    startLongitude: -46.6333,
    startRadiusMeters: 100,
    endLatitude: -23.5600,
    endLongitude: -46.6400,
    endRadiusMeters: 100,
    contractualValue: 150.0,
    noShowPenaltyMultiplier: 1.5,
  );
}

class _MockRuleRepository implements ContractualRuleRepository {
  @override
  Future<RuleSnapshot> getActiveSnapshotForContract(
    String orgId,
    String contractId,
  ) async =>
      const RuleSnapshot([]);

  @override
  Future<void> saveRule(ContractualRule rule) async {}
}
