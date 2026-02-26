import 'package:equatable/equatable.dart';

/// Value Object representing a monetary amount in cents.
///
/// Designed to avoid floating-point precision issues in financial calculations.
/// This is the foundation for future financial immutability in the domain.
class Money extends Equatable {
  final int cents;

  const Money(this.cents);

  /// Creates a Money instance from a double value (e.g., 10.50 -> 1050 cents).
  /// Uses rounding to avoid precision loss.
  factory Money.fromDouble(double value) {
    return Money((value * 100).round());
  }

  /// Converts the cents back to a double representation (e.g., 1050 -> 10.50).
  double toDouble() => cents / 100.0;

  /// Adds two monetary amounts.
  Money operator +(Money other) {
    return Money(cents + other.cents);
  }

  /// Multiplies the monetary amount by a double multiplier.
  /// Uses rounding for the final cent value.
  Money operator *(double multiplier) {
    return Money((cents * multiplier).round());
  }

  @override
  List<Object?> get props => [cents];
}
