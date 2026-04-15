/// Domain-layer exception for execution invariant violations.
class ExecutionDomainException implements Exception {
  final String message;

  const ExecutionDomainException(this.message);

  @override
  String toString() => 'ExecutionDomainException: $message';
}
