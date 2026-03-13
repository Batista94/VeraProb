/// Phase 5.4 / 5.10 — Automated Validation Scenarios
///
/// Fonte da verdade: `docs/governance/roadmap.md` › Phase 5 › 5.4 / 5.10 Validation
///
/// Cenários automatizados (testes manuais com Supabase são responsabilidade do operador):
///
///   Cenário 5.1 — Plano criado via UI gera ledger entry `PLAN_DECLARED`
///                 (mesmo comportamento da API direta)
///   Cenário 5.1-B2B — Plano declarado COM ShiftPattern gera ledger entry `PLAN_DECLARED`
///   Cenário 5.2 — Plano publicado não pode ser editado;
///                 apenas nova versão é aceita
///   Cenário 5.3 — Operador de Org A não vê contratos de Org B na listagem
///   Cenário 5.4 — Contrato encerrado não aceita novos planos
///
/// Todos os cenários usam infraestrutura InMemory — sem Supabase ativo.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:pactaflow/application/sla_audit/close_contract_command.dart';
import 'package:pactaflow/application/sla_audit/close_contract_handler.dart';
import 'package:pactaflow/application/sla_audit/create_contract_command.dart';
import 'package:pactaflow/application/sla_audit/create_contract_handler.dart';
import 'package:pactaflow/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:pactaflow/application/sla_audit/declare_contractual_plan_handler.dart';
import 'package:pactaflow/application/sla_audit/contractual_service_input.dart';
import 'package:pactaflow/application/sla_audit/projections/contract_query_service_in_memory.dart';
import 'package:pactaflow/application/sla_audit/shift_projection_service.dart';
import 'package:pactaflow/domain/sla_audit/contractual_rule_repository.dart';
import 'package:pactaflow/domain/sla_audit/contractual_rule.dart';
import 'package:pactaflow/domain/sla_audit/domain_exception.dart';
import 'package:pactaflow/domain/sla_audit/operational_zone.dart';
import 'package:pactaflow/domain/sla_audit/rule_snapshot.dart';
import 'package:pactaflow/domain/sla_audit/shift_pattern.dart';
import 'package:pactaflow/domain/sla_audit/sla_penalties.dart';
import 'package:pactaflow/domain/shared/money.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_contract_repository.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_operational_alert_repository.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_operational_zone_repository.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:pactaflow/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:pactaflow/application/sla_audit/projections/sla_execution_query_service_in_memory.dart';

// ── Shared helpers ─────────────────────────────────────────────────────────

ContractualServiceInput _makeService([DateTime? start]) {
  final s = start ?? DateTime.utc(2026, 3, 1, 6, 0);
  return ContractualServiceInput(
    scheduledStartTimeUtc: s,
    scheduledEndTimeUtc: s.add(const Duration(hours: 1)),
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

class _StubRuleRepository implements ContractualRuleRepository {
  @override
  Future<RuleSnapshot> getActiveSnapshotForContract(
    String orgId,
    String contractId,
  ) async =>
      const RuleSnapshot([]);

  @override
  Future<void> saveRule(ContractualRule rule) async {}
}

// ── Test suite ─────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

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
      ruleRepository: _StubRuleRepository(),
      contractRepository: contractRepo,
    );
  });

  // ── Cenário 5.1 ───────────────────────────────────────────────────────────

  group('Cenário 5.1 — Plano criado via UI gera PLAN_DECLARED no ledger', () {
    test(
      '5.1.a: handler produz entrada PLAN_DECLARED idêntica ao fluxo de API',
      () async {
        // Simula exatamente o que o DeclareContractPlanForm faz:
        // (1) cria contrato, (2) monta command com hash SHA-256, (3) chama handler
        final contract = await createHandler.handle(CreateContractCommand(
          organizationId: 'org-5-1',
          name: 'Rota Leste',
          contractorName: 'Trans Leste',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        // Hash simulado como SHA-256 de JSON (formato definido no Design Spec)
        const uiGeneratedHash =
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

        final plan = await planHandler.handle(DeclareContractualPlanCommand(
          organizationId: 'org-5-1',
          contractId: contract.id,
          declaredByUserId: 'operador-1',
          planVersion: 1,
          originalFileHash: uiGeneratedHash,
          declaredAtUtc: DateTime.utc(2026, 1, 15),
          services: [_makeService()],
        ));

        // Hash preservado intacto no aggregate
        expect(plan.originalFileHash, uiGeneratedHash);

        // Ledger contém PLAN_DECLARED (e CONTRACT_CREATED + CONTRACT_ACTIVATED)
        final types = ledger.entries.map((e) => e.type).toList();
        expect(types.contains('PLAN_DECLARED'), isTrue,
            reason: 'Ledger deve conter PLAN_DECLARED');

        // Entrada PLAN_DECLARED aponta para o plan correto
        final planEntry = ledger.entries.firstWhere((e) => e.type == 'PLAN_DECLARED');
        expect(planEntry.organizationId, 'org-5-1');
      },
    );

    test(
      '5.1.b: hash do plano é preservado sem alteração pelo handler',
      () async {
        final contract = await createHandler.handle(CreateContractCommand(
          organizationId: 'org-5-1b',
          name: 'Rota Sul',
          contractorName: 'Trans Sul',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        const expectedHash = 'abc123deadbeef';

        final plan = await planHandler.handle(DeclareContractualPlanCommand(
          organizationId: 'org-5-1b',
          contractId: contract.id,
          declaredByUserId: 'operador-2',
          planVersion: 1,
          originalFileHash: expectedHash,
          declaredAtUtc: DateTime.utc(2026, 1, 10),
          services: [_makeService()],
        ));

        // Persisted plan preserves hash
        final found = await planRepo.findById(plan.id);
        expect(found!.originalFileHash, expectedHash);
      },
    );
  });

  // ── Cenário 5.2 ───────────────────────────────────────────────────────────

  group('Cenário 5.2 — Plano publicado não pode ser editado; apenas nova versão', () {
    test(
      '5.2.a: PlanDeclaration expõe services como lista imutável',
      () async {
        final contract = await createHandler.handle(CreateContractCommand(
          organizationId: 'org-5-2',
          name: 'Contrato Imutável',
          contractorName: 'Empresa I',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        final plan = await planHandler.handle(DeclareContractualPlanCommand(
          organizationId: 'org-5-2',
          contractId: contract.id,
          declaredByUserId: 'user-1',
          planVersion: 1,
          originalFileHash: 'hash-v1',
          declaredAtUtc: DateTime.utc(2026, 1, 10),
          services: [_makeService()],
        ));

        // A lista services deve ser imutável — tentativa de mutação lança UnsupportedError
        expect(
          () => plan.services.clear(),
          throwsUnsupportedError,
          reason: 'services de PlanDeclaration é lista somente-leitura',
        );
        expect(
          () => plan.services.removeAt(0),
          throwsUnsupportedError,
          reason: 'Não é possível remover items do services publicado',
        );
      },
    );

    test(
      '5.2.b: nova versão do plano cria aggregate distinto (não sobrescreve)',
      () async {
        final contract = await createHandler.handle(CreateContractCommand(
          organizationId: 'org-5-2b',
          name: 'Contrato Versões',
          contractorName: 'Empresa V',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        final plan1 = await planHandler.handle(DeclareContractualPlanCommand(
          organizationId: 'org-5-2b',
          contractId: contract.id,
          declaredByUserId: 'user-1',
          planVersion: 1,
          originalFileHash: 'hash-v1',
          declaredAtUtc: DateTime.utc(2026, 1, 10),
          services: [_makeService(DateTime.utc(2026, 2, 1, 6, 0))],
        ));

        final plan2 = await planHandler.handle(DeclareContractualPlanCommand(
          organizationId: 'org-5-2b',
          contractId: contract.id,
          declaredByUserId: 'user-1',
          planVersion: 2,
          originalFileHash: 'hash-v2',
          declaredAtUtc: DateTime.utc(2026, 2, 1),
          services: [
            _makeService(DateTime.utc(2026, 3, 1, 6, 0)),
            _makeService(DateTime.utc(2026, 3, 1, 8, 0)),
          ],
        ));

        // Dois aggregates com IDs distintos
        expect(plan1.id, isNot(equals(plan2.id)));
        expect(plan1.planVersion, 1);
        expect(plan2.planVersion, 2);

        // Versão 1 ainda existe — não foi sobrescrita
        final found1 = await planRepo.findById(plan1.id);
        expect(found1, isNotNull);
        expect(found1!.planVersion, 1);
        expect(found1.originalFileHash, 'hash-v1');

        // Versão 2 existe com dados distintos
        final found2 = await planRepo.findById(plan2.id);
        expect(found2!.planVersion, 2);
        expect(found2.services, hasLength(2));

        // Ambas as versões listadas para o mesmo contrato
        final allPlans = await planRepo.findByContract(
          contract.id,
          organizationId: 'org-5-2b',
        );
        expect(allPlans, hasLength(2));
      },
    );

    test(
      '5.2.c: PlanDeclaration.domainEvents são imutáveis após criação',
      () async {
        final contract = await createHandler.handle(CreateContractCommand(
          organizationId: 'org-5-2c',
          name: 'Contrato Eventos',
          contractorName: 'Empresa E',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        final plan = await planHandler.handle(DeclareContractualPlanCommand(
          organizationId: 'org-5-2c',
          contractId: contract.id,
          declaredByUserId: 'user-1',
          planVersion: 1,
          originalFileHash: 'hash-v1',
          declaredAtUtc: DateTime.utc(2026, 1, 10),
          services: [_makeService()],
        ));

        expect(
          () => plan.domainEvents.clear(),
          throwsUnsupportedError,
          reason: 'domainEvents de PlanDeclaration é imutável',
        );
      },
    );
  });

  // ── Cenário 5.3 ───────────────────────────────────────────────────────────

  group('Cenário 5.3 — Operador de Org A não vê contratos de Org B', () {
    test(
      '5.3.a: ContractRepository.findByOrganization isola por tenant',
      () async {
        // Org A cria 2 contratos
        await createHandler.handle(CreateContractCommand(
          organizationId: 'org-A',
          name: 'Contrato A1',
          contractorName: 'Empresa A',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));
        await createHandler.handle(CreateContractCommand(
          organizationId: 'org-A',
          name: 'Contrato A2',
          contractorName: 'Empresa A',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        // Org B cria 1 contrato
        await createHandler.handle(CreateContractCommand(
          organizationId: 'org-B',
          name: 'Contrato B1',
          contractorName: 'Empresa B',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        // Org A vê só seus contratos
        final orgAContracts = await contractRepo.findByOrganization('org-A');
        expect(orgAContracts, hasLength(2));
        expect(orgAContracts.every((c) => c.organizationId == 'org-A'), isTrue);

        // Org B vê só o seu
        final orgBContracts = await contractRepo.findByOrganization('org-B');
        expect(orgBContracts, hasLength(1));
        expect(orgBContracts.first.name, 'Contrato B1');
      },
    );

    test(
      '5.3.b: ContractQueryServiceInMemory.listContracts isola por tenant',
      () async {
        final execStateRepo = InMemoryContractualExecutionStateRepository();
        final slaQueryService = SlaExecutionQueryServiceInMemory(repo: execStateRepo);

        final queryService = ContractQueryServiceInMemory(
          contractRepository: contractRepo,
          planRepository: planRepo,
          executionStateRepository: execStateRepo,
          slaExecutionQueryService: slaQueryService,
        );

        // Org A cria contrato
        final contractA = await createHandler.handle(CreateContractCommand(
          organizationId: 'org-A',
          name: 'Rota A',
          contractorName: 'Empresa A',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        // Org B cria contrato
        await createHandler.handle(CreateContractCommand(
          organizationId: 'org-B',
          name: 'Rota B',
          contractorName: 'Empresa B',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        // Query para Org A — só vê Rota A
        final summaries = await queryService.listContracts(
          organizationId: 'org-A',
        );
        expect(summaries, hasLength(1));
        expect(summaries.first.id, contractA.id);
        expect(summaries.first.name, 'Rota A');
      },
    );

    test(
      '5.3.c: findById com org errada retorna null (acesso cross-tenant negado)',
      () async {
        final contractA = await createHandler.handle(CreateContractCommand(
          organizationId: 'org-A',
          name: 'Contrato Privado A',
          contractorName: 'Empresa A',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        // Org B tenta acessar o ID do contrato de Org A
        final result = await contractRepo.findById(
          contractA.id,
          organizationId: 'org-B',
        );
        expect(result, isNull,
            reason: 'Acesso cross-tenant via findById deve ser negado');
      },
    );
  });

  // ── Cenário 5.4 ───────────────────────────────────────────────────────────

  group('Cenário 5.4 — Contrato encerrado não aceita novos planos', () {
    test(
      '5.4.a: DeclareContractualPlanHandler lança DomainException para contrato closed',
      () async {
        final contract = await createHandler.handle(CreateContractCommand(
          organizationId: 'org-5-4',
          name: 'Contrato Encerrado',
          contractorName: 'Empresa F',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        // Declara plano v1 (ativa o contrato)
        await planHandler.handle(DeclareContractualPlanCommand(
          organizationId: 'org-5-4',
          contractId: contract.id,
          declaredByUserId: 'user-1',
          planVersion: 1,
          originalFileHash: 'hash-v1',
          declaredAtUtc: DateTime.utc(2026, 1, 15),
          services: [_makeService()],
        ));

        // Fecha o contrato
        await closeHandler.handle(CloseContractCommand(
          organizationId: 'org-5-4',
          contractId: contract.id,
          closedByUserId: 'user-1',
          reason: 'Período encerrado.',
        ));

        final ledgerCountBeforeRejection = ledger.entries.length;

        // Tentativa de novo plano deve falhar
        expect(
          () => planHandler.handle(DeclareContractualPlanCommand(
            organizationId: 'org-5-4',
            contractId: contract.id,
            declaredByUserId: 'user-1',
            planVersion: 2,
            originalFileHash: 'hash-v2',
            declaredAtUtc: DateTime.utc(2026, 12, 1),
            services: [_makeService(DateTime.utc(2027, 1, 1, 6, 0))],
          )),
          throwsA(isA<DomainException>()),
          reason: 'Contrato closed deve rejeitar novos planos',
        );

        // Ledger não deve ter entradas novas após a rejeição
        expect(ledger.entries.length, ledgerCountBeforeRejection,
            reason: 'Rejeição não deve contaminar o ledger imutável');
      },
    );

    test(
      '5.4.b: assertCanReceivePlan impede plano mesmo em contrato draft encerrado diretamente',
      () async {
        final contract = await createHandler.handle(CreateContractCommand(
          organizationId: 'org-5-4b',
          name: 'Contrato Draft Encerrado',
          contractorName: 'Empresa G',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        // Fecha sem ter declarado nenhum plano (draft → closed diretamente)
        await closeHandler.handle(CloseContractCommand(
          organizationId: 'org-5-4b',
          contractId: contract.id,
          closedByUserId: 'admin-1',
          reason: 'Cancelado antes de operar.',
        ));

        expect(
          () => planHandler.handle(DeclareContractualPlanCommand(
            organizationId: 'org-5-4b',
            contractId: contract.id,
            declaredByUserId: 'user-1',
            planVersion: 1,
            originalFileHash: 'hash-v1',
            declaredAtUtc: DateTime.utc(2026, 1, 15),
            services: [_makeService()],
          )),
          throwsA(isA<DomainException>()),
          reason: 'Contrato closed (mesmo sem nunca ter sido active) deve rejeitar planos',
        );
      },
    );

    test(
      '5.4.c: contrato active (não closed) aceita plano normalmente',
      () async {
        final contract = await createHandler.handle(CreateContractCommand(
          organizationId: 'org-5-4c',
          name: 'Contrato Ativo',
          contractorName: 'Empresa H',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        // Plano v1 ativa o contrato
        await planHandler.handle(DeclareContractualPlanCommand(
          organizationId: 'org-5-4c',
          contractId: contract.id,
          declaredByUserId: 'user-1',
          planVersion: 1,
          originalFileHash: 'hash-v1',
          declaredAtUtc: DateTime.utc(2026, 1, 10),
          services: [_makeService()],
        ));

        // Plano v2 em contrato active deve ser aceito sem exceção
        final plan2 = await planHandler.handle(DeclareContractualPlanCommand(
          organizationId: 'org-5-4c',
          contractId: contract.id,
          declaredByUserId: 'user-1',
          planVersion: 2,
          originalFileHash: 'hash-v2',
          declaredAtUtc: DateTime.utc(2026, 2, 1),
          services: [_makeService(DateTime.utc(2026, 3, 1, 8, 0))],
        ));

        expect(plan2.planVersion, 2);
      },
    );
  });

  // ── Cenário 5.1-B2B ───────────────────────────────────────────────────────

  group('Cenário 5.1-B2B — Plano declarado com ShiftPattern gera PLAN_DECLARED', () {
    test(
      '5.1-B2B: handler com ShiftPattern produz PLAN_DECLARED idêntico ao fluxo manual',
      () async {
        // Infra B2B
        final zoneRepo = InMemoryOperationalZoneRepository();
        final alertRepo = InMemoryOperationalAlertRepository();
        final b2bPlanRepo = InMemoryPlanDeclarationRepository();
        final b2bLedger = InMemorySlaAuditLedgerRepository();
        final b2bContractRepo = InMemoryContractRepository();

        final origin = OperationalZone.create(
          organizationId: 'org-5-1-b2b',
          name: 'Origem B2B',
          type: ZoneType.garagem,
          geofence: const GeofenceConfiguration(
            latitude: -23.5505,
            longitude: -46.6333,
            radiusMeters: 200,
          ),
        );
        final dest = OperationalZone.create(
          organizationId: 'org-5-1-b2b',
          name: 'Destino B2B',
          type: ZoneType.cliente,
          geofence: const GeofenceConfiguration(
            latitude: -23.5600,
            longitude: -46.6400,
            radiusMeters: 200,
          ),
        );
        await zoneRepo.save(origin);
        await zoneRepo.save(dest);

        final projectionService = ShiftProjectionService(
          planRepo: b2bPlanRepo,
          zoneRepo: zoneRepo,
          alertRepo: alertRepo,
        );

        final b2bCreateHandler = CreateContractHandler(
          contractRepository: b2bContractRepo,
          ledger: b2bLedger,
        );
        final b2bPlanHandler = DeclareContractualPlanHandler(
          repository: b2bPlanRepo,
          ledger: b2bLedger,
          ruleRepository: _StubRuleRepository(),
          contractRepository: b2bContractRepo,
          projectionService: projectionService,
        );

        final contract = await b2bCreateHandler.handle(CreateContractCommand(
          organizationId: 'org-5-1-b2b',
          name: 'Contrato B2B Turno',
          contractorName: 'Trans B2B',
          validFromUtc: DateTime.utc(2026, 1, 1),
          validUntilUtc: DateTime.utc(2026, 12, 31),
        ));

        final pattern = ShiftPattern.create(
          index: 0,
          daysOfWeek: [DayOfWeek.monday, DayOfWeek.wednesday, DayOfWeek.friday],
          departureTimeLocal: '06:30',
          arrivalTimeLocal: '07:00',
          timezone: 'America/Sao_Paulo',
          originZoneId: origin.id,
          destinationZoneId: dest.id,
          penalties: SLAPenalties.create(
            noShowPenaltyMultiplier: 1.5,
            delayToleranceMinutes: 10,
            delayPenaltyPerMinute: const Money(100),
            downgradePenaltyFlat: const Money(5000),
          ),
        );

        final plan = await b2bPlanHandler.handle(DeclareContractualPlanCommand(
          organizationId: 'org-5-1-b2b',
          contractId: contract.id,
          declaredByUserId: 'operador-b2b',
          planVersion: 1,
          originalFileHash: 'b2b-hash-v1',
          declaredAtUtc: DateTime.utc(2026, 1, 15),
          shiftPatterns: [pattern],
          contractualValueCents: 15000,
        ));

        // Plano criado com ShiftPatterns
        expect(plan.planVersion, 1);
        expect(plan.shiftPatterns, hasLength(1));
        expect(plan.services, isEmpty,
            reason: 'Plano B2B não tem serviços manuais — SETs são projetados');

        // Ledger deve conter PLAN_DECLARED
        final types = b2bLedger.entries.map((e) => e.type).toList();
        expect(types.contains('PLAN_DECLARED'), isTrue,
            reason: 'ShiftPattern-based plan deve gerar PLAN_DECLARED no ledger');

        // Entrada PLAN_DECLARED aponta para org correta
        final planEntry =
            b2bLedger.entries.firstWhere((e) => e.type == 'PLAN_DECLARED');
        expect(planEntry.organizationId, 'org-5-1-b2b');

        // Contrato auto-ativado
        final types2 = b2bLedger.entries.map((e) => e.type).toList();
        expect(types2.contains('CONTRACT_ACTIVATED'), isTrue,
            reason: 'Primeiro plano B2B deve ativar o contrato');
      },
    );
  });
}
