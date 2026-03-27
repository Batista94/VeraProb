import 'contract_status_view.dart';
import 'contract_detail_view.dart';
import 'contract_summary_view.dart';

/// Read-only query service for [Contract] projections.
///
/// All methods are scoped by [organizationId] (multi-tenancy invariant).
/// Does NOT alter any state — pure read model.
///
/// Implementations: [ContractQueryServiceInMemory] (tests),
/// [ContractQueryServicePostgres] (production — Phase 5 infrastructure).
abstract class ContractQueryService {
  /// Returns all contracts for [organizationId], optionally filtered by [status].
  ///
  /// Ordered by [ContractSummaryView.createdAtUtc] descending.
  Future<List<ContractSummaryView>> listContracts({
    required String organizationId,
    ContractStatusView? status,
  });

  /// Returns the full detail view for a single contract.
  ///
  /// Returns `null` if not found or if the contract belongs to a different
  /// organization (tenant isolation).
  Future<ContractDetailView?> getContractDetail({
    required String organizationId,
    required String contractId,
  });
}
