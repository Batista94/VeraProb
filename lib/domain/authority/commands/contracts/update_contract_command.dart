import 'package:veraprob/domain/authority/commands/operational_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';

/// Command to update sensitive contractual information.
///
/// REQUIRES: Admin Role and strict Organization (Tenant) Match.
class UpdateContractCommand extends OperationalCommand {
  final String contractId;
  final int newValueCents; // Financial integrity requirement

  @override
  final String targetOrganizationId;

  const UpdateContractCommand({
    required this.contractId,
    required this.newValueCents,
    required this.targetOrganizationId,
  });

  @override
  TargetRef get targetRef => TargetRef('contract', contractId);

  @override
  List<Object?> get props => [contractId, newValueCents, targetOrganizationId];
}
