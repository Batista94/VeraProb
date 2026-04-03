import 'package:veraprob/domain/super_admin/create_organization_command.dart';

/// Mutable form DTO for the Create Organization wizard.
///
/// All fields are primitives — no domain types leak into features/.
/// Call [toCommand] to produce the [CreateOrganizationCommand] for dispatch.
class CreateOrganizationFormData {
  final String legalName;
  final String tradeName;
  final String cnpj;
  final String timezone;
  final String currencyCode;
  final String planType;
  final int? maxVehicles;
  final int? maxActiveContracts;
  final String initialAdminEmail;
  final String superAdminUserId;

  const CreateOrganizationFormData({
    required this.legalName,
    required this.tradeName,
    required this.cnpj,
    required this.timezone,
    required this.currencyCode,
    required this.planType,
    this.maxVehicles,
    this.maxActiveContracts,
    required this.initialAdminEmail,
    required this.superAdminUserId,
  });

  CreateOrganizationCommand toCommand() {
    return CreateOrganizationCommand(
      legalName: legalName,
      tradeName: tradeName,
      cnpj: cnpj,
      timezone: timezone,
      currencyCode: currencyCode,
      planType: planType,
      maxVehicles: maxVehicles,
      maxActiveContracts: maxActiveContracts,
      initialAdminEmail: initialAdminEmail,
      superAdminUserId: superAdminUserId,
    );
  }
}
