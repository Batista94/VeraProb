/// Result of TOTP enrollment — contains everything needed
/// for the user to configure their authenticator app.
///
/// Pure Dart value object (INV-18).
class MfaEnrollmentResult {
  /// Supabase MFA factor ID.
  final String factorId;

  /// `otpauth://` URI for QR code rendering.
  final String totpUri;

  /// Base32-encoded secret for manual entry.
  final String secret;

  /// One-time recovery codes (plain text, shown once).
  final List<String> recoveryCodes;

  const MfaEnrollmentResult({
    required this.factorId,
    required this.totpUri,
    required this.secret,
    required this.recoveryCodes,
  });
}
