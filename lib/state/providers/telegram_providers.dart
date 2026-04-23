import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/telegram/generate_telegram_binding_token_command.dart';
import 'package:veraprob/application/telegram/generate_telegram_binding_token_handler.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/telegram/compliance_check_result.dart';
import 'package:veraprob/domain/sla_audit/telegram/i_telegram_repository.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_binding_token.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_evidence_link.dart';
import 'package:veraprob/domain/sla_audit/telegram/telegram_evidence_upload.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/telegram/postgres_telegram_repository.dart';
import 'auth_providers.dart';
import 'contract_providers.dart';
import 'shared_providers.dart';

// ── Repository ────────────────────────────────────────────────────────────────

final telegramRepositoryProvider = Provider<ITelegramRepository>((ref) {
  return PostgresTelegramRepository(ref.watch(supabaseClientProvider));
});

// ── Handler ───────────────────────────────────────────────────────────────────

final generateTelegramBindingTokenHandlerProvider =
    Provider<GenerateTelegramBindingTokenHandler>((ref) {
      return GenerateTelegramBindingTokenHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        telegramRepo: ref.watch(telegramRepositoryProvider),
        rbac: RbacService(),
        dateTimeProvider: ref.watch(dateTimeProviderProvider),
      );
    });

// ── Notifier ──────────────────────────────────────────────────────────────────

class TelegramBindingNotifier
    extends StateNotifier<AsyncValue<TelegramBindingToken?>> {
  final GenerateTelegramBindingTokenHandler _handler;

  TelegramBindingNotifier(this._handler) : super(const AsyncData(null));

  Future<void> generateToken(
    GenerateTelegramBindingTokenCommand command,
  ) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _handler.handle(command));
  }
}

final telegramBindingNotifierProvider = StateNotifierProvider.autoDispose
    .family<TelegramBindingNotifier, AsyncValue<TelegramBindingToken?>, String>(
      (ref, driverId) => TelegramBindingNotifier(
        ref.watch(generateTelegramBindingTokenHandlerProvider),
      ),
    );

// ── Active binding query ──────────────────────────────────────────────────────

final driverHasActiveTelegramBindingProvider = FutureProvider.autoDispose
    .family<bool, ({String driverId, String organizationId})>((
      ref,
      args,
    ) async {
      return ref
          .watch(telegramRepositoryProvider)
          .hasActiveBinding(
            driverId: args.driverId,
            organizationId: args.organizationId,
          );
    });

// ── WS-4: Reconciliation Providers ───────────────────────────────────────────

/// Orphan evidence uploads awaiting manual reconciliation (INV-1: org-scoped).
final orphanEvidencesProvider =
    FutureProvider.autoDispose<List<TelegramEvidenceUpload>>((ref) async {
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) return [];
      return ref
          .watch(telegramRepositoryProvider)
          .findOrphanEvidences(organizationId: orgId);
    });

/// Notifier for linking orphan evidence to an execution set (INV-7: append-only).
class LinkEvidenceNotifier
    extends StateNotifier<AsyncValue<TelegramEvidenceLink?>> {
  final ITelegramRepository _repo;
  final Ref _ref;

  LinkEvidenceNotifier(this._repo, this._ref) : super(const AsyncData(null));

  Future<void> link({
    required String evidenceUploadId,
    required String executionSetId,
  }) async {
    final orgId = _ref.read(currentOrganizationIdProvider);
    final userId = _ref.read(currentOperatorIdProvider);
    if (orgId == null || userId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.linkEvidenceToExecution(
        evidenceUploadId: evidenceUploadId,
        executionSetId: executionSetId,
        organizationId: orgId,
        userId: userId,
      ),
    );

    // Invalidate orphan list after successful link
    if (state.hasValue && state.value != null) {
      _ref.invalidate(orphanEvidencesProvider);
    }
  }
}

final linkEvidenceNotifierProvider =
    StateNotifierProvider.autoDispose<
      LinkEvidenceNotifier,
      AsyncValue<TelegramEvidenceLink?>
    >((ref) {
      return LinkEvidenceNotifier(ref.watch(telegramRepositoryProvider), ref);
    });

// ── Compliance Status Providers ───────────────────────────────────────────────

/// Compliance status for a driver's active trip.
/// keepAlive: true — result survives widget rebuilds (INV-16: avoid redundant RPCs).
final complianceStatusProvider = FutureProvider.family
    .autoDispose<
      ComplianceCheckResult,
      ({String organizationId, String driverId})
    >((ref, args) async {
      ref.keepAlive();
      return ref
          .watch(telegramRepositoryProvider)
          .getComplianceStatus(
            organizationId: args.organizationId,
            driverId: args.driverId,
          );
    });

/// Batch compliance for a list of SET IDs — one RPC call for the whole dashboard.
/// Keyed by organizationId to allow per-org caching (INV-16, INV-22).
final batchComplianceProvider = FutureProvider.family
    .autoDispose<
      Map<String, ComplianceCheckResult>,
      ({String organizationId, List<String> setIds})
    >((ref, args) async {
      ref.keepAlive();
      return ref
          .watch(telegramRepositoryProvider)
          .getBatchComplianceStatus(
            organizationId: args.organizationId,
            setIds: args.setIds,
          );
    });

/// Per-SET compliance — reads from the batch cache when available.
/// Falls back to individual RPC if batch hasn't been loaded.
final executionComplianceProvider = FutureProvider.family
    .autoDispose<
      ComplianceCheckResult?,
      ({String organizationId, String setId})
    >((ref, args) async {
      ref.keepAlive();
      // Try to read from batch cache first (avoids extra RPC)
      final batchKey = (
        organizationId: args.organizationId,
        setIds: [args.setId],
      );
      final batchState = ref.read(batchComplianceProvider(batchKey));
      if (batchState.hasValue) {
        return batchState.value?[args.setId];
      }
      // Fallback: individual call
      final result = await ref
          .watch(telegramRepositoryProvider)
          .getBatchComplianceStatus(
            organizationId: args.organizationId,
            setIds: [args.setId],
          );
      return result[args.setId];
    });

/// Forensic negligence data for a driver+SET combination.
/// Used in SanctionVerdictCard to show "driver was warned X times".
final negligenceProvider = FutureProvider.family
    .autoDispose<
      ({
        int queryCount,
        DateTime? lastQueriedAt,
        bool hadPendingItems,
        int forcedCompletions,
      }),
      ({String organizationId, String driverId, String setId})
    >((ref, args) async {
      ref.keepAlive();
      return ref
          .watch(telegramRepositoryProvider)
          .getDriverStatusQueryCount(
            organizationId: args.organizationId,
            driverId: args.driverId,
            setId: args.setId,
          );
    });
