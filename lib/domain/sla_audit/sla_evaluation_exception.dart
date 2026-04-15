import 'domain_exception.dart';

/// Exception thrown when SLA evaluation fails due to invalid input.
///
/// Extends [DomainException] to maintain domain-layer error handling consistency.
class SlaEvaluationException extends DomainException {
  const SlaEvaluationException(super.message);
}
