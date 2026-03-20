/// Immutable result of a successful [CreateOrganizationHandler.handle()] call.
class CreateOrganizationResult {
  final String orgId;
  final String invitationToken;

  const CreateOrganizationResult({
    required this.orgId,
    required this.invitationToken,
  });
}
