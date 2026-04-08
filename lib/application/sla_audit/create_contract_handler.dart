import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'create_contract_command.dart';
import 'sla_ledger_mapper.dart';

/// Application handler for [CreateContractCommand].
///
/// Creates a [Contract] aggregate in draft status, persists it,
/// and appends the [ContractCreatedEvent] to the immutable ledger.
///
/// Contains NO domain logic — all validation is delegated to
/// [Contract.create()].
///
/// Throws [DomainException] if any invariant is violated —
/// in which case nothing is persisted and the ledger remains untouched.
class CreateContractHandler {
  final ContractRepository _contractRepository;
  final SlaAuditLedgerRepository _ledger;
  final IDateTimeProvider _clock;

  CreateContractHandler({
    required ContractRepository contractRepository,
    required SlaAuditLedgerRepository ledger,
    required IDateTimeProvider clock,
  }) : _contractRepository = contractRepository,
       _ledger = ledger,
       _clock = clock;

  /// Handles the command by creating the aggregate, persisting it,
  /// and appending all domain events to the ledger.
  ///
  /// Returns the created [Contract] aggregate.
  Future<Contract> handle(CreateContractCommand command) async {
    // 1. Create aggregate via domain factory (validates all invariants)
    final contract = Contract.create(
      organizationId: command.organizationId,
      name: command.name,
      contractorName: command.contractorName,
      description: command.description,
      validFromUtc: command.validFromUtc,
      validUntilUtc: command.validUntilUtc,
      financialCeiling: command.financialCeilingCents != null
          ? Money(command.financialCeilingCents!)
          : null,
      nowUtc: _clock.now(),
    );

    // 2. Persist aggregate
    try {
      await _contractRepository.save(contract);
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw DomainException(e.message);
      rethrow;
    }

    // 3. Append domain events to the immutable ledger
    for (final event in contract.domainEvents) {
      final entry = SlaLedgerMapper.mapToEntry(event);
      await _ledger.append(entry);
    }

    // 4. Return aggregate
    return contract;
  }
}
