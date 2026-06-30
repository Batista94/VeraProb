import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/infrastructure/sla_audit/justification/file_service/justification_file_service.dart';
import 'package:veraprob/application/sla_audit/justification/approve_justification_handler.dart';
import 'package:veraprob/application/sla_audit/justification/justification_summary.dart';
import 'package:veraprob/state/notifiers/async_command_mixin.dart';
import 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
import 'package:veraprob/application/sla_audit/justification/generate_justification_token_handler.dart';
import 'package:veraprob/application/sla_audit/justification/review_justification_command.dart';
import 'package:veraprob/application/sla_audit/justification/reject_justification_handler.dart';
import 'package:veraprob/application/sla_audit/justification/submit_justification_handler.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/justification/forensic_throttle_gateway.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/justification_evidence_storage_service.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/supabase_evidence_storage_reader.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/supabase_forensic_throttle_gateway.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'contract_providers.dart';
import 'local_fact_queue_providers.dart';
import 'shared_providers.dart';

// Re-export so features/ can resolve the type without importing infrastructure/.
export 'package:veraprob/infrastructure/sla_audit/justification/justification_evidence_storage_service.dart'
    show JustificationEvidenceStorageService;

// ── Handler providers (not cached) ───────────────────────────────────────────

/// Evidence storage reader bound to the signed-in Supabase session; shared
/// by the analyzer (forensic scan) and integrity verifier (hash recompute).
final evidenceStorageReaderProvider = Provider<SupabaseEvidenceStorageReader>((
  ref,
) {
  return SupabaseEvidenceStorageReader(ref.watch(supabaseClientProvider));
});

/// Two-pass contextual forensic analyzer — runs in the handler, never the UI.
final contextualSignatureAnalyzerProvider =
    Provider<ContextualSignatureAnalyzer>((ref) {
      return ContextualSignatureAnalyzer(
        ref.watch(evidenceStorageReaderProvider),
      );
    });

/// Server-authoritative forensic throttle gateway (INV-16, INV-18). The RPC
/// enforces JWT-claim tenancy and persisted backoff state under RLS.
final forensicThrottleGatewayProvider = Provider<ForensicThrottleGateway>((
  ref,
) {
  return SupabaseForensicThrottleGateway(ref.watch(supabaseClientProvider));
});

/// Provides a fresh [SubmitJustificationHandler] per read.
final submitJustificationHandlerProvider =
    Provider.autoDispose<SubmitJustificationHandler>((ref) {
      return SubmitJustificationHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        justificationRepo: ref.watch(justificationRepositoryProvider),
        ledger: ref.watch(slaAuditLedgerRepositoryProvider),
        factQueue: ref.watch(localFactQueueRepositoryProvider),
        rbac: RbacService(),
        clock: ref.watch(dateTimeProviderProvider),
        analyzer: ref.watch(contextualSignatureAnalyzerProvider),
        throttle: ref.watch(forensicThrottleGatewayProvider),
      );
    });

/// Provides a fresh [GenerateJustificationTokenHandler] per read.
final generateJustificationTokenHandlerProvider =
    Provider.autoDispose<GenerateJustificationTokenHandler>((ref) {
      return GenerateJustificationTokenHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        justificationRepo: ref.watch(justificationRepositoryProvider),
        rbac: RbacService(),
      );
    });

final justificationStorageServiceProvider =
    Provider<JustificationEvidenceStorageService>((ref) {
      return JustificationEvidenceStorageService(
        ref.watch(supabaseClientProvider),
      );
    });

final justificationFileServiceProvider = Provider<JustificationFileService>(
  (ref) => createJustificationFileService(),
);

// ── Realtime stream of all justifications ────────────────────────────────────

/// Stream of all justification rows for the current session's organisation,
/// ordered by submission time descending. Backed by Supabase Realtime.
///
/// RLS enforces tenant isolation — no explicit org_id filter needed.
/// INV-30: Client injected via supabaseClientProvider.
final justificationListStreamProvider =
    StreamProvider.autoDispose<List<JustificationSummary>>((ref) {
      return ref
          .watch(supabaseClientProvider)
          .from('contractor_justifications')
          .stream(primaryKey: ['id'])
          .order('created_at_utc', ascending: false)
          .map(
            (rows) => rows.map(JustificationSummary.fromRealtimeRow).toList(),
          );
    });

// ── Derived badge count ───────────────────────────────────────────────────────

/// Count of PENDING justifications — drives the nav-rail badge on
/// "Portal Defesa".
final pendingJustificationsCountProvider = Provider.autoDispose<int>((ref) {
  final justificationsAsync = ref.watch(justificationListStreamProvider);
  return switch (justificationsAsync) {
    AsyncData(:final value) => value.where((j) => j.isPending).length,
    AsyncError() => 0,
    AsyncLoading() => 0,
  };
});

// ── Per-justification action state ───────────────────────────────────────────

/// Provides a fresh [ApproveJustificationHandler] per read.
final approveJustificationHandlerProvider =
    Provider.autoDispose<ApproveJustificationHandler>((ref) {
      return ApproveJustificationHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        justificationRepo: ref.watch(justificationRepositoryProvider),
        ledger: ref.watch(slaAuditLedgerRepositoryProvider),
        rbac: RbacService(),
      );
    });

/// Provides a fresh [RejectJustificationHandler] per read.
final rejectJustificationHandlerProvider =
    Provider.autoDispose<RejectJustificationHandler>((ref) {
      return RejectJustificationHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        justificationRepo: ref.watch(justificationRepositoryProvider),
        ledger: ref.watch(slaAuditLedgerRepositoryProvider),
        rbac: RbacService(),
      );
    });

/// Loading/error state for approve/reject actions on a specific justification.
/// Key: justificationId.
final justificationActionStateProvider = NotifierProvider.autoDispose
    .family<JustificationActionNotifier, AsyncValue<void>, String>(
      JustificationActionNotifier.new,
    );

class JustificationActionNotifier extends Notifier<AsyncValue<void>>
    with GuardedAsyncActionMixin<void> {
  JustificationActionNotifier(this.justificationId);
  final String justificationId;

  @override
  AsyncValue<void> build() {
    return const AsyncData(null);
  }

  Future<void> approve({
    required String justificationId,
    required String organizationId,
    required int planVersion,
    required UserRole callerRole,
    required String callerUserId,
    required String callerEmail,
    required String sessionId,
  }) async {
    await guardedAction(
      () => ref
          .read(approveJustificationHandlerProvider)
          .handle(
            ApproveJustificationCommand(
              justificationId: justificationId,
              organizationId: organizationId,
              planVersion: planVersion,
              callerRole: callerRole,
              callerUserId: callerUserId,
              callerEmail: callerEmail,
              sessionId: sessionId,
            ),
          ),
    );
  }

  Future<void> reject({
    required String justificationId,
    required String organizationId,
    required int planVersion,
    required UserRole callerRole,
    required String callerUserId,
    required String callerEmail,
    required String rejectionNotes,
    required String sessionId,
  }) async {
    await guardedAction(
      () => ref
          .read(rejectJustificationHandlerProvider)
          .handle(
            RejectJustificationCommand(
              justificationId: justificationId,
              organizationId: organizationId,
              planVersion: planVersion,
              callerRole: callerRole,
              callerUserId: callerUserId,
              callerEmail: callerEmail,
              rejectionNotes: rejectionNotes,
              sessionId: sessionId,
            ),
          ),
    );
  }
}
