import 'contractual_financial_daily_snapshot.dart';

/// Repository interface for contractual financial daily snapshots.
///
/// Snapshots are immutable once created. The repository supports
/// idempotency checks via [existsForDate].
abstract class ContractualFinancialSnapshotRepository {
  /// Persists a new daily snapshot.
  Future<void> save(ContractualFinancialDailySnapshot snapshot);

  /// Returns all snapshots, optionally filtered by contract.
  Future<List<ContractualFinancialDailySnapshot>> findAll({String? contractId});

  /// Checks if a snapshot already exists for a given operational day.
  Future<bool> existsForDate(DateTime operationalDateUtc, {String? contractId});
}
