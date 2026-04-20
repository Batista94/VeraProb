import 'dart:collection';

import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration_repository.dart';

/// In-memory implementation of [PlanDeclarationRepository].
///
/// Uses a simple [Map] for storage. Suitable for development and testing.
class InMemoryPlanDeclarationRepository implements PlanDeclarationRepository {
  final Map<String, PlanDeclaration> _store = {};

  /// Projected SETs indexed by planDeclarationId.
  /// Keyed by setId within each plan for idempotency.
  final Map<String, Map<String, ContractualServiceExecution>> _projectedSets =
      {};

  @override
  Future<PlanDeclaration> save(PlanDeclaration plan) async {
    _store[plan.id] = plan;
    return plan;
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
          (p) =>
              p.organizationId == organizationId && p.contractId == contractId,
        )
        .toList();
    return UnmodifiableListView(results);
  }

  @override
  Future<List<PlanDeclaration>> findByOrganization(
    String organizationId,
  ) async {
    final results = _store.values
        .where((p) => p.organizationId == organizationId)
        .toList();
    return UnmodifiableListView(results);
  }

  @override
  Future<void> saveProjectedSets(
    String planDeclarationId,
    List<ContractualServiceExecution> sets, {
    required String organizationId,
  }) async {
    final bucket = _projectedSets.putIfAbsent(planDeclarationId, () => {});
    for (final set in sets) {
      bucket.putIfAbsent(set.setId, () => set); // idempotent: ignore duplicates
    }
  }

  /// Test helper: returns all projected SETs for a given plan.
  List<ContractualServiceExecution> projectedSetsFor(String planDeclarationId) {
    return List.unmodifiable(
      _projectedSets[planDeclarationId]?.values.toList() ?? [],
    );
  }
}
