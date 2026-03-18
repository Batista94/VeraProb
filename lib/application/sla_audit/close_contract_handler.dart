import '../../domain/enums/user_permissions.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/contract.dart';
import '../../domain/sla_audit/contract_repository.dart';
import '../../domain/sla_audit/domain_exception.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import 'close_contract_command.dart';
import 'sla_ledger_mapper.dart';

/// Application handler for [CloseContractCommand].
///
/// Finds the [Contract], delegates the state transition to [Contract.close()],
/// persists the updated aggregate, and appends the [ContractClosedEvent]
/// to the immutable ledger.
///
/// Contains NO domain logic — all state validation is delegated to [Contract.close()].
/// Authorization is enforced here (Application Layer) before any I/O is performed.
class CloseContractHandler {
  final ContractRepository _contractRepository;
  final SlaAuditLedgerRepository _ledger;
  final RbacService _rbac;

  CloseContractHandler({
    required ContractRepository contractRepository,
    required SlaAuditLedgerRepository ledger,
    required RbacService rbac,
  }) : _contractRepository = contractRepository,
       _ledger = ledger,
       _rbac = rbac;

  /// Handles the command by transitioning the contract to [closed],
  /// persisting the updated aggregate, and appending the event to the ledger.
  ///
  /// Returns the updated [Contract] aggregate.
  ///
  /// Throws [DomainException] if:
  /// - [callerRole] does not have [UserPermission.canCloseContracts]
  /// - Contract is not found for the given [organizationId]
  /// - Contract is already closed
  /// - [closedByUserId] or [reason] are empty
  Future<Contract> handle(CloseContractCommand command) async {
    // 1. RBAC check — before any I/O (prevents oracle attacks)
    if (!_rbac.can(command.callerRole, UserPermission.canCloseContracts)) {
      throw const DomainException('Unauthorized.');
    }

    // 2. Load aggregate — scoped to organizationId (tenant isolation)
    final existing = await _contractRepository.findById(
      command.contractId,
      organizationId: command.organizationId,
    );
    if (existing == null) {
      throw DomainException(
        'Contract "${command.contractId}" not found for organization '
        '"${command.organizationId}".',
      );
    }

    // 3. Transition state via domain method (validates invariants)
    final closed = existing.close(
      closedByUserId: command.closedByUserId,
      reason: command.reason,
    );

    // 4. Persist updated aggregate
    await _contractRepository.save(closed);

    // 5. Append domain events to the immutable ledger
    for (final event in closed.domainEvents) {
      final entry = SlaLedgerMapper.mapToEntry(event);
      await _ledger.append(entry);
    }

    // 6. Return updated aggregate
    return closed;
  }
}
