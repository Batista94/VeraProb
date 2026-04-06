import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'sla_execution_item_view.dart';
import 'sla_execution_summary.dart';

/// Read-only query service for SLA execution projections.
///
/// Maps [ContractualExecutionState] aggregates to read models.
/// Does NOT alter any state.
abstract class SlaExecutionQueryService {
  /// Returns a summary of execution states, optionally filtered by contract.
  Future<SlaExecutionSummary> getSummary({
    required String organizationId,
    String? contractId,
  });

  /// Returns execution items filtered by status, optionally by contract.
  /// Ordered by [windowStartUtc] ascending.
  Future<List<SlaExecutionItemView>> listByStatus(
    ExecutionStatus status, {
    required String organizationId,
    String? contractId,
  });

  /// Returns execution items whose window starts within the given UTC bounds.
  /// Ordered by [windowStartUtc] ascending.
  Future<List<SlaExecutionItemView>> listByWindow(
    DateTime startUtc,
    DateTime endUtc, {
    required String organizationId,
    String? contractId,
  });

  /// Returns the execution item matching [setId] within the given organization.
  ///
  /// Returns null if not found or if RLS blocks access.
  Future<SlaExecutionItemView?> findBySetId(
    String setId, {
    required String organizationId,
  });
}
