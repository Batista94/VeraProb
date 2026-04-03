import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact_query_service.dart';
import 'package:veraprob/domain/shared/money.dart';
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
  }) async {
    throw Exception('Falha de conexão');
  }
}

Widget buildTestWidget({
  required ContractualFinancialImpactQueryService service,
}) {
  return ProviderScope(
    overrides: [
      financialImpactQueryServiceProvider.overrideWithValue(service),
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
    totalContractedRevenue: Money.fromDouble(1000.0),
    protectedRevenue: Money.fromDouble(500.0),
    revenueAtRisk: Money.fromDouble(300.0),
    lostRevenue: Money.fromDouble(200.0),
    riskPercentageBps: 3000,
    lossPercentageBps: 2000,
  );

  group('SlaFinancialImpactScreen', () {
    testWidgets('renders 4 KPI cards with correct titles', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = FakeFinancialImpactQueryService(sampleImpact);
      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

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

      expect(find.textContaining(r'R$'), findsNWidgets(4));
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

    testWidgets('shows loading indicator before data', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = FakeFinancialImpactQueryService(sampleImpact);
      await tester.pumpWidget(buildTestWidget(service: service));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state on service failure', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = ErrorFinancialImpactQueryService();
      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      expect(find.text('Erro ao carregar impacto financeiro'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });
}
