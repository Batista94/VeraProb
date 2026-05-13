import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/shared/idempotent_handler_mixin.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/shared/idempotency_store.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'close_contract_command.dart';
import 'sla_ledger_mapper.dart';

/// Application handler for [CloseContractCommand].
///
/// **INV-33 (Idempotency):** Uses [IdempotentHandlerMixin] to provide
/// atomic execution, cached error replays, and dual-write self-healing.
class CloseContractHandler with IdempotentHandlerMixin {
  final TenantValidationService _tenantValidator;
  final ContractRepository _contractRepository;
  final SlaAuditLedgerRepository _ledger;
  final RbacService _rbac;
  final IDateTimeProvider _clock;
  final IIdempotencyStore _idempotencyStore;

  CloseContractHandler({
    required TenantValidationService tenantValidator,
    required ContractRepository contractRepository,
    required SlaAuditLedgerRepository ledger,
    required RbacService rbac,
    required IDateTimeProvider clock,
    required IIdempotencyStore idempotencyStore,
  }) : _tenantValidator = tenantValidator,
       _contractRepository = contractRepository,
       _ledger = ledger,
       _rbac = rbac,
       _clock = clock,
       _idempotencyStore = idempotencyStore;

  /// Handles the command by transitioning the contract to [closed].
  Future<Contract> handle(CloseContractCommand command) async {
    return await executeWithIdempotency<Contract>(
      idempotencyStore: _idempotencyStore,
      idempotencyKey: command.idempotencyKey,
      userId: command.closedByUserId,
      commandPath: 'close_contract',
      organizationId: command.organizationId,
      clock: _clock,
      staleThresholdMinutes: 5,
      businessLogic: () => _execute(command),
      toIdempotencyDto: (contract) => {
        'id': contract.id,
        'version': contract.version,
      },
      reloadEntity: (dto) => _contractRepository.findById(
        dto['id'] as String,
        organizationId: command.organizationId,
      ),
      // [Self-Heal] Recover from partial success (DB commitment but Idempotency Crash)
      recoverIfAlreadyCompleted: () async {
        final current = await _contractRepository.findById(
          command.contractId,
          organizationId: command.organizationId,
        );
        return current?.status == ContractStatus.closed ? current : null;
      },
    );
  }

  /// Extracts the core business logic.
  Future<Contract> _execute(CloseContractCommand command) async {
    // 1. Tenant match (INV-1)
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC check
    if (!_rbac.can(command.callerRole, UserPermission.canCloseContracts)) {
      throw const DomainException('Unauthorized.');
    }

    // 3. Load aggregate
    final existing = await _contractRepository.findById(
      command.contractId,
      organizationId: command.organizationId,
    );
    if (existing == null) {
      throw DomainException('Contract "${command.contractId}" not found.');
    }

    // 4. Transition state
    final closed = existing.close(
      closedByUserId: command.closedByUserId,
      reason: command.reason,
      nowUtc: _clock.nowUtc(),
    );

    // 5. Persist (Optimistic Locking INV-32)
    final saved = await _contractRepository.save(closed);

    // 6. Append events to ledger
    for (final event in saved.domainEvents) {
      final entry = SlaLedgerMapper.mapToEntry(event);
      await _ledger.append(entry);
    }

    return saved;
  }
}
