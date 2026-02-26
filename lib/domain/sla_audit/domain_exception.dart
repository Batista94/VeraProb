/// Domain-layer exception for invariant violations.
///
/// Thrown when an aggregate root or entity detects that a business rule
/// has been violated during creation or state transition.
class DomainException implements Exception {
  final String message;

  const DomainException(this.message);

  @override
  String toString() => 'DomainException: $message';
}
