import 'package:veraprob/domain/sla_audit/evaluation_trace.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace_repository.dart';

class InMemoryEvaluationTraceRepository implements EvaluationTraceRepository {
  final Map<String, EvaluationTrace> _db = {};

  @override
  Future<void> save(EvaluationTrace trace) async {
    _db[trace.id] = trace;
  }

  @override
  Future<EvaluationTrace?> findById(
    String id, {
    required String organizationId,
  }) async {
    final trace = _db[id];
    if (trace == null || trace.organizationId != organizationId) return null;
    return trace;
  }

  @override
  Future<List<EvaluationTrace>> findByEntityId(
    String entityId, {
    required String organizationId,
  }) async {
    return _db.values
        .where(
          (trace) =>
              trace.entityId == entityId &&
              trace.organizationId == organizationId,
        )
        .toList();
  }
}
