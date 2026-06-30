import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/financial_sparkline_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/financial_sparkline_series.dart';
import 'package:veraprob/features/admin/presentation/screens/sla_financial_impact_screen.dart';
import 'package:veraprob/state/providers/sla_financial_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// Fake implementation for widget testing.
class FakeFinancialImpactQueryService
    implements ContractualFinancialImpactQueryService {
  final ContractualFinancialImpact _impact;

  FakeFinancialImpactQueryService(this._impact);

  @override
  Future<ContractualFinancialImpact> getImpact({
    required String organizationId,
    String? contractId,
    DateTime? startUtc,
    DateTime? endUtc,
  }) async {
    return _impact;
  }
}

class ErrorFinancialImpactQueryService
    implements ContractualFinancialImpactQueryService {
  @override
  Future<ContractualFinancialImpact> getImpact({
    required String organizationId,
    String? contractId,
    DateTime? startUtc,
    DateTime? endUtc,
  }) async {
    throw Exception('Falha de conexão');
  }
}

class FakeSparklineQueryService implements FinancialSparklineQueryService {
  @override
  Future<FinancialSparklineSeries> getSparkline({
    required String organizationId,
    required int days,
  }) async {
    return FinancialSparklineSeries.empty;
  }
}

Widget buildTestWidget({
  required ContractualFinancialImpactQueryService service,
  FinancialSparklineQueryService? sparklineService,
}) {
  return ProviderScope(
    overrides: [
      financialImpactQueryServiceProvider.overrideWithValue(service),
      financialSparklineQueryServiceProvider.overrideWithValue(
        sparklineService ?? FakeSparklineQueryService(),
      ),
      // financialImpactProvider reads currentOrganizationIdProvider to scope
      // the query. Without a real auth session in tests, this returns null and
      // the service is never called. Override it with a fixed test org.
      currentOrganizationIdProvider.overrideWithValue('org-test'),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 900,
          child: SlaFinancialImpactScreen(),
        ),
      ),
    ),
  );
}

void main() {
  final sampleImpact = ContractualFinancialImpact(
    contractId: null,
    generatedAtUtc: DateTime.utc(2026, 3, 1, 12, 0),
    totalContractedRevenue: 100000,
    protectedRevenue: 50000,
    revenueAtRisk: 30000,
    lostRevenue: 20000,
    riskPercentageBps: 3000,
    lossPercentageBps: 2000,
  );

  group('SlaFinancialImpactScreen', () {
    testWidgets('renders Visão Executiva header and 4 KPI cards', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = FakeFinancialImpactQueryService(sampleImpact);
      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // New header (renamed from 'Impacto Financeiro do SLA')
      expect(find.text('Visão Executiva'), findsAtLeastNWidgets(1));
      expect(find.text('RECEITA TOTAL CONTRATADA'), findsOneWidget);
      expect(find.text('RECEITA PROTEGIDA'), findsOneWidget);
      expect(find.text('RECEITA EM RISCO'), findsOneWidget);
      expect(find.text('RECEITA PERDIDA'), findsOneWidget);
    });

    testWidgets('formats monetary values as BRL currency', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = FakeFinancialImpactQueryService(sampleImpact);
      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      expect(find.textContaining('R\$'), findsAtLeastNWidgets(4));
    });

    testWidgets('displays risk and loss percentages', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = FakeFinancialImpactQueryService(sampleImpact);
      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      expect(find.text('30.0%'), findsOneWidget);
      expect(find.text('20.0%'), findsOneWidget);
    });

    testWidgets(
      'shows skeleton loader before data (no CircularProgressIndicator)',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final service = FakeFinancialImpactQueryService(sampleImpact);
        await tester.pumpWidget(buildTestWidget(service: service));

        // Loading state uses SkeletonListLoader (ListView), not CircularProgressIndicator
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(ListView), findsOneWidget);
      },
    );

    testWidgets('shows error state on service failure', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = ErrorFinancialImpactQueryService();
      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();
      await tester.pump(
        const Duration(seconds: 1),
      ); // allow Future to resolve and state to update

      expect(find.text('Falha ao carregar visão executiva'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('renders 7d/30d SegmentedButton window toggle', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = FakeFinancialImpactQueryService(sampleImpact);
      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pump();

      expect(find.byType(SegmentedButton<int>), findsOneWidget);
      expect(find.text('7 dias'), findsOneWidget);
      expect(find.text('30 dias'), findsOneWidget);
    });
  });
}
