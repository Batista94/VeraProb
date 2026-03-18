import '../../domain/sla_audit/contract.dart';
import '../../domain/sla_audit/contract_repository.dart';
import '../../domain/sla_audit/domain_exception.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import 'clone_contract_command.dart';
import 'sla_ledger_mapper.dart';

/// Application handler for [CloneContractCommand].
///
/// Creates a new [Contract] in [draft] status, copying metadata from the
/// source contract. Validity dates are left blank (caller must provide
/// them separately via the UI).
///
/// **Invariants enforced:**
/// - Source contract must exist within [organizationId] — cross-tenant
///   cloning is rejected with [DomainException].
/// - [organizationId] comes from the JWT, never from the source record.
/// - The clone receives a new UUID and a new [ContractCreatedEvent].
/// - [clonedFromContractId] is stored as an immutable audit field.
class CloneContractHandler {
  final ContractRepository _contractRepository;
  final SlaAuditLedgerRepository _ledger;

  CloneContractHandler({
    required ContractRepository contractRepository,
    required SlaAuditLedgerRepository ledger,
  }) : _contractRepository = contractRepository,
       _ledger = ledger;

  /// Returns the newly created [Contract] draft.
  ///
  /// Throws [DomainException] if the source contract is not found within
  /// [command.organizationId] (tenant isolation check).
  Future<Contract> handle(
    CloneContractCommand command, {
    required DateTime validFromUtc,
    required DateTime validUntilUtc,
  }) async {
    // 1. Verify source belongs to the same org (tenant isolation)
    final source = await _contractRepository.findById(
      command.sourceContractId,
      organizationId: command.organizationId,
    );
    if (source == null) {
      throw const DomainException(
        'Contrato de origem não encontrado ou não pertence à sua organização.',
      );
    }

    // 2. Create new aggregate via domain factory (all invariants validated)
    final clone = Contract.createClone(
      organizationId: command.organizationId,
      name: command.name,
      contractorName: command.contractorName,
      description: command.description,
      validFromUtc: validFromUtc,
      validUntilUtc: validUntilUtc,
      clonedFromContractId: command.sourceContractId,
    );

    // 3. Persist
    await _contractRepository.save(clone);

    // 4. Append domain events to the immutable ledger
    for (final event in clone.domainEvents) {
      final entry = SlaLedgerMapper.mapToEntry(event);
      await _ledger.append(entry);
    }

    return clone;
  }
}
