import 'package:flutter/foundation.dart';

/// A single governance/audit-trail entry: role assignment/revocation and
/// member-lifecycle events (invite, deactivate, reactivate, remove, legacy
/// role change). Sourced from `system_audit_log` via the org-scoped
/// `get_tenant_governance_log` RPC — explicit typed columns only, never raw
/// JSONB (INV-1, INV-2, INV-22).
@immutable
class GovernanceAuditEntry {
  final DateTime occurredAtUtc;
  final String eventType;
  final String? actorId;
  final String? actorEmail;
  final String? targetUserId;
  final String? targetEmail;
  final String? reason;

  const GovernanceAuditEntry({
    required this.occurredAtUtc,
    required this.eventType,
    this.actorId,
    this.actorEmail,
    this.targetUserId,
    this.targetEmail,
    this.reason,
  });
}

/// Category filter mirroring the allowlist grouping enforced server-side in
/// `get_tenant_governance_log` (Pilar UX: period/category/email filter bar).
enum GovernanceEventCategory {
  roles,
  members,
  invites;

  /// Value expected by the `p_event_category` RPC parameter.
  String get dbValue => name;
}

/// Query service for the tenant governance audit trail (Histórico tab).
///
/// Decoupled from infrastructure implementations (INV-13).
abstract class GovernanceAuditQueryService {
  Future<List<GovernanceAuditEntry>> getEntries({
    int limit = 50,
    DateTime? before,
    GovernanceEventCategory? category,
    String? searchEmail,
  });
}
