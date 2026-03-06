import '../../domain/sla_audit/evaluation_trace.dart';
import '../../domain/sla_audit/evaluation_trace_repository.dart';

class InMemoryEvaluationTraceRepository implements EvaluationTraceRepository {
  final Map<String, EvaluationTrace> _db = {};

  @override
  Future<void> save(EvaluationTrace trace) async {
    _db[trace.id] = trace;
  }

  @override
  Future<EvaluationTrace?> findById(String id) async {
    return _db[id];
  }

  @override
  Future<List<EvaluationTrace>> findByEntityId(String entityId) async {
    return _db.values.where((trace) => trace.entityId == entityId).toList();
  }
}
