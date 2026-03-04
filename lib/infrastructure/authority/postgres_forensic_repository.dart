import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/authority/decision/authorization_decision.dart';
import '../../domain/authority/repositories/forensic_decision_repository.dart';

/// Postgres implementation of the [ForensicDecisionRepository].
/// Operates strictly as an immutable append-only storage for Forensic Decisions.
class PostgresForensicRepository implements ForensicDecisionRepository {
  final SupabaseClient _client;

  PostgresForensicRepository(this._client);

  @override
  Future<void> saveDecision(AuthorizationDecision decision) async {
    // Map the Domain Entity to a Postgres-compatible JSON map without altering the Domain.
    final payload = {
      'id': decision.decisionId,
      'actor_id': decision.actorId.value,
      'role_id': decision.roleId.value,
      'action_type': decision.actionType.key,
      'target_urn': decision.targetRef.urn,
      'policy_version': decision.policyVersion,
      'result': decision.isApproved ? 'APPROVED' : 'DENIED',
      'reason': decision.reason,
      'occurred_at': decision.occurredAt.toUtc().toIso8601String(),
      'context_snapshot': decision.contextSnapshot,
    };

    // Append-only constraint guaranteed by Supabase RLS in production.
    await _client.from('forensic_decisions').insert(payload);
  }
}
