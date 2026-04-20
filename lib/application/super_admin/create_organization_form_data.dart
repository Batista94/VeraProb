import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';

/// Mutable form DTO for the Create Organization wizard.
///
/// Pilar INV-18: Use domain types (PlanType) instead of raw strings.
class CreateOrganizationFormData {
  final String legalName;
  final String tradeName;
  final String cnpj;
  final String timezone;
  final String currencyCode;
  final PlanType planType; // Changed from String to PlanType
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
      planType: planType, // Pure enum
      maxVehicles: maxVehicles,
      maxActiveContracts: maxActiveContracts,
      initialAdminEmail: initialAdminEmail,
      superAdminUserId: superAdminUserId,
    );
  }
}
