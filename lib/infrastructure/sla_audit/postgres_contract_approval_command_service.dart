import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/sla_audit/contract_approval_command_service.dart';

/// PostgreSQL implementation of [ContractApprovalCommandService] via Supabase RPCs.
///
/// Both operations are SECURITY DEFINER RPCs that handle authorization and
/// atomicity server-side.
class PostgresContractApprovalCommandService
    implements ContractApprovalCommandService {
  final SupabaseClient client;

  PostgresContractApprovalCommandService(this.client);

  @override
  Future<void> submitForApproval({
    required String contractId,
    required String organizationId,
    required String tokenId,
    required String token,
    required DateTime expiresAtUtc,
    int? expectedVersion,
  }) async {
    await client.rpc(
      'submit_contract_for_approval',
      params: {
        'p_contract_id': contractId,
        'p_token_id': tokenId,
        'p_token': token,
        'p_expires_at': expiresAtUtc.toIso8601String(),
        'p_expected_version': expectedVersion,
      },
    );
  }

  @override
  Future<({String contractId, String organizationId})> acceptByContractor({
    required String token,
  }) async {
    final result =
        await client.rpc(
              'accept_contract_by_contractor',
              params: {'p_token': token},
            )
            as Map<String, dynamic>;

    return (
      contractId: result['contract_id'] as String,
      organizationId: result['organization_id'] as String,
    );
  }
}
