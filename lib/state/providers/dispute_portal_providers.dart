import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
import 'package:veraprob/application/dispute_portal/portal_submission_audit_gateway.dart';
import 'package:veraprob/infrastructure/dispute_portal/supabase_portal_dispute_gateway.dart';
import 'package:veraprob/infrastructure/dispute_portal/supabase_portal_submission_audit_gateway.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';

/// Anon-side gateway for the external dispute portal. Overridable in tests via
/// `portalDisputeGatewayProvider.overrideWithValue(fake)`.
final portalDisputeGatewayProvider = Provider<PortalDisputeGateway>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SupabasePortalDisputeGateway(client);
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
/// `'$organizationId|$queueEntryId'`. autoDispose so the panel re-queries fresh
/// each time a disputed card is expanded.
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
