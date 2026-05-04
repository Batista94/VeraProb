import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:veraprob/domain/auth/auth_failure_exception.dart';

/// INV-26: Error Parity — Intercepts Supabase Auth (GoTrue) errors
/// and maps them to domain-level [AuthFailureException].
///
/// **Security Contract:**
/// - Internal auth codes (invalid_credentials, user_not_found) MUST NOT
///   be distinguishable by the client to prevent user enumeration (INV-1).
/// - Network errors (SocketException) are captured at the repository level,
///   while specific Auth server responses are handled here.
mixin AuthErrorInterceptor {
  /// Maps a Supabase [sb.AuthException] to a domain [AuthFailureException].
  AuthFailureException mapAuthExceptionToDomain(sb.AuthException e) {
    return switch (e.code) {
      // Security: `invalid_credentials` and `user_not_found` return the SAME
      // message to prevent user enumeration attacks (INV-1 / INV-26).
      'invalid_credentials' ||
      'user_not_found' =>
        const AuthFailureException('Credenciais inválidas.'),

      'email_not_confirmed' =>
        const AuthFailureException('E-mail pendente de confirmação.'),

      'weak_password' =>
        const AuthFailureException('A senha não atende os requisitos de segurança.'),

      'rate_limit_exceeded' ||
      'over_request_rate_limit' =>
        const AuthFailureException('Muitas tentativas. Tente novamente mais tarde.'),

      // Fail-safe default message for unknown auth codes
      _ => const AuthFailureException('Erro de autenticação. Tente novamente.'),
    };
  }
}
