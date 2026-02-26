import '../../domain/sla_audit/contractual_financial_daily_snapshot.dart';
import '../../domain/sla_audit/contractual_financial_snapshot_repository.dart';

/// In-memory implementation of [ContractualFinancialSnapshotRepository].
///
/// Uses a Map keyed by snapshot ID. Guarantees idempotency by
/// checking operational date before save.
class InMemoryContractualFinancialSnapshotRepository
    implements ContractualFinancialSnapshotRepository {
  final Map<String, ContractualFinancialDailySnapshot> _store = {};

  @override
  Future<void> save(ContractualFinancialDailySnapshot snapshot) async {
    _store[snapshot.id] = snapshot;
  }

  @override
  Future<List<ContractualFinancialDailySnapshot>> findAll({
    String? contractId,
  }) async {
    final snapshots = _store.values.toList();
    if (contractId == null) return snapshots;
    return snapshots.where((s) => s.contractId == contractId).toList();
  }

  @override
  Future<bool> existsForDate(
    DateTime operationalDateUtc, {
    String? contractId,
  }) async {
    final normalizedDate = DateTime.utc(
      operationalDateUtc.year,
      operationalDateUtc.month,
      operationalDateUtc.day,
    );
    return _store.values.any(
      (s) =>
          s.operationalDateUtc == normalizedDate && s.contractId == contractId,
    );
  }
}
