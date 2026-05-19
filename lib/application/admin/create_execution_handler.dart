import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/admin/create_execution_command.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';

/// Application handler: delegates create_execution_for_operator RPC.
/// INV-1: assertTenantMatches before any RPC. INV-13: infra client injected.
class CreateExecutionHandler {
  final SupabaseClient _client;
  final TenantValidationService _tenantValidator;

  CreateExecutionHandler({
    required SupabaseClient client,
    required TenantValidationService tenantValidator,
  }) : _client = client,
       _tenantValidator = tenantValidator;

  Future<String> handle(CreateExecutionCommand cmd) async {
    // ── INV-1: Fail-Fast tenant check ────────────────────────────────────
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: cmd.organizationId,
      sessionId: cmd.sessionId,
    );

    final data = await _client.rpc<String>(
      'create_execution_for_operator',
      params: {
        'p_organization_id': cmd.organizationId,
        'p_contract_id': cmd.contractId,
        'p_driver_id': cmd.driverId,
        'p_vehicle_id': cmd.vehicleId,
        'p_origin_zone_id': cmd.originZoneId,
        'p_destination_zone_id': cmd.destinationZoneId,
        'p_window_start_utc': cmd.windowStartUtc.toUtc().toIso8601String(),
        'p_window_end_utc': cmd.windowEndUtc.toUtc().toIso8601String(),
      },
    );
    return data;
  }
}
