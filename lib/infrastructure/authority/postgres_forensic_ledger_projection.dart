import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/projections/forensic_ledger_view.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';

/// Postgres implementation for the Forensic Ledger Projection.
/// Parses immutable events from the [sla_audit_ledger] directly via Supabase.
class PostgresForensicLedgerProjection {
  final SupabaseClient _client;

  PostgresForensicLedgerProjection(this._client);

  /// Streams the latest forensic ledger entries directly from the audit ledger.
  /// Uses server-side sorting and limiting to avoid reading the full ledger to memory.
  Stream<List<ForensicLedgerEntry>> watchLedger({int limit = 50}) {
    return _client
        .from('sla_audit_ledger')
        .stream(primaryKey: ['id'])
        .order('timestamp', ascending: false)
        .limit(limit)
        .map((rows) {
          return rows.map((row) {
            // Reconstructing minimal domain-like object to use the existing `toNarrative` formatter
            final decision = AuthorizationDecision(
              decisionId: row['id'] as String,
              actorId: ActorId(row['operator_id'] as String),
              roleId: const RoleId(
                'unknown_role',
              ), // Metadata not strictly required for ledger view
              actionType: OperationalActionType(row['action_type'] as String),
              targetRef: TargetRef('system', row['entity_id'] as String),
              policyVersion: '1.0',
              result: DecisionResult
                  .approved, // Audit ledger currently infers approved actions
              reason: row['reason'] as String?,
              occurredAt: DateTime.parse(row['timestamp'] as String).toUtc(),
              contextSnapshot: const {},
            );

            return ForensicLedgerEntry(
              decisionId: decision.decisionId,
              actionType: decision.actionType.key,
              actionLabel: decision.actionType.key.replaceAll(
                '_',
                ' ',
              ), // Simplified label strategy for audited items
              actorId: decision.actorId.value,
              result: decision.result.name.toUpperCase(),
              reason: decision.reason,
              narrative: toNarrative(decision),
              timestamp: decision.occurredAt,
            );
          }).toList();
        });
  }
}
