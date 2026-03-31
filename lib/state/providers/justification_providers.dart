import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/sla_audit/justification/approve_justification_handler.dart';
import '../../application/sla_audit/justification/generate_justification_token_handler.dart';
import '../../application/sla_audit/justification/review_justification_command.dart';
import '../../application/sla_audit/justification/reject_justification_handler.dart';
import '../../application/sla_audit/justification/submit_justification_handler.dart';
import '../../domain/enums/user_role.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/justification/justification_status.dart';
import '../../infrastructure/sla_audit/sla_persistence_provider.dart';
import 'local_fact_queue_providers.dart';

// ── Handler providers (not cached) ───────────────────────────────────────────

/// Provides a fresh [SubmitJustificationHandler] per read.
final submitJustificationHandlerProvider =
    Provider.autoDispose<SubmitJustificationHandler>((ref) {
      return SubmitJustificationHandler(
        justificationRepo: ref.watch(justificationRepositoryProvider),
        ledger: ref.watch(slaAuditLedgerRepositoryProvider),
        factQueue: ref.watch(localFactQueueRepositoryProvider),
        rbac: RbacService(),
      );
    });

/// Provides a fresh [GenerateJustificationTokenHandler] per read.
final generateJustificationTokenHandlerProvider =
    Provider.autoDispose<GenerateJustificationTokenHandler>((ref) {
      return GenerateJustificationTokenHandler(
        justificationRepo: ref.watch(justificationRepositoryProvider),
        rbac: RbacService(),
      );
    });

// ── Realtime stream of all justifications ────────────────────────────────────

/// Stream of all justification rows for the current session's organisation,
/// ordered by submission time descending. Backed by Supabase Realtime.
///
/// RLS enforces tenant isolation — no explicit org_id filter needed.
final justificationListStreamProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      return Supabase.instance.client
          .from('contractor_justifications')
          .stream(primaryKey: ['id'])
          .order('created_at_utc', ascending: false)
          .map((rows) => List<Map<String, dynamic>>.from(rows));
    });

// ── Derived badge count ───────────────────────────────────────────────────────

/// Count of PENDING justifications — drives the nav-rail badge on
/// "Portal Defesa".
final pendingJustificationsCountProvider = Provider.autoDispose<int>((ref) {
  return ref
      .watch(justificationListStreamProvider)
      .maybeWhen(
        data: (rows) => rows
            .where((r) => r['status'] == JustificationStatus.pending.dbValue)
            .length,
        orElse: () => 0,
      );
});

// ── Per-justification action state ───────────────────────────────────────────

/// Loading/error state for approve/reject actions on a specific justification.
/// Key: justificationId.
final justificationActionStateProvider = StateNotifierProvider.autoDispose
    .family<JustificationActionNotifier, AsyncValue<void>, String>(
      (ref, justificationId) => JustificationActionNotifier(
        approveHandler: ApproveJustificationHandler(
          justificationRepo: ref.watch(justificationRepositoryProvider),
          ledger: ref.watch(slaAuditLedgerRepositoryProvider),
          rbac: RbacService(),
        ),
        rejectHandler: RejectJustificationHandler(
          justificationRepo: ref.watch(justificationRepositoryProvider),
          ledger: ref.watch(slaAuditLedgerRepositoryProvider),
          rbac: RbacService(),
        ),
      ),
    );

class JustificationActionNotifier extends StateNotifier<AsyncValue<void>> {
  final ApproveJustificationHandler _approveHandler;
  final RejectJustificationHandler _rejectHandler;

  JustificationActionNotifier({
    required ApproveJustificationHandler approveHandler,
    required RejectJustificationHandler rejectHandler,
  }) : _approveHandler = approveHandler,
       _rejectHandler = rejectHandler,
       super(const AsyncData(null));

  Future<void> approve({
    required String justificationId,
    required String organizationId,
    required int planVersion,
    required UserRole callerRole,
    required String callerUserId,
    required String callerEmail,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _approveHandler.handle(
        ApproveJustificationCommand(
          justificationId: justificationId,
          organizationId: organizationId,
          planVersion: planVersion,
          callerRole: callerRole,
          callerUserId: callerUserId,
          callerEmail: callerEmail,
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
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _rejectHandler.handle(
        RejectJustificationCommand(
          justificationId: justificationId,
          organizationId: organizationId,
          planVersion: planVersion,
          callerRole: callerRole,
          callerUserId: callerUserId,
          callerEmail: callerEmail,
          rejectionNotes: rejectionNotes,
        ),
      ),
    );
  }
}
