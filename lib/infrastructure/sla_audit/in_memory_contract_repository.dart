import 'dart:collection';

import '../../domain/sla_audit/contract.dart';
import '../../domain/sla_audit/contract_repository.dart';
import '../../domain/sla_audit/contract_status.dart';

/// In-memory implementation of [ContractRepository].
///
/// Uses a simple [Map] keyed by contract ID for storage.
/// Suitable for development, simulation mode, and unit tests.
class InMemoryContractRepository implements ContractRepository {
  final Map<String, Contract> _store = {};

  @override
  Future<void> save(Contract contract) async {
    _store[contract.id] = contract;
  }

  @override
  Future<Contract?> findById(String id, {required String organizationId}) async {
    final contract = _store[id];
    if (contract == null) return null;
    // Enforce tenant isolation even in-memory
    if (contract.organizationId != organizationId) return null;
    return contract;
  }

  @override
  Future<List<Contract>> findByOrganization(
    String organizationId, {
    ContractStatus? status,
  }) async {
    final results = _store.values.where((c) {
      if (c.organizationId != organizationId) return false;
      if (status != null && c.status != status) return false;
      return true;
    }).toList();

    // Ordered by createdAtUtc descending
    results.sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
    return UnmodifiableListView(results);
  }
}
