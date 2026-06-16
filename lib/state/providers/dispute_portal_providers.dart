import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/dispute_portal/i_file_hasher.dart';
import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
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

typedef PortalPageData = ({
  PortalSnapshot snapshot,
  InfractionContextProjection contextData,
});

/// Fetches both the snapshot and the immutable context data required by the portal page.
final portalPageDataProvider = FutureProvider.autoDispose
    .family<PortalPageData, String>((ref, token) async {
      final gateway = ref.watch(portalDisputeGatewayProvider);

      // Concurrently fetch both (Fail-Fast: if either fails, the Future fails).
      final results = await Future.wait([
        gateway.read(token),
        gateway.readInfractionContext(token),
      ]);

      return (
        snapshot: results[0] as PortalSnapshot,
        contextData: results[1] as InfractionContextProjection,
      );
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
