import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/dispute_portal/i_file_hasher.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
import 'package:veraprob/application/dispute_portal/portal_retry_policy.dart';
import 'package:veraprob/application/dispute_portal/portal_submission_audit_gateway.dart';
import 'package:veraprob/application/dispute_portal/infraction_context_projection.dart';
import 'package:veraprob/application/dispute_portal/portal_snapshot.dart';
import 'package:veraprob/infrastructure/dispute_portal/chunked_file_hasher.dart';
import 'package:veraprob/infrastructure/dispute_portal/web_worker_file_hasher_stub.dart'
    if (dart.library.js_interop) 'package:veraprob/infrastructure/dispute_portal/web_worker_file_hasher.dart';
import 'package:veraprob/infrastructure/dispute_portal/supabase_portal_dispute_gateway.dart';
import 'package:veraprob/infrastructure/dispute_portal/supabase_portal_submission_audit_gateway.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';

final fileHasherProvider = Provider<IFileHasher>((ref) {
  if (kIsWeb) {
    return const WebWorkerFileHasher();
  }
  return const ChunkedFileHasher();
});

/// Anon-side gateway for the external dispute portal. Overridable in tests via
/// `portalDisputeGatewayProvider.overrideWithValue(fake)`.
final portalDisputeGatewayProvider = Provider<PortalDisputeGateway>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SupabasePortalDisputeGateway(client);
});

/// Backoff policy applied by the submission notifier to retryable (infra 503)
/// failures. Overridable in tests with `PortalRetryPolicy.zeroDelay`.
final portalRetryPolicyProvider = Provider<PortalRetryPolicy>(
  (ref) => const PortalRetryPolicy(),
);

typedef PortalPageData = ({
  PortalSnapshot snapshot,
  InfractionContextProjection? contextData,
});

/// Fetches both the snapshot and the immutable context data required by the portal page.
///
/// When the verdict was sealed internally the token is revoked, so
/// `read_infraction_context` denies while `read_dispute_portal` returns a closed
/// snapshot. In that case we surface the sealed snapshot (with null context) so
/// the page can render "SLA encerrado", instead of collapsing to a generic error.
/// The sealed branch of `read_dispute_portal` returns BEFORE incrementing
/// `access_count`, so the re-fetch below burns no access.
final portalPageDataProvider = FutureProvider.autoDispose
    .family<PortalPageData, String>((ref, token) async {
      final gateway = ref.watch(portalDisputeGatewayProvider);

      try {
        // Concurrently fetch both (Fail-Fast: if either fails, the Future fails).
        final results = await Future.wait([
          gateway.read(token),
          gateway.readInfractionContext(token),
        ]);
        return (
          snapshot: results[0] as PortalSnapshot,
          contextData: results[1] as InfractionContextProjection,
        );
      } on PortalDisputeException {
        // A revoked-but-sealed token denies the context read. Re-read the
        // snapshot (free on the sealed branch) and surface the closure.
        final snapshot = await gateway.read(token);
        if (snapshot.closedInternally) {
          return (snapshot: snapshot, contextData: null);
        }
        rethrow;
      }
    });

/// Authenticated auditor gateway for reviewing PENDING_AUDIT portal submissions
/// (`list_portal_submissions` + `audit_portal_submission`). JWT-bound; the org +
/// role gate lives in the SECURITY DEFINER RPCs (INV-22/26).
final portalSubmissionAuditGatewayProvider =
    Provider<PortalSubmissionAuditGateway>((ref) {
      final client = ref.watch(supabaseClientProvider);
      return SupabasePortalSubmissionAuditGateway(client);
    });

/// PENDING_AUDIT submissions for a given queue entry. Family keyed by
/// `({orgId, queueEntryId})`. autoDispose so the panel re-queries fresh
/// each time a disputed card is expanded.
///
/// INV-1: `orgId` is a family parameter — the calling widget MUST source it
/// from `currentOrganizationIdProvider`. It is never hardcoded here, and the
/// SECURITY DEFINER RPC re-validates the JWT org server-side (INV-22/26),
/// returning 0 rows on any mismatch.
final pendingPortalSubmissionsProvider = FutureProvider.autoDispose
    .family<
      List<PortalSubmissionSummary>,
      ({String orgId, String queueEntryId})
    >((ref, key) {
      final gateway = ref.watch(portalSubmissionAuditGatewayProvider);
      return gateway.listPending(
        organizationId: key.orgId,
        queueEntryId: key.queueEntryId,
      );
    });

/// Single shared realtime tick for finalized portal counter-evidence.
///
/// INV-16: ONE channel for the whole auditor session — every disputed card
/// listens to THIS provider, never its own per-card subscription. Backed by
/// `dispute_evidence_attachments`, which gains a row 1:1 when
/// `register_portal_evidence` promotes a portal submission to PENDING_AUDIT
/// (migration 20260826000001 publishes it on `supabase_realtime`).
/// `portal_evidence_submissions` itself is deny-all RLS and cannot be streamed.
///
/// RLS (`dea_select_own_org`) scopes the stream to the caller's org, so Tenant-A
/// never observes Tenant-B inserts (INV-22). Emits `queueEntryId → active
/// attachment count`; a listener detects a NEW attachment for its own dispute
/// via the count delta and invalidates the matching
/// [pendingPortalSubmissionsProvider] family entry.
final portalEvidenceRealtimeProvider =
    StreamProvider.autoDispose<Map<String, int>>((ref) {
      return ref
          .watch(supabaseClientProvider)
          .from('dispute_evidence_attachments')
          .stream(primaryKey: ['id'])
          .map((rows) {
            final counts = <String, int>{};
            for (final row in rows) {
              if (row['deleted_at'] != null) continue;
              final queueEntryId = row['queue_entry_id'] as String?;
              if (queueEntryId == null) continue;
              counts[queueEntryId] = (counts[queueEntryId] ?? 0) + 1;
            }
            return counts;
          })
          .distinct(mapEquals);
    });
