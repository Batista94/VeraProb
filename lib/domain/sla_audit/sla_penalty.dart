import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/shared/money.dart';

/// Value Object representing the result of an SLA penalty calculation.
///
/// Invariants:
/// - INV-4: zero Flutter/Supabase dependencies.
/// - INV-19: penalty uses Money (BIGINT cents) for precision.
class SlaPenalty extends Equatable {
  /// The final penalty amount in cents.
  final Money penalty;

  /// The tier name that was applied (e.g., "No Penalty", "Tier 1", "Tier 2").
  final String appliedTier;

  const SlaPenalty({required this.penalty, required this.appliedTier});

  @override
  List<Object?> get props => [penalty, appliedTier];
}
