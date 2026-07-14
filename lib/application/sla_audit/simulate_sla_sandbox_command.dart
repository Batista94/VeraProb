import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_overrides.dart';

/// Immutable command DTO for invoking [simulate_sla_sandbox].
///
/// [organizationId] and [callerRole] must be sourced from the authenticated
/// JWT — never from form input (INV-1).
class SimulateSlaSandboxCommand {
  final String organizationId;
  final String contractId;
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;
  final SandboxSimulationOverrides overrides;
  final String sessionLabel;
  final UserRole callerRole;
  final String sessionId;

  const SimulateSlaSandboxCommand({
    required this.organizationId,
    required this.contractId,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.overrides,
    required this.sessionLabel,
    required this.callerRole,
    required this.sessionId,
  });
}
