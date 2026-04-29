/// Immutable result of a successful [CreateOrganizationHandler.handle()] call.
class CreateOrganizationResult {
  final String orgId;

  /// One invitation token per admin email, in the same order as the input list.
  final List<String> invitationTokens;

  /// Plain-text HMAC secret for this org (INV-28).
  /// Non-null on fresh creation — displayed once and never stored in plain text.
  /// Null if the generate-org-secret Edge Function failed (silent degradation).
  final String? orgApiSecret;

  const CreateOrganizationResult({
    required this.orgId,
    required this.invitationTokens,
    this.orgApiSecret,
  });

  /// Convenience accessor — first token (always present for single-admin flows).
  String get firstInvitationToken => invitationTokens.first;
}
