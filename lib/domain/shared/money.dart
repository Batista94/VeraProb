import 'package:equatable/equatable.dart';

/// Value Object representing a monetary amount in cents.
///
/// Designed to avoid floating-point precision issues in financial calculations.
/// This is the foundation for future financial immutability in the domain.
class Money extends Equatable {
  final int cents;

  const Money(this.cents);

  /// Creates a Money instance from a decimal value (e.g., 10.50 -> 1050 cents).
  /// Uses rounding to avoid precision loss.
  factory Money.fromDouble(double value) {
    // Bridge Utility: Converts decimal to integer cents for storage.
    // Precise rounding applied at boundary to avoid IEEE-754 drift.
    return Money((value * 100).round());
  }

  /// Converts the cents back to a decimal representation (e.g., 1050 -> 10.50).
  double toDouble() => cents / 100.0;

  /// Adds two monetary amounts.
  Money operator +(Money other) {
    return Money(cents + other.cents);
  }

  /// Multiplies the monetary amount by a double multiplier.
  /// Uses rounding for the final cent value.
  Money operator *(double multiplier) {
    // Bridge Utility: Specialized financial math for simple scalar adjustments.
    return Money((cents * multiplier).round());
  }

  /// Multiplies by a basis-points integer (e.g., 10000 = 1.0×, 15000 = 1.5×, 8750 = 87.5%).
  /// Preferred over [operator *] for penalty multipliers — avoids float ambiguity.
  Money multiplyByBps(int bps) {
    return Money((cents * bps) ~/ 10000);
  }

  @override
  List<Object?> get props => [cents];
}
