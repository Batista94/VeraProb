import 'package:collection/collection.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/shared/idempotent_handler_mixin.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contract_events.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/idempotency_store.dart';
import 'package:veraprob/domain/sla_audit/operational_zone_repository.dart';
import 'package:veraprob/domain/admin/i_active_vehicle_repository.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'declare_contractual_plan_command.dart';
import 'sla_ledger_mapper.dart';

/// Application handler for [DeclareContractualPlanCommand].
///
/// **INV-33 (Idempotency):** Uses [IdempotentHandlerMixin] to provide
/// atomic execution and self-healing.
class DeclareContractualPlanHandler with IdempotentHandlerMixin {
  final TenantValidationService _tenantValidator;
  final PlanDeclarationRepository _repository;
  final SlaAuditLedgerRepository _ledger;
  final ContractRepository _contractRepository;
  final OperationalZoneRepository _zoneRepository;
  final IActiveVehicleRepository _vehicleRepository;
  final IDateTimeProvider _clock;
  final IIdempotencyStore _idempotencyStore;

  DeclareContractualPlanHandler({
    required TenantValidationService tenantValidator,
    required PlanDeclarationRepository repository,
    required SlaAuditLedgerRepository ledger,
    required ContractRepository contractRepository,
    required OperationalZoneRepository zoneRepository,
    required IActiveVehicleRepository vehicleRepository,
    required IDateTimeProvider clock,
    required IIdempotencyStore idempotencyStore,
  }) : _tenantValidator = tenantValidator,
       _repository = repository,
       _ledger = ledger,
       _contractRepository = contractRepository,
       _zoneRepository = zoneRepository,
       _vehicleRepository = vehicleRepository,
       _clock = clock,
       _idempotencyStore = idempotencyStore;

  Future<PlanDeclaration> handle(DeclareContractualPlanCommand command) async {
    return await executeWithIdempotency<PlanDeclaration>(
      idempotencyStore: _idempotencyStore,
      idempotencyKey: command.idempotencyKey,
      userId: command.declaredByUserId,
      commandPath: 'declare_contract_plan',
      organizationId: command.organizationId,
      businessLogic: () => _execute(command),
      toIdempotencyDto: (plan) => {
        'id': plan.id,
        'version': plan.planVersion,
        'hash': plan.originalFileHash,
      },
      reloadEntity: (dto) => _repository
          .findByContract(
            command.contractId,
            organizationId: command.organizationId,
          )
          .then(
            (list) => list.firstWhere((p) => p.planVersion == dto['version']),
          ),
      // [Self-Heal] Check if the specific hash/version already exists
      recoverIfAlreadyCompleted: () async {
        final existing = await _repository.findByContract(
          command.contractId,
          organizationId: command.organizationId,
        );
        return existing
            .where((p) => p.originalFileHash == command.originalFileHash)
            .firstOrNull;
      },
    );
  }

  Future<PlanDeclaration> _execute(
    DeclareContractualPlanCommand command,
  ) async {
    // 1. Tenant match (INV-1)
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. Domain Validation & Enrichment
    final contract = await _contractRepository.findById(
      command.contractId,
      organizationId: command.organizationId,
    );
    if (contract == null) throw const DomainException('Contract not found.');

    // 2.0.5 Contract state validation (INV-18)
    contract.assertCanReceivePlan();

    // 2.1 Active vehicle gate (INV-18)
    final vehicleCount = await _vehicleRepository.countActiveByOrganization(
      command.organizationId,
    );
    if (vehicleCount == 0) {
      throw const DomainException(
        'No active vehicles found for this organization',
      );
    }

    // 2.2 Operational zone gate (INV-18)
    final zones = await _zoneRepository.findByOrganization(
      command.organizationId,
    );
    if (zones.isEmpty) {
      throw const DomainException(
        'No operational zones configured for this organization',
      );
    }

    final plan = command.shiftPatterns.isNotEmpty
        ? PlanDeclaration.createWithShiftPatterns(
            organizationId: command.organizationId,
            contractId: command.contractId,
            declaredByUserId: command.declaredByUserId,
            planVersion: command.planVersion,
            originalFileHash: command.originalFileHash,
            declaredAtUtc: command.declaredAtUtc,
            ruleSnapshot: const RuleSnapshot([]), // Simplified for MVP
            shiftPatterns: command.shiftPatterns,
            nowUtc: _clock.now(),
          )
        : PlanDeclaration.create(
            organizationId: command.organizationId,
            contractId: command.contractId,
            declaredByUserId: command.declaredByUserId,
            planVersion: command.planVersion,
            originalFileHash: command.originalFileHash,
            declaredAtUtc: command.declaredAtUtc,
            ruleSnapshot: const RuleSnapshot([]), // Simplified for MVP
            services: command.services
                .map(
                  (input) => ContractualServiceExecution.create(
                    contractId: command.contractId,
                    scheduledStartTimeUtc: input.scheduledStartTimeUtc,
                    scheduledEndTimeUtc: input.scheduledEndTimeUtc,
                    startLatitude: input.startLatitude,
                    startLongitude: input.startLongitude,
                    startRadiusMeters: input.startRadiusMeters,
                    endLatitude: input.endLatitude,
                    endLongitude: input.endLongitude,
                    endRadiusMeters: input.endRadiusMeters,
                    contractualValue: Money(input.contractualValueCents),
                    noShowPenaltyBps: input.noShowPenaltyBps,
                  ),
                )
                .toList(),
            nowUtc: _clock.now(),
          );

    // 3. Persist
    final saved = await _repository.save(plan);

    // 4. Activate contract on first plan declaration (INV-18 happy path)
    if (command.planVersion == 1) {
      final now = _clock.now();
      final activatedContract = contract.activate(nowUtc: now);
      await _contractRepository.save(activatedContract);
    }

    // 5. Ledger entry
    if (saved.domainEvents.isNotEmpty) {
      final entry = SlaLedgerMapper.mapToEntry(saved.domainEvents.first);
      await _ledger.append(entry);

      // If this is the version 1, also emit CONTRACT_ACTIVATED to the ledger
      if (command.planVersion == 1) {
        final now = _clock.now();
        final activationEvent = ContractActivatedEvent(
          organizationId: command.organizationId,
          contractId: command.contractId,
          activatedAtUtc: now,
          occurredAtUtc: now,
        );
        await _ledger.append(SlaLedgerMapper.mapToEntry(activationEvent));
      }
    }

    return saved;
  }
}
