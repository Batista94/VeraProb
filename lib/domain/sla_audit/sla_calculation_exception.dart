import 'domain_exception.dart';

/// Exception thrown when SLA penalty calculation fails due to invalid input.
///
/// Extends [DomainException] to maintain domain-layer error handling consistency.
class SlaCalculationException extends DomainException {
  const SlaCalculationException(super.message);
}
