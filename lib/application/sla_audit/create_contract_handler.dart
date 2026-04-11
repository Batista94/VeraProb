import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
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
/// **Security (INV-1):** Step 1 validates that the [organizationId] in the
/// command matches the authenticated user's JWT claim. This is a Fail-Fast
/// check — if it fails, [SovereigntyViolationException] is thrown before
/// any domain factory, repository, or ledger operation is invoked.
///
/// Contains NO domain logic — all validation is delegated to
/// [Contract.create()].
///
/// Throws [DomainException] if any invariant is violated —
/// in which case nothing is persisted and the ledger remains untouched.
class CreateContractHandler {
  final TenantValidationService _tenantValidator;
  final ContractRepository _contractRepository;
  final SlaAuditLedgerRepository _ledger;
  final IDateTimeProvider _clock;

  CreateContractHandler({
    required TenantValidationService tenantValidator,
    required ContractRepository contractRepository,
    required SlaAuditLedgerRepository ledger,
    required IDateTimeProvider clock,
  }) : _tenantValidator = tenantValidator,
       _contractRepository = contractRepository,
       _ledger = ledger,
       _clock = clock;

  /// Handles the command by validating tenant isolation, creating the aggregate,
  /// persisting it, and appending all domain events to the ledger.
  ///
  /// Returns the created [Contract] aggregate.
  ///
  /// **INV-1 Fail-Fast:** Throws [SovereigntyViolationException] if the
  /// command's [organizationId] does not match the JWT claim — before any
  /// repository or domain factory is invoked.
  Future<Contract> handle(CreateContractCommand command) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync ────────────────────────────
    // Validate that the org_id in the command matches the authenticated
    // user's JWT claim. Throws SovereigntyViolationException on mismatch.
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // ── Step 2: Create aggregate via domain factory ──────────────────────
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

    // ── Step 3: Persist aggregate ────────────────────────────────────────
    try {
      await _contractRepository.save(contract);
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') throw DomainException(e.message);
      rethrow;
    }

    // ── Step 4: Append domain events to the immutable ledger ─────────────
    for (final event in contract.domainEvents) {
      final entry = SlaLedgerMapper.mapToEntry(event);
      await _ledger.append(entry);
    }

    // ── Step 5: Return aggregate ─────────────────────────────────────────
    return contract;
  }
}
