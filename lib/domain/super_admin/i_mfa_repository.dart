import 'mfa_challenge_result.dart';
import 'mfa_enrollment_result.dart';
import 'mfa_status.dart';
import 'mfa_verification_result.dart';

/// Port for MFA operations on SuperAdmin accounts.
///
/// Concrete implementation: [SupabaseMfaRepository].
/// INV-4/INV-18: Pure Dart interface — zero infrastructure dependencies.
/// INV-6: SuperAdmin access requires MFA + super_admin=true JWT claim.
abstract class IMfaRepository {
  /// Enrolls a new TOTP factor and generates recovery codes.
  Future<MfaEnrollmentResult> enrollTotp();

  /// Creates a challenge for an enrolled TOTP factor.
  Future<MfaChallengeResult> createChallenge(String factorId);

  /// Verifies a TOTP code against a challenge.
  /// Handles circuit-breaker lockout (5 failures → 15 min).
  Future<MfaVerificationResult> verifyChallenge({
    required String factorId,
    required String challengeId,
    required String code,
  });

  /// Returns the current MFA status (assurance level, enrollment, lockout).
  Future<MfaStatus> getMfaStatus();
}
