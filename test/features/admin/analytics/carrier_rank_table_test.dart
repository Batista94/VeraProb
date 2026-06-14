import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/analytics/carrier_performance_rank.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/features/admin/presentation/analytics/carrier_rank_table.dart';
import 'package:veraprob/state/providers/analytics_providers.dart';

CarrierPerformanceRank _rank(String contractId, int complianceBps) =>
    CarrierPerformanceRank(
      organizationId: 'org-1',
      contractId: contractId,
      totalObligations: 10,
      executedCount: complianceBps ~/ 1000,
      noShowCount: 1,
      evidenceGapCount: 0,
      falsePositiveCount: 0,
      falseNegativeCount: 0,
      complianceRateBps: complianceBps,
      disputeCount: 2,
      disputeRateBps: 2000,
      fineExposure: const Money(90000),
      lastEvaluatedUtc: null,
    );

Widget _host(List<CarrierPerformanceRank> rows) => ProviderScope(
  overrides: [carrierRankingProvider.overrideWith((ref) async => rows)],
  child: const MaterialApp(
    home: Scaffold(body: SizedBox(width: 320, child: CarrierRankTable())),
  ),
);

void main() {
  testWidgets('renders ranked rows with compliance and exposure', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_rank('contractA', 8000)]));
    await tester.pumpAndSettle();

    expect(find.text('contractA'), findsOneWidget);
    expect(find.text('80.00%'), findsOneWidget);
    expect(find.textContaining(r'R$'), findsOneWidget);
    expect(find.byType(Tooltip), findsWidgets);
  });

  testWidgets('shows empty state when no contracts', (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();

    expect(find.text('Sem contratos avaliados ainda.'), findsOneWidget);
  });
}
