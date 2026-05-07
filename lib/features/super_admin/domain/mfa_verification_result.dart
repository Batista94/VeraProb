/// Sealed result of an MFA verification attempt.
///
/// Pure Dart (INV-18). Follows the same sealed-class pattern
/// as [EvidencePayload] in the SLA audit domain.
sealed class MfaVerificationResult {
  const MfaVerificationResult();
}

/// TOTP code verified — session promoted to AAL2.
class MfaVerificationSuccess extends MfaVerificationResult {
  const MfaVerificationSuccess();
}

/// TOTP code rejected or account locked.
class MfaVerificationFailure extends MfaVerificationResult {
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
