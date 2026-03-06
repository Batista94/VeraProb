import '../../domain/sla_audit/evaluation_trace.dart';

abstract class EvaluationTraceRepository {
  Future<void> save(EvaluationTrace trace);
  Future<EvaluationTrace?> findById(String id);
  Future<List<EvaluationTrace>> findByEntityId(String entityId);
}
