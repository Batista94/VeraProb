import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contract_detail_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_summary_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_summary.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';

void main() {
  final now = DateTime.utc(2024, 6, 1);

  ContractSummaryView makeSummary() => ContractSummaryView(
    id: 'contract-abc',
    name: 'Rota Central',
    contractorName: 'Viação Express',
    status: ContractStatusView.active,
    validFromUtc: now,
    validUntilUtc: now.add(const Duration(days: 365)),
    createdAtUtc: now,
    planCount: 1,
    activePlanVersion: 1,
    totalSetsInProgress: 0,
    slaHealthBps: 10000,
  );

  SlaExecutionItemView makeExecution() => SlaExecutionItemView(
    setId: 'set-1',
    contractId: 'contract-abc',
    status: ExecutionStatus.completed,
    windowStartUtc: now,
    windowEndUtc: now.add(const Duration(hours: 1)),
    startLatitude: -23.5,
    startLongitude: -46.6,
    startRadiusMeters: 100,
    contractualValue: 50000,
    noShowPenaltyBps: 10000,
  );

  SlaExecutionSummary makeSummaryFinancial() => SlaExecutionSummary(
    contractId: 'contract-abc',
    totalPlanned: 0,
    totalCompleted: 1,
    totalFailed: 0,
    totalCompletedWithGaps: 0,
    generatedAtUtc: now,
    protectedRevenue: 50000,
    revenueAtRisk: 0,
    lostRevenue: 0,
  );

  group('ContractDetailView', () {
    test('id forwards from summary', () {
      final detail = ContractDetailView(
        summary: makeSummary(),
        recentExecutions: [makeExecution()],
        financialSummary: makeSummaryFinancial(),
      );
      expect(detail.id, 'contract-abc');
    });

    test('name forwards from summary', () {
      final detail = ContractDetailView(
        summary: makeSummary(),
        recentExecutions: [],
        financialSummary: makeSummaryFinancial(),
      );
      expect(detail.name, 'Rota Central');
    });

    test('contractorName forwards from summary', () {
      final detail = ContractDetailView(
        summary: makeSummary(),
        recentExecutions: [],
        financialSummary: makeSummaryFinancial(),
      );
      expect(detail.contractorName, 'Viação Express');
    });

    test('props equality works', () {
      final d1 = ContractDetailView(
        summary: makeSummary(),
        recentExecutions: [],
        financialSummary: makeSummaryFinancial(),
      );
      final d2 = ContractDetailView(
        summary: makeSummary(),
        recentExecutions: [],
        financialSummary: makeSummaryFinancial(),
      );
      expect(d1, equals(d2));
    });
  });
}
