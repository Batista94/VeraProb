/// Immutable command DTO for creating a new tenant organization.
///
/// Carries all data from the 3-step wizard.
/// Contains ZERO logic — pure data transfer.
/// INV-4: Pure Dart — zero infrastructure dependencies.
class CreateOrganizationCommand {
  final String legalName;
  final String tradeName;
  final String cnpj;
  final String timezone;
  final String currencyCode;
  final String planType;
  final int maxVehicles;
  final int maxActiveContracts;
  final String initialAdminEmail;
  final String superAdminUserId;

  const CreateOrganizationCommand({
    required this.legalName,
    required this.tradeName,
    required this.cnpj,
    required this.timezone,
    required this.currencyCode,
    required this.planType,
    required this.maxVehicles,
    required this.maxActiveContracts,
    required this.initialAdminEmail,
    required this.superAdminUserId,
  });
}
