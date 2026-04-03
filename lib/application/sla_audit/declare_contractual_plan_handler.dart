import '../../domain/admin/i_active_vehicle_repository.dart';
import '../../domain/shared/money.dart';
import '../../domain/sla_audit/contract_repository.dart';
import '../../domain/sla_audit/contractual_rule_repository.dart';
import '../../domain/sla_audit/contractual_service_execution.dart';
import '../../domain/sla_audit/domain_exception.dart';
import '../../domain/sla_audit/operational_zone_repository.dart';
import '../../domain/sla_audit/plan_declaration.dart';
import '../../domain/sla_audit/plan_declaration_repository.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import 'declare_contractual_plan_command.dart';
import 'shift_projection_service.dart';
import 'sla_ledger_mapper.dart';

/// Application service that handles the declaration of a contractual plan.
///
/// This is a direct handler — it does NOT go through [AuthorizingCommandBus].
/// Plan declaration is an administrative setup action, not a real-time
/// operational mutation subject to RBAC/Trust Backbone policies.
///
/// The handler contains NO domain logic. All validation and entity creation
/// is delegated to domain factories:
/// - [Contract.assertCanReceivePlan()] — guards the pre-condition
/// - [Contract.activate()] — automatic draft→active on first plan
/// - [ContractualServiceExecution.create()] / [PlanDeclaration.create()]
/// - [PlanDeclaration.createWithShiftPatterns()] — B2B mode
/// - [ShiftProjectionService.projectDays()] — eager 30-day SET projection (B2B)
///
/// INV-18 (Engine Activation Gate) is enforced here before any persistence:
/// - At least one [OperationalZone] must exist for the organization.
/// - For shift-based plans, at least one active vehicle must also exist.
///
/// If any [DomainException] is thrown during creation, nothing is persisted.
class DeclareContractualPlanHandler {
  final PlanDeclarationRepository _repository;
  final SlaAuditLedgerRepository _ledger;
  final ContractualRuleRepository _ruleRepository;
  final ContractRepository _contractRepository;

  /// Required for INV-18: verifies spatial context before engine activation.
  final OperationalZoneRepository _zoneRepository;

  /// Required for INV-18: verifies active vehicle availability for shift-based plans.
  final IActiveVehicleRepository _vehicleRepository;

  /// Optional projection service. When provided, B2B shift-based plans eagerly
  /// project SETs for the next 30 days immediately after declaration (B1 decision).
  /// Null = projection disabled (backwards compatible — used in tests without projection).
  final ShiftProjectionService? _projectionService;

  DeclareContractualPlanHandler({
    required PlanDeclarationRepository repository,
    required SlaAuditLedgerRepository ledger,
    required ContractualRuleRepository ruleRepository,
    required ContractRepository contractRepository,
    required OperationalZoneRepository zoneRepository,
    required IActiveVehicleRepository vehicleRepository,
    ShiftProjectionService? projectionService,
  }) : _repository = repository,
       _ledger = ledger,
       _ruleRepository = ruleRepository,
       _contractRepository = contractRepository,
       _zoneRepository = zoneRepository,
       _vehicleRepository = vehicleRepository,
       _projectionService = projectionService;

  /// Handles the command by creating the aggregate, persisting it,
  /// and appending all domain events to the ledger.
  ///
  /// Returns the created [PlanDeclaration] aggregate.
  ///
  /// Throws [DomainException] if any invariant is violated —
  /// in which case nothing is persisted and the ledger remains untouched.
  Future<PlanDeclaration> handle(DeclareContractualPlanCommand command) async {
    final isShiftBased = command.shiftPatterns.isNotEmpty;
    final isManual = command.services.isNotEmpty;

    if (!isShiftBased && !isManual) {
      throw const DomainException(
        'Command must include either services (manual) or shiftPatterns (B2B)',
      );
    }
    if (isShiftBased && isManual) {
      throw const DomainException(
        'services and shiftPatterns are mutually exclusive',
      );
    }
    if (isShiftBased && command.contractualValueCents <= 0) {
      throw const DomainException(
        'contractualValueCents must be > 0 for shift-based plans',
      );
    }

    // INV-18: Engine Activation Gate — spatial context is mandatory.
    // The engine cannot produce spatial SLA evaluations without at least one
    // geofenced zone. For shift-based plans, an active vehicle is also required.
    final zones = await _zoneRepository.findByOrganization(
      command.organizationId,
    );
    if (zones.isEmpty) {
      throw const DomainException(
        'No operational zones configured for this organization',
      );
    }
    if (isShiftBased) {
      final activeVehicleCount = await _vehicleRepository
          .countActiveByOrganization(command.organizationId);
      if (activeVehicleCount == 0) {
        throw const DomainException(
          'No active vehicles found for this organization',
        );
      }
    }

    // 0. Validate Contract exists and can receive a plan (Phase 5)
    final contract = await _contractRepository.findById(
      command.contractId,
      organizationId: command.organizationId,
    );
    if (contract == null) {
      throw DomainException(
        'Contract "${command.contractId}" not found for organization '
        '"${command.organizationId}".',
      );
    }
    contract.assertCanReceivePlan();

    // 1. Fetch the active Rule Snapshot
    final ruleSnapshot = await _ruleRepository.getActiveSnapshotForContract(
      command.organizationId,
      command.contractId,
    );

    PlanDeclaration plan;

    if (isShiftBased) {
      // ── B2B shift-based mode ─────────────────────────────
      plan = PlanDeclaration.createWithShiftPatterns(
        organizationId: command.organizationId,
        contractId: command.contractId,
        declaredAtUtc: command.declaredAtUtc,
        declaredByUserId: command.declaredByUserId,
        planVersion: command.planVersion,
        originalFileHash: command.originalFileHash,
        ruleSnapshot: ruleSnapshot,
        shiftPatterns: command.shiftPatterns,
      );
    } else {
      // ── Manual mode (baseline) ───────────────────────────
      final services = command.services
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
              plannedVehicleId: input.plannedVehicleId,
              contractualValue: input.contractualValue,
              noShowPenaltyBps: input.noShowPenaltyBps,
            ),
          )
          .toList();

      plan = PlanDeclaration.create(
        organizationId: command.organizationId,
        contractId: command.contractId,
        declaredAtUtc: command.declaredAtUtc,
        declaredByUserId: command.declaredByUserId,
        planVersion: command.planVersion,
        originalFileHash: command.originalFileHash,
        ruleSnapshot: ruleSnapshot,
        services: services,
      );
    }

    // 2. Persist plan aggregate
    await _repository.save(plan);

    // 3. Eager SET projection for B2B plans (B1 decision: 30 days on declaration)
    if (isShiftBased && _projectionService != null) {
      final projected = await _projectionService.projectDays(
        plan,
        from: command.declaredAtUtc,
        contractualValue: Money(command.contractualValueCents),
      );
      await _repository.saveProjectedSets(
        plan.id,
        projected,
        organizationId: plan.organizationId,
      );
    }

    // 4. Append plan domain events to the ledger
    for (final event in plan.domainEvents) {
      final entry = SlaLedgerMapper.mapToEntry(event);
      await _ledger.append(entry);
    }

    // 5. If contract is still draft, activate it (first plan — draft→active)
    if (contract.isDraft) {
      final activated = contract.activate();
      await _contractRepository.save(activated);
      for (final event in activated.domainEvents) {
        final entry = SlaLedgerMapper.mapToEntry(event);
        await _ledger.append(entry);
      }
    }

    // 6. Return plan aggregate
    return plan;
  }
}
