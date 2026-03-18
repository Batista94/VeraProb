import 'package:uuid/uuid.dart';

import '../../domain/enums/user_permissions.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/contract_repository.dart';
import '../../domain/sla_audit/domain_exception.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import 'contract_approval_command_service.dart';
import 'sla_ledger_mapper.dart';
import 'submit_contract_for_approval_command.dart';

/// Application handler for [SubmitContractForApprovalCommand].
///
/// Transitions a draft contract to [awaitingContractorAcceptance] and
/// generates a shareable review token for the contractor.
///
/// Flow:
///   1. RBAC check ([canApproveContractAcceptance])
///   2. Load contract (tenant-scoped)
///   3. Domain guard via [Contract.submitForApproval]
///   4. Generate token in Dart (INV-7: Deterministic Replay)
///   5. Atomic RPC: update status + insert token row
///   6. Append [ContractSubmittedForApprovalEvent] to ledger
///   7. Return raw token string (UI builds the sharable link)
class SubmitContractForApprovalHandler {
  final ContractRepository _contractRepository;
  final ContractApprovalCommandService _approvalService;
  final SlaAuditLedgerRepository _ledger;
  final RbacService _rbac;

  static const _tokenTtl = Duration(days: 30);

  SubmitContractForApprovalHandler({
    required ContractRepository contractRepository,
    required ContractApprovalCommandService approvalService,
    required SlaAuditLedgerRepository ledger,
    required RbacService rbac,
  }) : _contractRepository = contractRepository,
       _approvalService = approvalService,
       _ledger = ledger,
       _rbac = rbac;

  /// Returns the raw [token] string on success.
  /// The UI is responsible for constructing the full review URL.
  ///
  /// Throws [DomainException] if:
  /// - Caller lacks [UserPermission.canApproveContractAcceptance]
  /// - Contract not found for the given [organizationId]
  /// - Contract is not in [draft] status
  Future<String> handle(SubmitContractForApprovalCommand command) async {
    // 1. RBAC — before any I/O
    if (!_rbac.can(
      command.callerRole,
      UserPermission.canApproveContractAcceptance,
    )) {
      throw const DomainException(
        'Unauthorized: canApproveContractAcceptance required.',
      );
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

    // 3. Generate token in Dart (INV-7)
    const uuid = Uuid();
    final tokenId = uuid.v4();
    final token = uuid.v4();
    final expiresAtUtc = DateTime.now().toUtc().add(_tokenTtl);

    // 4. Domain guard — [Contract.submitForApproval] validates status
    final submitted = existing.submitForApproval(reviewToken: token);

    // 5. Atomic RPC: transitions contract + inserts token row
    await _approvalService.submitForApproval(
      contractId: command.contractId,
      organizationId: command.organizationId,
      tokenId: tokenId,
      token: token,
      expiresAtUtc: expiresAtUtc,
    );

    // 6. Append domain event to immutable ledger
    for (final event in submitted.domainEvents) {
      final entry = SlaLedgerMapper.mapToEntry(event);
      await _ledger.append(entry);
    }

    // 7. Return token for UI link construction
    return token;
  }
}
