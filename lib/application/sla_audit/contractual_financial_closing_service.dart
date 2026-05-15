import 'package:veraprob/domain/shared/brazil_time.dart';
import 'projections/contractual_financial_snapshot_generator.dart';

/// Automated daily financial closing service.
///
/// Tracks the last closed operational day and generates a snapshot
/// for the previous day whenever a day transition is detected.
///
/// Designed to be called repeatedly (e.g., from a sweep timer)
/// without side effects on repeated calls within the same day.
///
/// Does NOT maintain its own timer — relies on external `onTick()` calls.
class ContractualFinancialClosingService {
  final ContractualFinancialSnapshotGenerator _generator;

  /// The last operational day for which a snapshot was generated.
  DateTime? _lastClosedOperationalDateUtc;

  ContractualFinancialClosingService({
    required ContractualFinancialSnapshotGenerator generator,
  }) : _generator = generator;

  /// Returns the last closed operational date (for testing/debugging).
  DateTime? get lastClosedOperationalDateUtc => _lastClosedOperationalDateUtc;

  /// Checks for day transition and generates snapshot if needed.
  ///
  /// Flow:
  /// 1. Get current BRT time → derive current operational date
  /// 2. If the operational date has changed since last close:
  ///    - Generate snapshot for the *previous* day
  ///    - Update internal state
  /// 3. If first call ever, just record the current day (no snapshot)
  /// [organizationId] is required to scope the generated snapshot.
  Future<void> onTick(String organizationId, {DateTime? closedAtUtc}) async {
    final nowBrt = BrazilTime.nowBrazil();
    final currentOperationalDate = BrazilTime.toOperationalDateUtc(nowBrt);

    if (_lastClosedOperationalDateUtc == null) {
      // First call: just record the current day, don't generate
      _lastClosedOperationalDateUtc = currentOperationalDate;
      return;
    }

    if (currentOperationalDate != _lastClosedOperationalDateUtc) {
      // Day transition detected — close the previous day
      await _generator.generateDailySnapshot(
        organizationId,
        _lastClosedOperationalDateUtc!,
        closedAtUtc: closedAtUtc,
      );
      _lastClosedOperationalDateUtc = currentOperationalDate;
    }
  }
}
