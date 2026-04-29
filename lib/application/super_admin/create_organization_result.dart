/// Immutable result of a successful [CreateOrganizationHandler.handle()] call.
class CreateOrganizationResult {
  final String orgId;
  final String invitationToken;

  /// Plain-text HMAC secret for this org (INV-28).
  /// Non-null on fresh creation — displayed once and never stored in plain text.
  /// Null if the generate-org-secret Edge Function failed (silent degradation).
  final String? orgApiSecret;

  const CreateOrganizationResult({
    required this.orgId,
    required this.invitationToken,
    this.orgApiSecret,
  });
}
