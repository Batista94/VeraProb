// admin_layout_test.dart
//
// P3: regressão do shell responsivo. O bottom NavigationBar (compact) tem
// apenas [pillarCount] destinos, mas o shell tem 17 branches — o índice real
// PRECISA passar por [railIndexFor], senão qualquer deep branch (>= 6) em
// largura compacta estoura o assert `selectedIndex < destinations.length`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veraprob/application/projections/providers/feed_health_projection_provider.dart';
import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/features/admin/presentation/widgets/admin_layout.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/features/admin/providers/vehicles_provider.dart';
import 'package:veraprob/state/providers/alert_providers.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/contractor_providers.dart';
import 'package:veraprob/state/providers/justification_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';

/// 17 branches espelhando o shell real (6 pilares + 11 deep-hub).
const _kBranchCount = 17;

class _EmptyAlertsNotifier extends ActiveAlertsNotifier {
  @override
  Stream<List<OperationalAlert>> build() =>
      Stream.value(const <OperationalAlert>[]);
}

GoRouter _buildRouter(int initialBranch) {
  return GoRouter(
    initialLocation: '/b$initialBranch',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AdminLayout(navigationShell: shell),
        branches: [
          for (var i = 0; i < _kBranchCount; i++)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/b$i',
                  builder: (context, state) => Text('branch-$i'),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

Widget _wrap(GoRouter router) {
  return ProviderScope(
    overrides: [
      pendingSanctionsCountProvider.overrideWithValue(0),
      pendingJustificationsCountProvider.overrideWithValue(0),
      activeAlertsStreamProvider.overrideWith(_EmptyAlertsNotifier.new),
      feedHealthProjectionProvider.overrideWithValue(
        const FeedHealthProjection(
          status: FeedHealthStatus.offline,
          currentDelayMs: 0,
          activeVehicles: 0,
        ),
      ),
      operationalZonesProvider.overrideWith((ref) async => []),
      contractorListProvider.overrideWith((ref) async => []),
      vehiclesListProvider.overrideWith((ref) async => []),
      slaTemplatesProvider.overrideWith((ref) async => []),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  Future<void> setViewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('AdminLayout — responsive shell', () {
    testWidgets('compact + deep hub branch não crasha o bottom NavigationBar', (
      tester,
    ) async {
      await setViewport(tester, const Size(500, 900));

      // Branch 16 (deep hub) — sem railIndexFor isso estourava o assert
      // selectedIndex < destinations.length do NavigationBar.
      await tester.pumpWidget(_wrap(_buildRouter(_kBranchCount - 1)));
      await tester.pump();

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, railIndexFor(_kBranchCount - 1));
      expect(bar.selectedIndex, lessThan(pillarCount));
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('branch-${_kBranchCount - 1}'), findsOneWidget);

      // Descarta a árvore para cancelar os timers do AdminSessionKeepAlive.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('compact + branch pilar seleciona o próprio destino', (
      tester,
    ) async {
      await setViewport(tester, const Size(500, 900));

      await tester.pumpWidget(_wrap(_buildRouter(2)));
      await tester.pump();

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 2);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('wide usa NavigationRail, sem bottom NavigationBar', (
      tester,
    ) async {
      await setViewport(tester, const Size(1400, 900));

      await tester.pumpWidget(_wrap(_buildRouter(0)));
      await tester.pump();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
