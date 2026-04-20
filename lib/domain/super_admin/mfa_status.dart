/// MFA assurance level — mirrors Supabase AAL.
enum MfaAssuranceLevel { aal1, aal2 }

/// Snapshot of a SuperAdmin's MFA state.
///
/// Pure Dart value object (INV-18). Computed getters drive the
/// presentation-layer routing decision after password login.
class MfaStatus {
  final MfaAssuranceLevel currentLevel;
  final bool hasEnrolledFactor;
  final String? factorId;
  final bool isLockedOut;
  final int failedAttempts;
  final DateTime? lockedUntil;

  const MfaStatus({
    required this.currentLevel,
    required this.hasEnrolledFactor,
    this.factorId,
    this.isLockedOut = false,
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  /// No TOTP factor enrolled — must show enrollment screen.
  bool get needsEnrollment => !hasEnrolledFactor;

  /// Factor enrolled but session is still AAL1 — must show challenge screen.
  bool get needsChallenge =>
      hasEnrolledFactor && currentLevel == MfaAssuranceLevel.aal1;

  /// AAL2 achieved — SuperAdmin portal access granted.
  bool get isFullyAuthenticated =>
      hasEnrolledFactor && currentLevel == MfaAssuranceLevel.aal2;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MfaStatus &&
          currentLevel == other.currentLevel &&
          hasEnrolledFactor == other.hasEnrolledFactor &&
          factorId == other.factorId &&
          isLockedOut == other.isLockedOut &&
          failedAttempts == other.failedAttempts &&
          lockedUntil == other.lockedUntil;

  @override
  int get hashCode => Object.hash(
    currentLevel,
    hasEnrolledFactor,
    factorId,
    isLockedOut,
    failedAttempts,
    lockedUntil,
  );
}
