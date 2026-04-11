import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/contract_events.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'accept_by_contractor_command.dart';
import 'contract_approval_command_service.dart';
import 'sla_ledger_mapper.dart';

/// Application handler for [AcceptByContractorCommand].
///
/// PUBLIC operation — no RBAC check. Token possession IS the authorization.
///
/// Flow:
///   1. Guard: token must not be empty
///   2. Atomic RPC: validate token, stamp used_at_utc, activate contract
///   3. Append [ContractAcceptedByContractorEvent] to the immutable ledger
///
/// The aggregate is NOT reloaded after the RPC — the RPC returns the minimal
/// data needed to construct the ledger event, avoiding a second round-trip.
///
/// Note: [_tenantValidator] is injected for API consistency but intentionally
/// not used — this is a public token-based operation with no session context.
class AcceptByContractorHandler {
  // ignore: unused_field
  final TenantValidationService _tenantValidator;
  final ContractApprovalCommandService _approvalService;
  final SlaAuditLedgerRepository _ledger;
  final IDateTimeProvider _clock;

  AcceptByContractorHandler({
    required TenantValidationService tenantValidator,
    required ContractApprovalCommandService approvalService,
    required SlaAuditLedgerRepository ledger,
    required IDateTimeProvider clock,
  }) : _tenantValidator = tenantValidator,
       _approvalService = approvalService,
       _ledger = ledger,
       _clock = clock;

  /// Throws [DomainException] if:
  /// - [command.token] is empty or whitespace
  /// - The RPC rejects the token (expired, used, or not found)
  Future<void> handle(AcceptByContractorCommand command) async {
    // 1. Fast-fail on empty token
    if (command.token.trim().isEmpty) {
      throw const DomainException('Review token must not be empty.');
    }

    // 2. Atomic RPC: validation + stamp + contract activation
    final result = await _approvalService.acceptByContractor(
      token: command.token,
    );

    // 3. Construct ledger event from RPC result (no second round-trip)
    final now = _clock.now();
    final event = ContractAcceptedByContractorEvent(
      organizationId: result.organizationId,
      occurredAtUtc: now,
      contractId: result.contractId,
      reviewToken: command.token,
      acceptedAtUtc: now,
    );

    final entry = SlaLedgerMapper.mapToEntry(event);
    await _ledger.append(entry);
  }
}
