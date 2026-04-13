import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
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
  final TenantValidationService _tenantValidator;
  final ContractRepository _contractRepository;
  final SlaAuditLedgerRepository _ledger;
  final RbacService _rbac;
  final IDateTimeProvider _clock;

  CloseContractHandler({
    required TenantValidationService tenantValidator,
    required ContractRepository contractRepository,
    required SlaAuditLedgerRepository ledger,
    required RbacService rbac,
    required IDateTimeProvider clock,
  }) : _tenantValidator = tenantValidator,
       _contractRepository = contractRepository,
       _ledger = ledger,
       _rbac = rbac,
       _clock = clock;

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
    // ── Step 1: INV-1 Fail-Fast Identity Sync ────────────────────────────
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC check — before any I/O (prevents oracle attacks)
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
      nowUtc: _clock.now(),
    );

    // 4. Persist updated aggregate — with auto-merge on conflict (INV-32)
    Contract saved;
    try {
      saved = await _contractRepository.save(closed);
    } on ConflictException catch (e) {
      if (e.isDeleted) {
        throw DomainException(
          'Contract "${command.contractId}" was deleted by another user.',
        );
      }
      if (e.isVersionMismatch) {
        // Forensic log: auto-merge triggered by concurrent modification
        await Sentry.addBreadcrumb(
          Breadcrumb(
            category: 'optimistic_lock',
            level: SentryLevel.warning,
            message:
                '[AUTO-MERGE] Contract ${command.contractId}: '
                'version conflict (client=${e.clientVersion}, server=${e.currentVersion}). '
                'Re-fetching latest and re-applying close transition.',
            data: {
              'contractId': command.contractId,
              'clientVersion': e.clientVersion,
              'serverVersion': e.currentVersion,
              'action': 'close',
            },
          ),
        );
        await Sentry.captureMessage(
          'Auto-merge: Contract ${command.contractId} closed with stale version '
          '(client=${e.clientVersion}, server=${e.currentVersion})',
          level: SentryLevel.warning,
        );

        // Auto-merge: re-fetch latest and re-apply the same transition
        final latest = await _contractRepository.findById(
          command.contractId,
          organizationId: command.organizationId,
        );
        if (latest == null) {
          throw DomainException(
            'Contract "${command.contractId}" was deleted by another user.',
          );
        }
        final merged = latest.close(
          closedByUserId: command.closedByUserId,
          reason: command.reason,
          nowUtc: _clock.now(),
        );

        // ── Second attempt with retry-storm protection ──────────────────
        // If the auto-merge ALSO fails (concurrency storm), we DO NOT retry
        // again — instead we fail-fast with a user-friendly message.
        // A single retry is the maximum acceptable under load; looping would
        // amplify contention and waste Supabase free-tier quotas (INV-16).
        try {
          saved = await _contractRepository.save(merged);
        } on ConflictException catch (e2) {
          // Forensic alert: concurrency storm detected (two conflicts in a row)
          await Sentry.addBreadcrumb(
            Breadcrumb(
              category: 'optimistic_lock',
              level: SentryLevel.error,
              message:
                  '[CONCURRENCY STORM] Contract ${command.contractId}: '
                  'auto-merge ALSO failed on retry (client=${e2.clientVersion}, '
                  'server=${e2.currentVersion}). Failing fast to prevent retry loop.',
              data: {
                'contractId': command.contractId,
                'firstConflictClientVersion': e.clientVersion,
                'secondConflictClientVersion': e2.clientVersion,
                'secondConflictServerVersion': e2.currentVersion,
                'action': 'close',
              },
            ),
          );
          Sentry.configureScope((scope) {
            scope.setTag('concurrency_storm', 'true');
            scope.setTag('contract_id', command.contractId);
            scope.setTag('action', 'close_contract_retry_failed');
          });
          // unawaited: fire-and-forget telemetry before throwing
          // ignore: unawaited_futures
          Sentry.captureException(e2);

          if (e2.isDeleted) {
            throw const DomainException(
              'Contrato fechado ou removido por outro operador. Atualize a tela.',
            );
          }
          // Generic message — no forensic details leaked (INV-26)
          throw const DomainException(
            'Conflito de concorrência ao fechar contrato. '
            'Atualize a tela e tente novamente.',
          );
        }

        await Sentry.addBreadcrumb(
          Breadcrumb(
            category: 'optimistic_lock',
            level: SentryLevel.info,
            message:
                '[AUTO-MERGE] Contract ${command.contractId}: merge succeeded. '
                'New version: ${saved.version}',
          ),
        );
      } else {
        rethrow; // Unexpected conflict type — fail-fast
      }
    }

    // 5. Append domain events to the immutable ledger
    for (final event in saved.domainEvents) {
      final entry = SlaLedgerMapper.mapToEntry(event);
      await _ledger.append(entry);
    }

    // 6. Return updated aggregate
    return saved;
  }
}
