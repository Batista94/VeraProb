import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/application/sla_audit/projections/sla_execution_summary.dart';

void main() {
  group('SlaExecutionSummary', () {
    test('total calculates correctly', () {
      final summary = SlaExecutionSummary(
        contractId: 'c1',
        totalPending: 10,
        totalExecuted: 20,
        totalNoShow: 5,
        totalEvidenceGap: 2,
        generatedAtUtc: DateTime.utc(2026, 3, 1),
      );

      expect(summary.total, 37); // 10 + 20 + 5 + 2
    });

    test('default properties are assigned', () {
      final summary = SlaExecutionSummary(
        totalPending: 1,
        totalExecuted: 1,
        totalNoShow: 1,
        totalEvidenceGap: 1,
        generatedAtUtc: DateTime.utc(2026, 3, 1),
      );

      expect(summary.contractId, isNull);
      expect(summary.protectedRevenue, 0.0);
      expect(summary.revenueAtRisk, 0.0);
      expect(summary.lostRevenue, 0.0);
    });

    test('props computes identical states as equal', () {
      final t = DateTime.utc(2026, 3, 1);
      final s1 = SlaExecutionSummary(
        totalPending: 1,
        totalExecuted: 1,
        totalNoShow: 1,
        totalEvidenceGap: 1,
        generatedAtUtc: t,
      );
      final s2 = SlaExecutionSummary(
        totalPending: 1,
        totalExecuted: 1,
        totalNoShow: 1,
        totalEvidenceGap: 1,
        generatedAtUtc: t,
      );

      expect(s1, equals(s2));
    });
  });
}
