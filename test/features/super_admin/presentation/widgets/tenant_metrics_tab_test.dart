import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:veraprob/application/super_admin/evidence_volume_view.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/evidence_volume_card.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/org_health_card.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_metrics_tab.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

// ─── Fixtures ───────────────────────────────────────────────────────────────

TenantHealthView _makeTenant({
  DateTime? lastTelemetryAt,
  int openCriticalAlertCount = 0,
}) {
  return TenantHealthView(
    id: 'org-001',
    name: 'Acme',
    maxVehicles: 10,
    maxActiveContracts: 5,
    activeContractCount: 2,
    lastTelemetryAt: lastTelemetryAt,
    openCriticalAlertCount: openCriticalAlertCount,
  );
}

// ─── Helpers ────────────────────────────────────────────────────────────────

Widget _buildTestWidget({
  required TenantHealthView tenant,
  AsyncValue<EvidenceVolumeView>? evidenceState,
}) {
  final state =
      evidenceState ??
      const AsyncData(
        EvidenceVolumeView(totalHistorical: 100, totalMonthly: 5),
      );

  return ProviderScope(
    overrides: [
      evidenceVolumeProvider.overrideWith((ref, orgId) {
        return switch (state) {
          AsyncData(:final value) => Future.value(value),
          AsyncError(:final error, :final stackTrace) =>
            Future<EvidenceVolumeView>.error(error, stackTrace),
          _ => Future<EvidenceVolumeView>.delayed(
            const Duration(days: 1),
            () => const EvidenceVolumeView(totalHistorical: 0, totalMonthly: 0),
          ),
        };
      }),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 800,
          child: TenantMetricsTab(tenant: tenant),
        ),
      ),
    ),
  );
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // "Nunca" text when lastTelemetryAt is null
  // ═══════════════════════════════════════════════════════════════════════════

  group('Última Telemetria card', () {
    testWidgets('shows "Nunca" when lastTelemetryAt is null', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(tenant: _makeTenant(lastTelemetryAt: null)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nunca'), findsOneWidget);
      expect(find.text('Última Telemetria'), findsOneWidget);
    });

    testWidgets('shows formatted date when lastTelemetryAt is set', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWidget(
          tenant: _makeTenant(
            lastTelemetryAt: DateTime.utc(2025, 3, 15, 14, 30),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should NOT show "Nunca"
      expect(find.text('Nunca'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Critical alerts card color
  // ═══════════════════════════════════════════════════════════════════════════

  group('Alertas Críticos card', () {
    testWidgets('value is red (VeraProbColors.error) when alerts > 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWidget(tenant: _makeTenant(openCriticalAlertCount: 3)),
      );
      await tester.pumpAndSettle();

      // Find OrgHealthCard with title 'Alertas Críticos'
      final cardFinder = find.byWidgetPredicate(
        (w) => w is OrgHealthCard && w.title == 'Alertas Críticos',
      );
      expect(cardFinder, findsOneWidget);

      final card = tester.widget<OrgHealthCard>(cardFinder);
      expect(card.valueColor, equals(VeraProbColors.error));
    });

    testWidgets('value is green (success) when alerts == 0', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(tenant: _makeTenant(openCriticalAlertCount: 0)),
      );
      await tester.pumpAndSettle();

      final cardFinder = find.byWidgetPredicate(
        (w) => w is OrgHealthCard && w.title == 'Alertas Críticos',
      );
      final card = tester.widget<OrgHealthCard>(cardFinder);
      expect(card.valueColor, equals(VeraProbColors.success));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AsyncError state for evidence volume card
  // ═══════════════════════════════════════════════════════════════════════════

  group('Evidence Volume AsyncError', () {
    testWidgets('renders _EvidenceVolumeErrorCard on AsyncError', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWidget(
          tenant: _makeTenant(),
          evidenceState: AsyncError(Exception('timeout'), StackTrace.current),
        ),
      );
      await tester.pumpAndSettle();

      // Error card shows error icon and message
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Erro ao carregar dados'), findsOneWidget);

      // EvidenceVolumeCard should NOT be present
      expect(find.byType(EvidenceVolumeCard), findsNothing);
    });

    testWidgets('renders EvidenceVolumeCard on AsyncData', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          tenant: _makeTenant(),
          evidenceState: const AsyncData(
            EvidenceVolumeView(totalHistorical: 500, totalMonthly: 20),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EvidenceVolumeCard), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });
}
