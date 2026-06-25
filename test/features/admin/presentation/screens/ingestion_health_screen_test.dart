import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade_drawer.dart';
import 'package:veraprob/features/admin/presentation/screens/ingestion_health_screen.dart';
import 'package:veraprob/state/providers/fleet_health_providers.dart';

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _kOrgVehicleId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _kOtherVehicleId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

VehicleHealthEntry _entry({String? vehicleId = _kOrgVehicleId}) =>
    VehicleHealthEntry(
      vehicleId: vehicleId,
      plate: vehicleId == null ? null : 'ABC-1234',
      model: 'Volvo FH',
      deviceId: 'SASCAR-0x7F3A',
      lastPingUtc: DateTime.utc(2026, 6, 20, 12),
      gapSeconds: 90,
      hardwareStatus: HardwareStatusView.delayed,
      integrityScoreBps: 6500,
      anomalyCount24h: 0,
    );

FleetHealthView _view({bool includeTarget = true}) => FleetHealthView(
  vehicles: [if (includeTarget) _entry()],
  healthyCount: 0,
  delayedCount: includeTarget ? 1 : 0,
  offlineCount: 0,
  neverSeenCount: 0,
  fleetActiveRatioBps: 6500,
);

// ── Test host helpers ─────────────────────────────────────────────────────────

/// Minimal router: ingestion-health nested under /admin/hub so shell is
/// preserved and back nav (`context.go(AppRoutes.adminHub)`) doesn't 404.
GoRouter _router({String? vehicleId}) {
  final location = vehicleId != null
      ? '${AppRoutes.adminHub}/ingestion-health?vehicleId=$vehicleId'
      : '${AppRoutes.adminHub}/ingestion-health';
  return GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: AppRoutes.adminHub,
        builder: (_, _) => const Scaffold(body: Text('hub')),
        routes: [
          GoRoute(
            path: 'ingestion-health',
            builder: (context, state) => IngestionHealthScreen(
              preselectedVehicleId: state.uri.queryParameters['vehicleId'],
            ),
          ),
        ],
      ),
    ],
  );
}

Widget _host(ProviderContainer container, GoRouter router) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

ProviderContainer _container({
  Stream<FleetHealthView>? healthStream,
  bool includeTarget = true,
}) {
  return ProviderContainer(
    overrides: [
      fleetHealthPollingProvider.overrideWith(
        (ref) =>
            healthStream ?? Stream.value(_view(includeTarget: includeTarget)),
      ),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('IngestionHealthScreen', () {
    setUpAll(() async {
      await initializeDateFormatting('pt_BR', null);
    });

    testWidgets('renders vehicle list and header without preselection', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = _container();
      addTearDown(container.dispose);
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(container, router));
      await tester.pumpAndSettle();

      expect(find.text('Monitor de Saúde da Ingestão'), findsOneWidget);
      expect(find.text('ABC-1234'), findsOneWidget);
      // No drill-down → detail panel collapsed
      expect(find.text('Integridade do Sinal'), findsNothing);
      // No vehicle selected in provider
      expect(container.read(selectedHealthVehicleIdProvider), isNull);
    });

    testWidgets('resolves preselection immediately and opens detail panel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = _container();
      addTearDown(container.dispose);
      final router = _router(vehicleId: _kOrgVehicleId);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(container, router));
      // One pump for stream emission + postFrameCallback resolution.
      await tester.pump();
      await tester.pump();

      // Provider updated with the resolved id.
      expect(container.read(selectedHealthVehicleIdProvider), _kOrgVehicleId);
      // Detail panel visible.
      expect(find.text('Integridade do Sinal'), findsOneWidget);
      expect(find.text('ABC-1234'), findsWidgets);
    });

    testWidgets('shows absent snackbar when id is not in org fleet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Fleet loads but does NOT contain _kOtherVehicleId (Anti-Oracle INV-26).
      final container = _container(includeTarget: true);
      addTearDown(container.dispose);
      final router = _router(vehicleId: _kOtherVehicleId);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(container, router));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // Provider must NOT be set to the absent id.
      expect(container.read(selectedHealthVehicleIdProvider), isNull);
      // Detail panel collapsed.
      expect(find.text('Integridade do Sinal'), findsNothing);
      // Snackbar visible with no id in message (Anti-Oracle).
      expect(
        find.text('Este registro não está mais disponível no monitor.'),
        findsOneWidget,
      );
      expect(find.textContaining(_kOtherVehicleId), findsNothing);
    });

    testWidgets('close button clears selected vehicle from provider', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = _container();
      // Pre-select via provider directly (simulates clicking a card).
      container
          .read(selectedHealthVehicleIdProvider.notifier)
          .set(_kOrgVehicleId);
      addTearDown(container.dispose);

      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(container, router));
      await tester.pumpAndSettle();

      expect(find.text('Integridade do Sinal'), findsOneWidget);

      // Tap the close (×) button in the detail panel.
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pump();

      expect(container.read(selectedHealthVehicleIdProvider), isNull);
      expect(find.text('Integridade do Sinal'), findsNothing);
    });

    testWidgets('dispose clears selectedHealthVehicleIdProvider', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = _container();
      container
          .read(selectedHealthVehicleIdProvider.notifier)
          .set(_kOrgVehicleId);
      addTearDown(container.dispose);

      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(container, router));
      await tester.pumpAndSettle();
      expect(container.read(selectedHealthVehicleIdProvider), _kOrgVehicleId);

      // Replace with unrelated widget → screen disposes.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: Text('gone'))),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(selectedHealthVehicleIdProvider), isNull);
    });

    testWidgets('back button in drill-down mode reopens the alerts drawer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = _container();
      addTearDown(container.dispose);
      final router = _router(vehicleId: _kOrgVehicleId);
      addTearDown(router.dispose);

      await tester.pumpWidget(_host(container, router));
      await tester.pumpAndSettle();

      // Back arrow is the first icon in the header.
      await tester.tap(find.byTooltip('Voltar'));
      // Let navigation + post-frame callback fire.
      await tester.pump();
      await tester.pump();

      expect(container.read(isAlertsDrawerOpenProvider), isTrue);
    });
  });
}
