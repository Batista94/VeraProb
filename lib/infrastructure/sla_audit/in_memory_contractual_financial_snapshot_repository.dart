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
    required String organizationId,
    String? contractId,
  }) async {
    final snapshots = _store.values
        .where((s) => s.organizationId == organizationId)
        .toList();

    // Identify superseded snapshots (those referenced by another snapshot's previousSnapshotId)
    final supersededIds = snapshots
        .where((s) => s.previousSnapshotId != null)
        .map((s) => s.previousSnapshotId!)
        .toSet();

    // Filter to only active snapshots (not superseded)
    final activeSnapshots = snapshots.where(
      (s) => !supersededIds.contains(s.id),
    );

    if (contractId == null) return activeSnapshots.toList();
    return activeSnapshots.where((s) => s.contractId == contractId).toList();
  }

  @override
  Future<List<ContractualFinancialDailySnapshot>> findByDateRange({
    required String organizationId,
    required DateTime startUtc,
    required DateTime endUtc,
    String? contractId,
  }) async {
    final active = await findAll(
      organizationId: organizationId,
      contractId: contractId,
    );
    return active.where((s) {
      final date = s.operationalDateUtc;
      return (date.isAtSameMomentAs(startUtc) || date.isAfter(startUtc)) &&
          (date.isAtSameMomentAs(endUtc) || date.isBefore(endUtc));
    }).toList();
  }

  @override
  Future<bool> existsForDate(
    String organizationId,
    DateTime operationalDateUtc, {
    String? contractId,
  }) async {
    final normalizedDate = DateTime.utc(
      operationalDateUtc.year,
      operationalDateUtc.month,
      operationalDateUtc.day,
    );
    final active = await findAll(
      organizationId: organizationId,
      contractId: contractId,
    );
    return active.any((s) => s.operationalDateUtc == normalizedDate);
  }
}
