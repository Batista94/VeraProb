import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/sla_audit/close_contract_command.dart';
import 'package:veraprob/application/sla_audit/projections/contract_detail_view.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/state/providers/contract_providers.dart';

/// Notifier that executes contract commands (close, activate, etc.) and
/// **automatically** invalidates cached queries — preventing the "UI pipoco"
/// (stale state after mutation).
///
/// **Anti-Pipoco Strategy:**
/// Instead of requiring every widget to call `ref.refresh(provider)` manually
/// after a mutation, this Notifier centralizes cache invalidation. After
/// any command succeeds, it invalidates:
/// - [contractDetailProvider(contractId)] — the detail view
/// - [contractListProvider] — the list summary
///
/// The UI observes these providers via Riverpod's reactive system and
/// re-renders automatically — no manual refresh needed.
///
/// **Usage:**
/// ```dart
/// final notifier = ref.read(contractCommandNotifierProvider(contractId));
/// final result = await notifier.closeContract(command);
/// // UI is already updating — no ref.refresh needed!
/// ```
class ContractCommandNotifier
    extends AutoDisposeFamilyNotifier<ContractDetailView?, String> {
  ContractCommandNotifier();

  @override
  ContractDetailView? build(String contractId) {
    return null; // Notifier has no state — it's a command dispatcher
  }

  /// Executes a close contract command.
  ///
  /// Returns the updated [Contract] aggregate for caller inspection.
  /// The UI state is automatically refreshed via cache invalidation.
  Future<Contract> closeContract(CloseContractCommand command) async {
    final handler = ref.read(closeContractHandlerProvider);

    // Execute the command (handler has Auto-Merge internally — INV-32)
    final updatedContract = await handler.handle(command);

    // ── Anti-Pipoco: Invalidate cached queries ──────────────────────
    // This triggers automatic re-fetch of the detail and list providers.
    // Widgets watching these providers will receive updated data without
    // manual ref.refresh calls.
    ref.invalidate(contractDetailProvider(command.contractId));
    ref.invalidate(contractListProvider);

    return updatedContract;
  }
}

/// Provider family for the contract command notifier.
///
/// Use [contractCommandNotifierProvider(contractId)] to get a notifier
/// scoped to a specific contract.
///
/// Example:
/// ```dart
/// final result = await ref
///     .read(contractCommandNotifierProvider(contractId))
///     .closeContract(command);
/// ```
final contractCommandNotifierProvider =
    AutoDisposeNotifierProvider.family<
      ContractCommandNotifier,
      ContractDetailView?,
      String
    >(ContractCommandNotifier.new);
