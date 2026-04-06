import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace_repository.dart';

class PostgresEvaluationTraceRepository implements EvaluationTraceRepository {
  final SupabaseClient _client;

  PostgresEvaluationTraceRepository(this._client);

  @override
  Future<void> save(EvaluationTrace trace) async {
    final Map<String, dynamic> row = {
      'id': trace.id,
      'organization_id': trace.organizationId,
      'entity_id': trace.entityId,
      'triggering_event_id': trace.triggeringEventId,
      'evaluated_at_utc': trace.evaluatedAtUtc.toIso8601String(),
      'engine_version': trace.engineVersion,
      'decisions': trace.decisions.map((d) => d.toJson()).toList(),
    };

    await _client.from('contractual_evaluation_traces').insert(row);
  }

  @override
  Future<EvaluationTrace?> findById(String id) async {
    final response = await _client
        .from('contractual_evaluation_traces')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return _mapToEvaluationTrace(response);
  }

  @override
  Future<List<EvaluationTrace>> findByEntityId(String entityId) async {
    final response = await _client
        .from('contractual_evaluation_traces')
        .select()
        .eq('entity_id', entityId)
        .order('evaluated_at_utc', ascending: false);

    return (response as List<dynamic>)
        .map((row) => _mapToEvaluationTrace(row as Map<String, dynamic>))
        .toList();
  }

  EvaluationTrace _mapToEvaluationTrace(Map<String, dynamic> row) {
    return EvaluationTrace(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      entityId: row['entity_id'] as String,
      triggeringEventId: row['triggering_event_id'] as String,
      evaluatedAtUtc: DateTime.parse(row['evaluated_at_utc'] as String),
      engineVersion: row['engine_version'] as String,
      decisions: (row['decisions'] as List<dynamic>)
          .map((d) => EvaluationDecision.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }
}
