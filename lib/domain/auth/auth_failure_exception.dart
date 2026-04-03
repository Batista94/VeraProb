/// Domain-scoped exception for authentication failures.
///
/// Prevents leaking [AuthException] from `supabase_flutter` into the
/// domain layer. INV-18: domain must remain infrastructure-free.
class AuthFailureException implements Exception {
  final String message;

  const AuthFailureException(this.message);

  @override
  String toString() => 'AuthFailureException: $message';
}
