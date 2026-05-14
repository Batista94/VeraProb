import 'contractual_financial_daily_snapshot.dart';

/// Repository interface for contractual financial daily snapshots.
///
/// Snapshots are immutable once created. The repository supports
/// idempotency checks via [existsForDate].
abstract class ContractualFinancialSnapshotRepository {
  /// Persists a new daily snapshot.
  Future<void> save(ContractualFinancialDailySnapshot snapshot);

  /// Returns all active snapshots, optionally filtered by contract.
  Future<List<ContractualFinancialDailySnapshot>> findAll({
    required String organizationId,
    String? contractId,
  });

  /// Returns snapshots within a specific date range, optionally filtered by contract.
  Future<List<ContractualFinancialDailySnapshot>> findByDateRange({
    required String organizationId,
    required DateTime startUtc,
    required DateTime endUtc,
    String? contractId,
  });

  /// Checks if a snapshot already exists for a given operational day.
  Future<bool> existsForDate(
    String organizationId,
    DateTime operationalDateUtc, {
    String? contractId,
  });

  /// Returns true if ANY snapshot (active or superseded) in the full history
  /// lists [snapshotId] as its predecessor. Used to enforce strictly linear
  /// custody chains (INV-33): a snapshot that has already been superseded at
  /// any depth must not be used as the base for a new reprocessing branch.
  Future<bool> existsSuperseding(String organizationId, String snapshotId);
}
