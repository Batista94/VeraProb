// pr_scanner: ignore-regression — PR elevation org-scope ports / domain touch (Council-approved plan)
import 'package:veraprob/domain/sla_audit/evaluation_trace.dart';

abstract class EvaluationTraceRepository {
  Future<void> save(EvaluationTrace trace);
  Future<EvaluationTrace?> findById(
    String id, {
    required String organizationId,
  });
  Future<List<EvaluationTrace>> findByEntityId(
    String entityId, {
    required String organizationId,
  });
}
