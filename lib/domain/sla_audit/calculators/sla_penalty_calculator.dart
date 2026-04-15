import 'package:veraprob/domain/sla_audit/sla_calculation_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_penalty.dart';

import '../contract.dart';
import 'package:veraprob/domain/shared/money.dart';

/// SLA Penalty Calculator using tier step function.
///
/// **Tier Step Function:**
/// - < 900s (15min) → No Penalty (0 BPS)
/// - ≥ 900s and < 1800s (15-29min) → Tier 1 (500 BPS)
/// - ≥ 1800s (30min+) → Tier 2 (1200 BPS)
///
/// **Penalty Formula:**
/// ```
/// tierBps = lookupTier(delay)
/// tierAmount = (base × tierBps + 5000) ~/ 10000  // Symmetric Rounding
/// finalPenalty = tierAmount + fixedPenalty
/// ```
///
/// Invariants:
/// - INV-4: zero Flutter/Supabase dependencies.
/// - INV-19: BPS precision with symmetric rounding.
/// - INV-9: All DateTime fields are UTC.
/// - Non-negative: Never returns negative penalty.
class SlaPenaltyCalculator {
  /// Tier 1 threshold: 15 minutes = 900 seconds.
  static const int tier1ThresholdSeconds = 900;

  /// Tier 2 threshold: 30 minutes = 1800 seconds.
  static const int tier2ThresholdSeconds = 1800;

  /// Tier 1 BPS: 500 (0.5% of base).
  static const int tier1Bps = 500;

  /// Tier 2 BPS: 1200 (1.2% of base).
  static const int tier2Bps = 1200;

  const SlaPenaltyCalculator();

  /// Calculates the SLA penalty for a given contract and delay.
  ///
  /// [contract] - The contract with base penalty information.
  /// [delay] - The delay duration (positive = late, negative = early).
  /// [fixedPenalty] - Optional fixed penalty in cents (e.g., R$ 50.00 = 5000 cents).
  ///
  /// Returns [SlaPenalty] with the calculated penalty and applied tier name.
  ///
  /// Throws [SlaCalculationException] if contract is null or base is missing.
  SlaPenalty calculate({
    required Contract contract,
    required Duration delay,
    Money? fixedPenalty,
  }) {
    if (contract.financialCeiling == null) {
      throw const SlaCalculationException(
        'Contract must have a financialCeiling (base penalty) defined',
      );
    }

    // Non-negative guard: early delivery = no penalty
    if (delay.isNegative) {
      return const SlaPenalty(penalty: Money(0), appliedTier: 'No Penalty');
    }

    final base = contract.financialCeiling!;
    final tierBps = _lookupTier(delay.inSeconds);
    final tierName = _getTierName(tierBps);

    // Calculate tier amount: (base × bps + 5000) ~/ 10000
    final tierAmount = base.multiplyByBps(tierBps);

    // Add fixed penalty if provided
    final finalPenalty = fixedPenalty != null
        ? tierAmount + fixedPenalty
        : tierAmount;

    return SlaPenalty(penalty: finalPenalty, appliedTier: tierName);
  }

  /// Looks up the BPS value for a given delay using step function.
  ///
  /// < 900s → 0 BPS (No Penalty)
  /// ≥ 900s and < 1800s → 500 BPS (Tier 1)
  /// ≥ 1800s → 1200 BPS (Tier 2)
  int _lookupTier(int seconds) {
    if (seconds < tier1ThresholdSeconds) {
      return 0;
    } else if (seconds < tier2ThresholdSeconds) {
      return tier1Bps;
    } else {
      return tier2Bps;
    }
  }

  /// Returns the tier name for a given BPS value.
  String _getTierName(int bps) {
    if (bps == 0) {
      return 'No Penalty';
    } else if (bps == tier1Bps) {
      return 'Tier 1';
    } else if (bps == tier2Bps) {
      return 'Tier 2';
    } else {
      return 'Unknown';
    }
  }
}
