/// Sealed result of an MFA verification attempt (presentation layer mirror).
///
/// features/ imports this instead of domain/super_admin/mfa_verification_result.dart.
sealed class MfaVerificationView {
  const MfaVerificationView();
}

/// TOTP code verified — session promoted to AAL2.
class MfaVerificationSuccess extends MfaVerificationView {
  const MfaVerificationSuccess();
}

/// TOTP code rejected or account locked.
class MfaVerificationFailure extends MfaVerificationView {
  final int failedAttempts;
  final bool isLockedOut;
  final DateTime? lockedUntil;
  final String message;

  const MfaVerificationFailure({
    required this.failedAttempts,
    required this.isLockedOut,
    this.lockedUntil,
    required this.message,
  });
}

/// Generic MFA operation error surfaced to the UI.
class MfaOperationFailure implements Exception {
  final String message;
  const MfaOperationFailure(this.message);
}
