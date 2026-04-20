/// Thrown when an atomic status update detects a concurrent modification.
///
/// This occurs when `updateStatusAtomic` returns 0 rows affected,
/// meaning another concurrent operation already changed the justification's
/// status before this operation could complete.
///
/// Callers should surface this as a 409 Conflict HTTP response and advise
/// the user to reload and retry.
class ConcurrencyException implements Exception {
  final String message;

  const ConcurrencyException(this.message);

  @override
  String toString() => 'ConcurrencyException: $message';
}
