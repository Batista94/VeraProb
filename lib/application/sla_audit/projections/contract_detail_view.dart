import 'package:equatable/equatable.dart';

import 'contract_summary_view.dart';
import 'sla_execution_item_view.dart';
import 'sla_execution_summary.dart';

/// Read model: full detail of a single [Contract] for the detail screen.
///
/// Composes [ContractSummaryView] with execution history and financial data.
/// Immutable — no domain logic.
class ContractDetailView extends Equatable {
  final ContractSummaryView summary;

  /// Most recent SET executions for the "Execuções" tab.
  /// Ordered by [SlaExecutionItemView.windowStartUtc] descending.
  final List<SlaExecutionItemView> recentExecutions;

  /// Aggregated financial projection for the "Financeiro" tab.
  final SlaExecutionSummary financialSummary;

  const ContractDetailView({
    required this.summary,
    required this.recentExecutions,
    required this.financialSummary,
  });

  // Convenience forwarding accessors
  String get id => summary.id;
  String get name => summary.name;
  String get contractorName => summary.contractorName;

  @override
  List<Object?> get props => [summary, recentExecutions, financialSummary];
}
