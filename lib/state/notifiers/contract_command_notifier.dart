import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:veraprob/application/sla_audit/close_contract_command.dart';
import 'package:veraprob/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/application/sla_audit/contractual_service_input.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'contract_command_state.dart';

/// Notifier that executes contract commands (close, declare plan, etc.) and
/// **automatically** synchronization UI state via manual updates — preventing
/// the "UI pipoco" (stale state after mutation).
///
/// **Anti-Pipoco Strategy (INV-33):**
/// Instead of invalidating and forcing a full DB re-fetch (data blackout),
/// this Notifier updates the local [contractDetailProvider] using `copyWith`.
/// It preserves historical data (executions, financials) while updating
/// mutable fields (status, plan versions).
///
/// **INV-33 (Idempotency):**
/// - The [idempotencyKey] is stable across network retries.
/// - [onFormChanged] recycles the key ONLY if a previous error occurred.
/// - Uses [ref.keepAlive()] to prevent unmount during in-flight operations.
class ContractCommandNotifier
    extends AutoDisposeFamilyNotifier<ContractCommandState, String> {
  ContractCommandNotifier();

  @override
  ContractCommandState build(String contractId) {
    // [INV-33] Stable Key on build
    return ContractCommandState(idempotencyKey: const Uuid().v4());
  }

  /// Called by the UI whenever form data changes.
  ///
  /// **Intention Differentiation:** Generates a new key only if the
  /// current state is an error, signifying the user corrected data.
  void onFormChanged() {
    if (state.status is AsyncError) {
      state = state.withNewKey();
    }
  }

  /// Executes a close contract command.
  Future<Contract?> closeContract({
    required String contractId,
    required String closedByUserId,
    required String reason,
    required UserRole callerRole,
    required String sessionId,
    required String organizationId,
  }) async {
    final keepAlive = ref.keepAlive();
    state = state.copyWith(status: const AsyncLoading());

    try {
      final handler = ref.read(closeContractHandlerProvider);

      final command = CloseContractCommand(
        organizationId: organizationId,
        contractId: contractId,
        closedByUserId: closedByUserId,
        reason: reason,
        callerRole: callerRole,
        sessionId: sessionId,
        idempotencyKey: state.idempotencyKey,
      );

      final updatedContract = await handler.handle(command);

      // ── Anti-Pipoco State Sync ────────────────────────────────────
      _syncDetailView(contractId, updatedContract);
      ref.invalidate(contractListProvider);

      state = state.copyWith(status: const AsyncData(null));
      return updatedContract;
    } catch (e, st) {
      state = state.copyWith(status: AsyncError(e, st));
      return null;
    } finally {
      keepAlive.close();
    }
  }

  /// Executes a declare contractual plan command.
  Future<String?> declareContractualPlan({
    required String contractId,
    required String declaredByUserId,
    required int planVersion,
    required String originalFileHash,
    required DateTime declaredAtUtc,
    required String sessionId,
    required String organizationId,
    List<ContractualServiceInput> services = const [],
    List<ShiftPattern> shiftPatterns = const [],
    int contractualValueCents = 0,
  }) async {
    final keepAlive = ref.keepAlive();
    state = state.copyWith(status: const AsyncLoading());

    try {
      final handler = ref.read(declareContractualPlanHandlerProvider);

      final command = DeclareContractualPlanCommand(
        organizationId: organizationId,
        contractId: contractId,
        declaredByUserId: declaredByUserId,
        planVersion: planVersion,
        originalFileHash: originalFileHash,
        declaredAtUtc: declaredAtUtc,
        sessionId: sessionId,
        services: services,
        shiftPatterns: shiftPatterns,
        contractualValueCents: contractualValueCents,
        idempotencyKey: state.idempotencyKey,
      );

      final plan = await handler.handle(command);

      // ── Anti-Pipoco State Sync ────────────────────────────────────
      // Not yet implementing deep contract update for plans since
      // the handler manages multiple aggregates. Best to invalidate
      // the detail view for plans to ensure projection sync.
      ref.invalidate(contractDetailProvider(contractId));
      ref.invalidate(contractListProvider);

      state = state.copyWith(status: const AsyncData(null));
      return plan.id;
    } catch (e, st) {
      state = state.copyWith(status: AsyncError(e, st));
      return null;
    } finally {
      keepAlive.close();
    }
  }

  /// Internally maps Domain Contract -> View Model and updates state.
  void _syncDetailView(String contractId, Contract domain) {
    final currentView = ref
        .read(contractDetailProvider(contractId))
        .valueOrNull;
    if (currentView != null) {
      final updatedView = currentView.copyWith(
        summary: currentView.summary.copyWith(
          status: _mapStatus(domain.status),
          activatedAtUtc: domain.activatedAtUtc,
        ),
      );

      ref
          .read(contractDetailProvider(contractId).notifier)
          .updateState(updatedView);
    }
  }

  ContractStatusView _mapStatus(ContractStatus domainStatus) {
    return switch (domainStatus) {
      ContractStatus.draft => ContractStatusView.draft,
      ContractStatus.awaitingContractorAcceptance =>
        ContractStatusView.awaitingContractorAcceptance,
      ContractStatus.active => ContractStatusView.active,
      ContractStatus.closed => ContractStatusView.closed,
    };
  }
}

/// Provider family for the contract command notifier.
final contractCommandNotifierProvider =
    AutoDisposeNotifierProvider.family<
      ContractCommandNotifier,
      ContractCommandState,
      String
    >(ContractCommandNotifier.new);
