import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/sandbox_simulation_service.dart';
import 'package:veraprob/application/sla_audit/simulate_sla_sandbox_command.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/domain/sla_audit/sandbox_simulation_exception.dart';

/// Application handler for [SimulateSlaSandboxCommand].
///
/// Enforces tenant isolation (INV-1), RBAC (`TENANT_ADMIN` or
/// `sandbox:simulate`), and client-side period guards before invoking the RPC.
class SimulateSlaSandboxHandler {
  static const Duration _maxPeriod = Duration(days: 183);

  final TenantValidationService _tenantValidator;
  final SandboxSimulationCommandService _commandService;
  final PermissionService _permissions;

  SimulateSlaSandboxHandler({
    required TenantValidationService tenantValidator,
    required SandboxSimulationCommandService commandService,
    required PermissionService permissions,
  }) : _tenantValidator = tenantValidator,
       _commandService = commandService,
       _permissions = permissions;

  /// Returns the UUID of the created simulation session.
  Future<String> handle(SimulateSlaSandboxCommand command) async {
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    _assertAuthorized(command.callerRole);
    _validatePeriod(command);
    command.overrides.validate();

    return _commandService.simulate(
      organizationId: command.organizationId,
      contractId: command.contractId,
      periodStartUtc: command.periodStartUtc,
      periodEndUtc: command.periodEndUtc,
      overrides: command.overrides,
      sessionLabel: command.sessionLabel,
    );
  }

  void _assertAuthorized(UserRole callerRole) {
    final isTenantAdmin = callerRole == UserRole.admin;
    final hasSimulatePermission = _permissions.hasPermission(
      'sandbox:simulate',
    );
    if (!isTenantAdmin && !hasSimulatePermission) {
      throw SandboxSimulationException(SandboxSimulationFailure.unauthorized);
    }
  }

  void _validatePeriod(SimulateSlaSandboxCommand command) {
    if (!command.periodStartUtc.isUtc || !command.periodEndUtc.isUtc) {
      throw SandboxSimulationException(SandboxSimulationFailure.invalidPeriod);
    }
    if (!command.periodEndUtc.isAfter(command.periodStartUtc)) {
      throw SandboxSimulationException(SandboxSimulationFailure.invalidPeriod);
    }
    if (command.periodEndUtc.difference(command.periodStartUtc) > _maxPeriod) {
      throw SandboxSimulationException(SandboxSimulationFailure.periodTooLong);
    }
  }
}
