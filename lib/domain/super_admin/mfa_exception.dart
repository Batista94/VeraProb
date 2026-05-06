/// Domain exception for MFA operations.
/// INV-4: Pure Dart interface — zero infrastructure dependencies.
class MfaException implements Exception {
  final String message;
  final String? code;
  final bool isNotEnabled;

  const MfaException(this.message, {this.code, this.isNotEnabled = false});

  @override
  String toString() => message;
}

/// [CIA: Confidentiality] Thrown when a TOTP code is submitted outside the
/// valid time window (e.g., T-2 or later). Prevents acceptance of intercepted
/// codes that have drifted past the 30-second TOTP window.
/// INV-16: Privileged operations must validate temporal integrity.
class CodeExpiredException extends MfaException {
  const CodeExpiredException()
    : super(
        'Código TOTP expirado. Janela de tempo inválida.',
        code: 'totp_expired',
      );
}

/// [CIA: Confidentiality] Thrown at the model layer for null, empty,
/// wrong-length, or structurally malicious input (SQL/NoSQL injection strings).
/// Fail-fast before the repository processes garbage. INV-16.
class InvalidMfaCodeException extends MfaException {
  final String invalidInput;

  const InvalidMfaCodeException(this.invalidInput)
    : super('Código MFA inválido ou malformado.', code: 'invalid_mfa_code');
}

/// [CIA: Integrity] Thrown when the same TOTP code is submitted a second time
/// within the same challenge window. Enforces the "One-Time" property —
/// one code → one use, atomically. INV-16.
class CodeAlreadyUsedException extends MfaException {
  const CodeAlreadyUsedException()
    : super(
        'Código TOTP já utilizado nesta sessão.',
        code: 'code_already_used',
      );
}

/// [CIA: Availability] Thrown after 5 consecutive failures trigger the
/// circuit-breaker lockout. Carries the unlock timestamp for UI display.
/// INV-16: Privileged account access must enforce brute-force protection.
class MfaLockoutException extends MfaException {
  final int failedAttempts;
  final DateTime? lockedUntil;

  const MfaLockoutException({required this.failedAttempts, this.lockedUntil})
    : super(
        'Conta bloqueada por 15 minutos após 5 tentativas falhas.',
        code: 'mfa_lockout',
      );
}
