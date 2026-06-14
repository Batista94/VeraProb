import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/analytics/carrier_performance_rank.dart';
import 'package:veraprob/application/analytics/fleet_risk_window.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/features/admin/presentation/screens/fleet_risk_analytics_screen.dart';
import 'package:veraprob/features/admin/presentation/widgets/risk_thermometer_widget.dart';
import 'package:veraprob/state/providers/analytics_providers.dart';

FleetRiskWindow _window({int riskBps = 5000}) {
  return FleetRiskWindow(
    setId: 'set-1',
    contractId: 'contract-abc',
    windowStartUtc: DateTime.utc(2026, 6, 14, 8),
    windowEndUtc: DateTime.utc(2026, 6, 14, 18),
    // Moderate risk (< 8500 bps) → no pulse animation → pumpAndSettle settles.
    riskBps: riskBps,
    contractualValue: const Money(5000000),
  );
}

Widget _host({
  required AsyncValue<List<FleetRiskWindow>> summary,
  List<CarrierPerformanceRank> ranking = const [],
}) {
  final overrides = <Override>[
    carrierRankingProvider.overrideWith((ref) async => ranking),
  ];
  // Drive the sentinel through the real fleetRiskSummaryProvider override.
  overrides.add(
    fleetRiskSummaryProvider.overrideWith(
      (ref) async => switch (summary) {
        AsyncData(:final value) => value,
        AsyncError(:final error) => throw error,
        _ => <FleetRiskWindow>[],
      },
    ),
  );
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: Scaffold(body: FleetRiskAnalyticsScreen())),
  );
}

void main() {
  group('FleetRiskAnalyticsScreen', () {
    testWidgets('renders the sentinel thermometer + carrier ranking host', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _host(summary: AsyncData([_window(riskBps: 5000)])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Análise de Risco da Frota'), findsOneWidget);
      expect(
        find.text('Sentinela de Risco — Janela Mais Crítica'),
        findsOneWidget,
      );
      expect(find.byType(RiskThermometerWidget), findsOneWidget);
      expect(find.text('contract-abc'), findsOneWidget);
      // Carrier ranking table is mounted (empty ranking → its empty state).
      expect(
        find.text('Ranking de Performance — Transportadoras'),
        findsOneWidget,
      );
    });

    testWidgets('no active windows shows the calm empty message', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _host(summary: const AsyncData(<FleetRiskWindow>[])),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhuma janela de SLA ativa no momento.'),
        findsOneWidget,
      );
      expect(find.byType(RiskThermometerWidget), findsNothing);
    });

    testWidgets('summary error surfaces a domain-language message', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _host(summary: AsyncError(StateError('boom'), StackTrace.empty)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível carregar o risco da frota.'),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
    });
  });
}
