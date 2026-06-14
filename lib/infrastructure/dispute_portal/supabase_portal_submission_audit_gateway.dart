import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/dispute_portal/portal_submission_audit_gateway.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Supabase-backed [PortalSubmissionAuditGateway] for the authenticated auditor.
///
/// Both RPCs are SECURITY DEFINER and gate the JWT org + TENANT_ADMIN/AUDITOR
/// role server-side; failures surface as identical anti-oracle errors (INV-26).
class SupabasePortalSubmissionAuditGateway extends BasePostgresRepository
    implements PortalSubmissionAuditGateway {
  SupabasePortalSubmissionAuditGateway(super.client);

  @override
  Future<List<PortalSubmissionSummary>> listPending({
    required String organizationId,
    required String queueEntryId,
  }) async {
    try {
      final rows = await client.rpc<List<dynamic>>(
        'list_portal_submissions',
        params: {
          'p_organization_id': organizationId,
          'p_queue_entry_id': queueEntryId,
        },
      );
      return rows
          .map(
            (r) => PortalSubmissionSummary.fromJson(
              Map<String, dynamic>.from(r as Map),
            ),
          )
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e);
    }
  }

  @override
  Future<void> audit({
    required String organizationId,
    required String submissionId,
    required PortalAuditDecision decision,
    required String auditedByUserId,
  }) async {
    try {
      await client.rpc<dynamic>(
        'audit_portal_submission',
        params: {
          'p_organization_id': organizationId,
          'p_submission_id': submissionId,
          'p_decision': decision.rpcValue,
          'p_audited_by': auditedByUserId,
        },
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e);
    }
  }
}
