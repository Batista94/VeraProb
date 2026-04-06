import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'contractual_service_input.dart';

/// Immutable command DTO for declaring a contractual operational plan.
///
/// Contains ZERO logic. Carries only the data required by the
/// [DeclareContractualPlanHandler] to create a [PlanDeclaration] aggregate.
///
/// Does NOT extend [OperationalCommand] — plan declaration is an
/// administrative setup action, not a real-time operational mutation.
///
/// **Two modes (mutually exclusive):**
/// - **Manual** (baseline): populate [services]; leave [shiftPatterns] empty.
/// - **B2B shift-based**: populate [shiftPatterns] + [contractualValueCents];
///   leave [services] empty.
class DeclareContractualPlanCommand {
  final String organizationId;
  final String contractId;
  final String declaredByUserId;
  final int planVersion;
  final String originalFileHash;
  final DateTime declaredAtUtc;

  /// Manual mode: explicit service execution inputs.
  /// Empty for shift-based plans.
  final List<ContractualServiceInput> services;

  /// B2B mode: shift recurrence patterns.
  /// Empty for manual plans.
  final List<ShiftPattern> shiftPatterns;

  /// Base contractual value in cents per projected SET.
  /// Required (> 0) when [shiftPatterns] is non-empty.
  final int contractualValueCents;

  const DeclareContractualPlanCommand({
    required this.organizationId,
    required this.contractId,
    required this.declaredByUserId,
    required this.planVersion,
    required this.originalFileHash,
    required this.declaredAtUtc,
    this.services = const [],
    this.shiftPatterns = const [],
    this.contractualValueCents = 0,
  });
}
