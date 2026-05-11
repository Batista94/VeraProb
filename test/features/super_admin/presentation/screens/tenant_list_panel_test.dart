import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/features/super_admin/presentation/screens/tenant_list_panel.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

class MockTenantHealthView extends Mock implements TenantHealthView {}

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

void main() {
  late MockSuperAdminRepository mockRepo;

  setUp(() {
    mockRepo = MockSuperAdminRepository();
  });
  final mockTenants = [
    const TenantHealthView(
      id: 'org-1',
      name: 'Omni Consórcio',
      legalName: 'Omni Consórcio Ltda',
      planType: 'Enterprise',
      status: OrgStatus.active,
      maxVehicles: 100,
      maxActiveContracts: 50,
      activeContractCount: 10,
      openCriticalAlertCount: 0,
      cnpj: '11.444.777/0001-61',
    ),
    const TenantHealthView(
      id: 'org-2',
      name: 'Hydra Corp',
      legalName: 'Hydra Logistica',
      planType: 'Basic',
      status: OrgStatus.suspended,
      maxVehicles: 20,
      maxActiveContracts: 5,
      activeContractCount: 5,
      openCriticalAlertCount: 2,
      cnpj: '22.333.444/0001-22',
    ),
    const TenantHealthView(
      id: 'org-3',
      name: 'Alpha Trans',
      legalName: 'Alpha Transportes',
      planType: 'Enterprise',
      status: OrgStatus.active,
      maxVehicles: 200,
      maxActiveContracts: 100,
      activeContractCount: 80,
      openCriticalAlertCount: 0,
      cnpj: '33.222.111/0001-33',
    ),
  ];

  Widget createTestWidget({
    List<TenantHealthView>? tenants,
    Object? error,
    String? selectedOrgId,
    required ValueChanged<TenantHealthView> onOrgSelected,
  }) {
    if (error != null) {
      when(() => mockRepo.getAllTenantHealth()).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 50));
        throw error;
      });
    } else {
      when(() => mockRepo.getAllTenantHealth()).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return (tenants ?? mockTenants)
            .map((t) => t.toSnapshot()) // Helper needed
            .toList();
      });
    }

    return ProviderScope(
      overrides: [superAdminRepositoryProvider.overrideWithValue(mockRepo)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: TenantListPanel(
            selectedOrgId: selectedOrgId,
            onOrgSelected: onOrgSelected,
          ),
        ),
      ),
    );
  }

  group('TenantListPanel - Happy Path', () {
    testWidgets('Renders tenant list correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      expect(find.text('Omni Consórcio'), findsOneWidget);
      expect(find.text('Hydra Corp'), findsOneWidget);
      expect(find.text('Alpha Trans'), findsOneWidget);
      expect(find.text('ENTERPRISE'), findsAtLeast(2));
      expect(find.text('BASIC'), findsOneWidget);
    });

    testWidgets('Selects a tenant and calls onOrgSelected', (tester) async {
      TenantHealthView? selected;
      await tester.pumpWidget(
        createTestWidget(onOrgSelected: (t) => selected = t),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hydra Corp'));
      await tester.pumpAndSettle();

      expect(selected?.id, equals('org-2'));
    });

    testWidgets('Filters list by search query (Name)', (tester) async {
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pumpAndSettle();

      expect(find.text('Alpha Trans'), findsOneWidget);
      expect(find.text('Omni Consórcio'), findsNothing);
      expect(find.text('Hydra Corp'), findsNothing);
    });

    testWidgets('Filters list by search query (i18n / Accents)', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      // Search with accent for item with accent
      await tester.enterText(find.byType(TextField), 'Consórcio');
      await tester.pumpAndSettle();
      expect(find.text('Omni Consórcio'), findsOneWidget);

      // Search WITHOUT accent for item WITH accent
      await tester.enterText(find.byType(TextField), 'consorcio');
      await tester.pumpAndSettle();
      expect(find.text('Omni Consórcio'), findsOneWidget);
    });

    testWidgets('Status filtering: Active vs Suspended', (tester) async {
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      // Tap "Ativos" chip
      await tester.tap(find.text('Ativos'));
      await tester.pumpAndSettle();

      expect(find.text('Omni Consórcio'), findsOneWidget);
      expect(find.text('Alpha Trans'), findsOneWidget);
      expect(find.text('Hydra Corp'), findsNothing);

      // Tap "Suspensos" chip
      await tester.tap(find.text('Suspensos'));
      await tester.pumpAndSettle();

      expect(find.text('Hydra Corp'), findsOneWidget);
      expect(find.text('Omni Consórcio'), findsNothing);
      expect(find.text('Alpha Trans'), findsNothing);
    });

    testWidgets('Clearing search resets the list', (tester) async {
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pumpAndSettle();
      expect(find.text('Omni Consórcio'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.text('Omni Consórcio'), findsOneWidget);
      expect(find.text('Alpha Trans'), findsOneWidget);
    });

    testWidgets('Shows loading state', (tester) async {
      final completer = Completer<List<TenantHealthSnapshot>>();
      when(
        () => mockRepo.getAllTenantHealth(),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Cleanup: complete to avoid pending timers
      completer.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets('Shows error state', (tester) async {
      await tester.pumpWidget(
        createTestWidget(onOrgSelected: (_) {}, error: 'API Error'),
      );
      await tester.pump(); // Start loading
      await tester.pump(const Duration(milliseconds: 100)); // Finish with error
      await tester.pumpAndSettle();

      expect(find.textContaining('API Error'), findsOneWidget);
    });
  });

  group('TenantListPanel - Enterprise & Security Scenarios', () {
    testWidgets('Golden Test: Panel width is exactly 320px', (tester) async {
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      final panel = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(panel.width, equals(320));
    });

    testWidgets('Forensic Visibility: Critical alerts show warning icon', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      // Hydra Corp has 2 critical alerts
      final hydraTile = find.ancestor(
        of: find.text('Hydra Corp'),
        matching: find.byType(ListTile),
      );

      expect(
        find.descendant(
          of: hydraTile,
          matching: find.byIcon(Icons.warning_amber),
        ),
        findsOneWidget,
      );

      // Omni has 0
      final omniTile = find.ancestor(
        of: find.text('Omni Consórcio'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: omniTile,
          matching: find.byIcon(Icons.warning_amber),
        ),
        findsNothing,
      );
    });

    testWidgets('Security: Search injection resilience (DoS/Injection)', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      // Attempt injection-like query
      await tester.enterText(
        find.byType(TextField),
        "'; DROP TABLE organizations; --",
      );
      await tester.pumpAndSettle();

      // Should just show empty result, not crash
      expect(find.text('Nenhuma organização encontrada.'), findsOneWidget);

      // Attempt massive string
      await tester.enterText(find.byType(TextField), 'A' * 5000);
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma organização encontrada.'), findsOneWidget);
    });

    testWidgets('Accessibility: Semantics audit', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      // Verify search field has correct hint
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText == 'Buscar por nome, CNPJ, ID...',
        ),
        findsOneWidget,
      );

      // Verify chips have correct labels
      expect(find.bySemanticsLabel('Todos'), findsOneWidget);
      expect(find.bySemanticsLabel('Ativos'), findsOneWidget);
      expect(find.bySemanticsLabel('Suspensos'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('Stress Test: Rendering 50 items', (tester) async {
      final largeList = List.generate(
        50,
        (i) => TenantHealthView(
          id: 'org-$i',
          name: 'Tenant $i',
          maxVehicles: 10,
          maxActiveContracts: 5,
          activeContractCount: 1,
          openCriticalAlertCount: 0,
          status: OrgStatus.active,
        ),
      );

      await tester.pumpWidget(
        createTestWidget(onOrgSelected: (_) {}, tenants: largeList),
      );
      await tester.pumpAndSettle();

      // Verify first visible item
      expect(find.text('Tenant 0'), findsOneWidget);

      // Manual scroll to bottom to avoid finder evaluation issues in cache extent
      bool found = false;
      for (int i = 0; i < 20; i++) {
        if (find.text('Tenant 49').evaluate().isNotEmpty) {
          found = true;
          break;
        }
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pump();
      }
      expect(found, isTrue);
      expect(find.text('Tenant 49'), findsWidgets);
    });
  });

  group('TenantListPanel - Enterprise Tier 1: CIA / Adversarial / A11y', () {
    testWidgets(
      'CIA (Integrity): Race condition — rapid search resolves to last query',
      (tester) async {
        await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
        await tester.pumpAndSettle();

        // Type "Alpha" then immediately overwrite with "Hydra"
        await tester.enterText(find.byType(TextField), 'Alpha');
        await tester.pump(); // single frame — no settle
        await tester.enterText(find.byType(TextField), 'Hydra');
        await tester.pumpAndSettle();

        // Final state MUST reflect last query only
        expect(find.text('Hydra Corp'), findsOneWidget);
        expect(find.text('Alpha Trans'), findsNothing);
        expect(find.text('Omni Consórcio'), findsNothing);
      },
    );

    testWidgets(
      'Adversarial (Availability): Retry after timeout preserves filter state',
      (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            onOrgSelected: (_) {},
            error: TimeoutException('Network timeout'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Error state visible with retry button
        expect(find.text('Tentar novamente'), findsOneWidget);

        // Set filter to "Suspensos" BEFORE retry
        await tester.tap(find.text('Suspensos'));
        await tester.pumpAndSettle();

        // Enter search text BEFORE retry
        await tester.enterText(find.byType(TextField), 'Hydra');
        await tester.pumpAndSettle();

        // Now reconfigure mock to succeed on next call
        when(() => mockRepo.getAllTenantHealth()).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return mockTenants.map((t) => t.toSnapshot()).toList();
        });

        // Tap retry
        await tester.tap(find.text('Tentar novamente'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Filter state preserved: only suspended + matching "Hydra"
        expect(find.text('Hydra Corp'), findsOneWidget);
        expect(find.text('Omni Consórcio'), findsNothing);
        expect(find.text('Alpha Trans'), findsNothing);
      },
    );

    testWidgets('A11y (Semantics): Screen reader announces tenant status', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      // Active tenant announces "Ativo"
      expect(
        find.bySemanticsLabel(RegExp(r'Omni Consórcio, Ativo')),
        findsOneWidget,
      );

      // Suspended tenant announces "Suspenso"
      expect(
        find.bySemanticsLabel(RegExp(r'Hydra Corp, Suspenso')),
        findsOneWidget,
      );

      handle.dispose();
    });
  });

  group('TenantListPanel - Visual Regression (Goldens)', () {
    testWidgets('Golden Test: Default List State', (tester) async {
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(TenantListPanel),
        matchesGoldenFile('goldens/tenant_list_panel_default.png'),
      );
    });

    testWidgets('Golden Test: Search Results State', (tester) async {
      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(TenantListPanel),
        matchesGoldenFile('goldens/tenant_list_panel_searching.png'),
      );
    });

    testWidgets('Golden Test: Empty State', (tester) async {
      await tester.pumpWidget(
        createTestWidget(onOrgSelected: (_) {}, tenants: []),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(TenantListPanel),
        matchesGoldenFile('goldens/tenant_list_panel_empty.png'),
      );
    });

    testWidgets('Golden Test: Loading State', (tester) async {
      final completer = Completer<List<TenantHealthSnapshot>>();
      when(
        () => mockRepo.getAllTenantHealth(),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(createTestWidget(onOrgSelected: (_) {}));
      await tester.pump(); // Render initial loading

      await expectLater(
        find.byType(TenantListPanel),
        matchesGoldenFile('goldens/tenant_list_panel_loading.png'),
      );

      completer.complete([]);
      await tester.pumpAndSettle();
    });
  });
}

extension on TenantHealthView {
  TenantHealthSnapshot toSnapshot() {
    return TenantHealthSnapshot(
      id: id,
      name: name,
      legalName: legalName,
      planType: planType,
      status: status ?? OrgStatus.active,
      isActive: isActive,
      maxVehicles: maxVehicles,
      maxActiveContracts: maxActiveContracts,
      activeContractCount: activeContractCount,
      lastTelemetryAt: lastTelemetryAt,
      openCriticalAlertCount: openCriticalAlertCount,
      capabilities: {}, // Simplify for test
      dwellTimeSeconds: dwellTimeSeconds,
      updatedAt: updatedAt,
      cnpj: cnpj,
      createdAt: createdAt,
    );
  }
}
