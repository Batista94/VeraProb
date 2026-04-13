import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/admin/i_active_vehicle_repository.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule_repository.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/operational_zone_repository.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
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
  final TenantValidationService _tenantValidator;
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

  final IDateTimeProvider _clock;

  DeclareContractualPlanHandler({
    required TenantValidationService tenantValidator,
    required PlanDeclarationRepository repository,
    required SlaAuditLedgerRepository ledger,
    required ContractualRuleRepository ruleRepository,
    required ContractRepository contractRepository,
    required OperationalZoneRepository zoneRepository,
    required IActiveVehicleRepository vehicleRepository,
    required IDateTimeProvider clock,
    ShiftProjectionService? projectionService,
  }) : _tenantValidator = tenantValidator,
       _repository = repository,
       _ledger = ledger,
       _ruleRepository = ruleRepository,
       _contractRepository = contractRepository,
       _zoneRepository = zoneRepository,
       _vehicleRepository = vehicleRepository,
       _clock = clock,
       _projectionService = projectionService;

  /// Handles the command by creating the aggregate, persisting it,
  /// and appending all domain events to the ledger.
  ///
  /// Returns the created [PlanDeclaration] aggregate.
  ///
  /// Throws [DomainException] if any invariant is violated —
  /// in which case nothing is persisted and the ledger remains untouched.
  Future<PlanDeclaration> handle(DeclareContractualPlanCommand command) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync ────────────────────────────
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

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

    final nowUtc = _clock.now();
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
        nowUtc: nowUtc,
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
              contractualValue: Money(input.contractualValueCents),
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
        nowUtc: nowUtc,
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
      final activated = contract.activate(nowUtc: nowUtc);
      try {
        await _contractRepository.save(activated);
      } on ConflictException catch (e) {
        if (e.isVersionMismatch) {
          // Forensic log: auto-merge triggered by concurrent modification
          await Sentry.addBreadcrumb(
            Breadcrumb(
              category: 'optimistic_lock',
              level: SentryLevel.warning,
              message:
                  '[AUTO-MERGE] Contract ${command.contractId}: '
                  'version conflict during plan declaration activation '
                  '(client=${e.clientVersion}, server=${e.currentVersion}).',
              data: {
                'contractId': command.contractId,
                'clientVersion': e.clientVersion,
                'serverVersion': e.currentVersion,
                'action': 'activate_on_plan_declaration',
              },
            ),
          );
          await Sentry.captureMessage(
            'Auto-merge: Contract ${command.contractId} activated during plan declaration '
            'with stale version (client=${e.clientVersion}, server=${e.currentVersion})',
            level: SentryLevel.warning,
          );

          // Auto-merge: re-fetch and re-activate on latest
          final latest = await _contractRepository.findById(
            command.contractId,
            organizationId: command.organizationId,
          );
          if (latest != null && latest.isDraft) {
            final merged = latest.activate(nowUtc: nowUtc);
            try {
              await _contractRepository.save(merged);
            } on ConflictException catch (e2) {
              // Retry-storm protection: second conflict in a row → fail-fast.
              // We do NOT loop — this would amplify contention under load (INV-16).
              await Sentry.addBreadcrumb(
                Breadcrumb(
                  category: 'optimistic_lock',
                  level: SentryLevel.error,
                  message:
                      '[CONCURRENCY STORM] Contract ${command.contractId}: '
                      'auto-merge ALSO failed during plan activation '
                      '(client=${e2.clientVersion}, server=${e2.currentVersion}).',
                  data: {
                    'contractId': command.contractId,
                    'firstConflictClientVersion': e.clientVersion,
                    'secondConflictClientVersion': e2.clientVersion,
                    'action': 'activate_on_plan_declaration',
                  },
                ),
              );
              Sentry.configureScope((scope) {
                scope.setTag('concurrency_storm', 'true');
                scope.setTag('contract_id', command.contractId);
                scope.setTag('action', 'plan_activation_retry_failed');
              });
              // unawaited: fire-and-forget telemetry before silently skipping
              // ignore: unawaited_futures
              Sentry.captureException(e2);
              // Silently skip — plan was saved, contract may have been activated
              // by another operator. Non-fatal for this flow.
            }
          }
          // If latest is null or not draft → silently skip (race: already activated)
        } else {
          rethrow;
        }
      }
      for (final event in activated.domainEvents) {
        final entry = SlaLedgerMapper.mapToEntry(event);
        await _ledger.append(entry);
      }
    }

    // 6. Return plan aggregate
    return plan;
  }
}
