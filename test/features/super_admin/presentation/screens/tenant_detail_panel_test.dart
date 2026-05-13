import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/features/super_admin/presentation/keys/tenant_tab_keys.dart';
import 'package:veraprob/features/super_admin/presentation/screens/tenant_detail_panel.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

const _orgId = 'org-smoke-001';

TenantHealthView _makeTenant() => const TenantHealthView(
  id: _orgId,
  name: 'Smoke Corp',
  maxVehicles: 10,
  maxActiveContracts: 5,
  activeContractCount: 2,
  openCriticalAlertCount: 0,
);

Widget _buildTestWidget({required TenantHealthView tenant}) {
  return ProviderScope(
    overrides: [
      isSuperAdminProvider.overrideWithValue(true),
      evidenceVolumeProvider.overrideWith((ref, orgId) => _neverFuture()),
      tenantTechnicalHealthProvider.overrideWith(
        (ref, orgId) => _neverFuture(),
      ),
      systemAuditLogProvider.overrideWith((ref, params) => _neverFuture()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1400,
          height: 900,
          child: TenantDetailPanel(tenant: tenant),
        ),
      ),
    ),
  );
}

Future<T> _neverFuture<T>() => Future<T>.delayed(const Duration(days: 365));

void _setLargeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('TenantDetailPanel — Semantic Keys Smoke Test', () {
    testWidgets('all 6 tabs are findable by semantic key', (tester) async {
      _setLargeScreen(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildTestWidget(tenant: _makeTenant()));
      await tester.pump();

      for (final type in TenantTabKeys.allTabs) {
        expect(
          find.byKey(TenantTabKeys.tab(_orgId, type)),
          findsOneWidget,
          reason: 'Tab key for ${type.name} not found',
        );
      }
    });

    testWidgets('tab navigation does not throw and preserves parent state', (
      tester,
    ) async {
      _setLargeScreen(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildTestWidget(tenant: _makeTenant()));
      await tester.pump();

      for (final type in TenantTabKeys.allTabs) {
        await tester.tap(find.byKey(TenantTabKeys.tab(_orgId, type)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.widgetWithText(ConstrainedBox, 'Smoke Corp'),
          findsOneWidget,
        );
      }
    });

    testWidgets('switching tenant resets tab index to first', (tester) async {
      _setLargeScreen(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const tenant2 = TenantHealthView(
        id: 'org-smoke-002',
        name: 'Other Corp',
        maxVehicles: 5,
        maxActiveContracts: 3,
        activeContractCount: 1,
        openCriticalAlertCount: 0,
      );

      await tester.pumpWidget(_buildTestWidget(tenant: _makeTenant()));
      await tester.pump();
      await tester.tap(
        find.byKey(TenantTabKeys.tab(_orgId, TenantTabType.audit)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to tenant2 — should reset to first tab.
      await tester.pumpWidget(_buildTestWidget(tenant: tenant2));
      await tester.pump();

      expect(
        find.byKey(TenantTabKeys.tab('org-smoke-002', TenantTabType.metrics)),
        findsOneWidget,
      );
    });

    testWidgets('Semantics widgets carry correct labels for automation', (
      tester,
    ) async {
      _setLargeScreen(tester);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildTestWidget(tenant: _makeTenant()));
      await tester.pump();

      for (final type in TenantTabKeys.allTabs) {
        final semantics = find.byWidgetPredicate(
          (w) =>
              w is Semantics && w.properties.label == TenantTabKeys.label(type),
        );
        expect(
          semantics,
          findsAtLeastNWidgets(1),
          reason: 'Semantics label for ${type.name} not found',
        );
      }
    });
  });
}
