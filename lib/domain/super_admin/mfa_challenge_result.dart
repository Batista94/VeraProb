/// Result of creating an MFA challenge — contains the IDs
/// needed to submit a TOTP verification code.
///
/// Pure Dart value object (INV-18).
class MfaChallengeResult {
  final String challengeId;
  final String factorId;

  const MfaChallengeResult({required this.challengeId, required this.factorId});
}
