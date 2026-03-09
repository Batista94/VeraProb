import 'dart:collection';

import '../../domain/sla_audit/plan_declaration.dart';
import '../../domain/sla_audit/plan_declaration_repository.dart';

/// In-memory implementation of [PlanDeclarationRepository].
///
/// Uses a simple [Map] for storage. Suitable for development and testing.
class InMemoryPlanDeclarationRepository implements PlanDeclarationRepository {
  final Map<String, PlanDeclaration> _store = {};

  @override
  Future<void> save(PlanDeclaration plan) async {
    _store[plan.id] = plan;
  }

  @override
  Future<PlanDeclaration?> findById(String id) async {
    return _store[id];
  }

  @override
  Future<List<PlanDeclaration>> findByContract(
    String contractId, {
    required String organizationId,
  }) async {
    final results = _store.values
        .where(
          (p) => p.organizationId == organizationId && p.contractId == contractId,
        )
        .toList();
    return UnmodifiableListView(results);
  }
}
