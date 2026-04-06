import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/core/config/supabase_client.dart';

/// Read-only query service for contract review data.
///
/// Used exclusively by [ReviewContractScreen] to load the contract summary
/// for display before the contractor accepts.
///
/// Calls the public `get_contract_for_review` RPC which works without
/// Supabase auth (anon key is sufficient).
class PostgresContractReviewTokenQueryService {
  final SupabaseClient _client;

  PostgresContractReviewTokenQueryService([SupabaseClient? client])
    : _client = client ?? supabase;

  /// Returns a [ContractReviewSummary] for the given [token],
  /// or `null` if the token is invalid, expired, or the contract is
  /// no longer in [awaitingContractorAcceptance].
  Future<ContractReviewSummary?> findContractSummaryByToken(
    String token,
  ) async {
    try {
      final result =
          await _client.rpc(
                'get_contract_for_review',
                params: {'p_token': token},
              )
              as Map<String, dynamic>?;

      if (result == null) return null;
      return ContractReviewSummary.fromJson(result);
    } catch (_) {
      return null;
    }
  }
}

/// Read-only projection of a contract for the public review page.
/// No domain methods — pure data carrier (UI model).
class ContractReviewSummary {
  final String contractId;
  final String name;
  final String contractorName;
  final DateTime validFromUtc;
  final DateTime validUntilUtc;
  final int? financialCeilingCents;
  final String status;
  final String organizationId;

  const ContractReviewSummary({
    required this.contractId,
    required this.name,
    required this.contractorName,
    required this.validFromUtc,
    required this.validUntilUtc,
    this.financialCeilingCents,
    required this.status,
    required this.organizationId,
  });

  factory ContractReviewSummary.fromJson(Map<String, dynamic> json) {
    return ContractReviewSummary(
      contractId: json['contract_id'] as String,
      name: json['name'] as String,
      contractorName: json['contractor_name'] as String,
      validFromUtc: DateTime.parse(json['valid_from_utc'] as String).toUtc(),
      validUntilUtc: DateTime.parse(json['valid_until_utc'] as String).toUtc(),
      financialCeilingCents: json['financial_ceiling_cents'] != null
          ? (json['financial_ceiling_cents'] as num).toInt()
          : null,
      status: json['status'] as String,
      organizationId: json['organization_id'] as String,
    );
  }
}
