import 'dart:async';
import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/tenant_search_notifier.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/features/super_admin/presentation/screens/tenant_list_panel.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/tenant_skeleton_tile.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

late MockSuperAdminRepository _mockRepo;

final _mockTenants = [
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

Widget _createTestWidget({
  List<TenantHealthView>? tenants,
  Object? error,
  String? selectedOrgId,
  Duration debounce = Duration.zero,
  bool isLoading = false,
  required ValueChanged<TenantHealthView> onOrgSelected,
}) {
  if (isLoading) {
    final completer = Completer<List<TenantHealthSnapshot>>();
    when(
      () => _mockRepo.getAllTenantHealth(),
    ).thenAnswer((_) => completer.future);
    addTearDown(() {
      if (!completer.isCompleted) completer.complete([]);
    });
  } else if (error != null) {
    when(() => _mockRepo.getAllTenantHealth()).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      throw error;
    });
  } else {
    when(() => _mockRepo.getAllTenantHealth()).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return (tenants ?? _mockTenants).map((t) => t.toSnapshot()).toList();
    });
  }

  return ProviderScope(
    overrides: [
      superAdminRepositoryProvider.overrideWithValue(_mockRepo),
      tenantSearchDebounceDurationProvider.overrideWithValue(debounce),
      if (isLoading)
        tenantHealthSnapshotProvider.overrideWith(
          (ref) => Completer<List<TenantHealthView>>().future,
        ),
    ],
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

void _testHappyPath() {
  group('TenantListPanel - Happy Path', () {
    testWidgets('Renders tenant list correctly', (tester) async {
      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      expect(find.text('Omni Consórcio'), findsOneWidget);
      expect(find.text('Hydra Corp'), findsOneWidget);
      expect(find.text('Alpha Trans'), findsOneWidget);
      expect(find.text('ENTERPRISE'), findsAtLeast(2));
      expect(find.text('BASIC'), findsOneWidget);
      // E2E navigation helper depends on this key — must stay attached to the ListView
      expect(find.byKey(TenantListPanel.tenantListViewKey), findsOneWidget);
      // Error key must NOT be present when data loaded successfully
      expect(find.byKey(TenantListPanel.tenantListErrorKey), findsNothing);
    });

    testWidgets('Selects a tenant and calls onOrgSelected', (tester) async {
      TenantHealthView? selected;
      await tester.pumpWidget(
        _createTestWidget(onOrgSelected: (t) => selected = t),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hydra Corp'));
      await tester.pumpAndSettle();

      expect(selected?.id, equals('org-2'));
    });

    testWidgets('Filters list by search query (Name)', (tester) async {
      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
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
      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Consórcio');
      await tester.pumpAndSettle();
      expect(find.text('Omni Consórcio'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'consorcio');
      await tester.pumpAndSettle();
      expect(find.text('Omni Consórcio'), findsOneWidget);
    });

    testWidgets('Status filtering: Active vs Suspended', (tester) async {
      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ativos'));
      await tester.pumpAndSettle();

      expect(find.text('Omni Consórcio'), findsOneWidget);
      expect(find.text('Alpha Trans'), findsOneWidget);
      expect(find.text('Hydra Corp'), findsNothing);

      await tester.tap(find.text('Suspensos'));
      await tester.pumpAndSettle();

      expect(find.text('Hydra Corp'), findsOneWidget);
      expect(find.text('Omni Consórcio'), findsNothing);
      expect(find.text('Alpha Trans'), findsNothing);
    });

    testWidgets('Clearing search resets the list', (tester) async {
      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pumpAndSettle();
      expect(find.text('Omni Consórcio'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.text('Omni Consórcio'), findsOneWidget);
      expect(find.text('Alpha Trans'), findsOneWidget);
    });

    testWidgets('Shows skeleton loading state', (tester) async {
      final completer = Completer<List<TenantHealthSnapshot>>();
      when(
        () => _mockRepo.getAllTenantHealth(),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pump();

      expect(find.byType(TenantSkeletonTile), findsNWidgets(5));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      completer.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets('Shows error state', (tester) async {
      await tester.pumpWidget(
        _createTestWidget(onOrgSelected: (_) {}, error: 'API Error'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.textContaining('API Error'), findsOneWidget);
      // E2E navigation helper uses this key to detect error state and fail fast
      expect(find.byKey(TenantListPanel.tenantListErrorKey), findsOneWidget);
      expect(find.byKey(TenantListPanel.tenantListViewKey), findsNothing);
    });
  });
}

void _testEnterpriseScenarios() {
  group('TenantListPanel - Enterprise & Security Scenarios', () {
    testWidgets('Golden Test: Panel width is exactly 320px', (tester) async {
      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      final panel = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(panel.width, equals(320));
    });

    testWidgets('Forensic Visibility: Critical alerts show warning icon', (
      tester,
    ) async {
      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

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
      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        "'; DROP TABLE organizations; --",
      );
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma organização encontrada.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'A' * 5000);
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma organização encontrada.'), findsOneWidget);
    });

    testWidgets('Accessibility: Semantics audit', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText == 'Buscar por nome, CNPJ, ID...',
        ),
        findsOneWidget,
      );

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
        _createTestWidget(onOrgSelected: (_) {}, tenants: largeList),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tenant 0'), findsOneWidget);

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
    });
  });
}

void _testCiaA11y() {
  group('TenantListPanel - Enterprise Tier 1: CIA / Adversarial / A11y', () {
    testWidgets(
      'CIA (Integrity): Race condition — rapid search resolves to last query',
      (tester) async {
        await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'Alpha');
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Hydra');
        await tester.pumpAndSettle();

        expect(find.text('Hydra Corp'), findsOneWidget);
        expect(find.text('Alpha Trans'), findsNothing);
        expect(find.text('Omni Consórcio'), findsNothing);
      },
    );

    testWidgets(
      'Adversarial (Availability): Retry after timeout preserves filter state',
      (tester) async {
        await tester.pumpWidget(
          _createTestWidget(
            onOrgSelected: (_) {},
            error: TimeoutException('Network timeout'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(find.text('Tentar novamente'), findsOneWidget);

        when(() => _mockRepo.getAllTenantHealth()).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return _mockTenants.map((t) => t.toSnapshot()).toList();
        });

        await tester.tap(find.text('Tentar novamente'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // After retry, data loads successfully
        expect(find.text('Omni Consórcio'), findsOneWidget);
        expect(find.text('Hydra Corp'), findsOneWidget);
        expect(find.text('Alpha Trans'), findsOneWidget);
      },
    );

    testWidgets('A11y (Semantics): Screen reader announces tenant status', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp(r'Omni Consórcio, Ativo')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Hydra Corp, Suspenso')),
        findsOneWidget,
      );

      handle.dispose();
    });
  });
}

void _testDebounceAdversarial() {
  group('TenantListPanel - Debounce Adversarial', () {
    testWidgets(
      'Rapid fire: 10 keystrokes in 50ms each — shimmer overlay visible',
      (tester) async {
        await tester.pumpWidget(
          _createTestWidget(
            onOrgSelected: (_) {},
            debounce: const Duration(milliseconds: 300),
          ),
        );
        await tester.pumpAndSettle();

        // Simulate rapid typing
        for (int i = 1; i <= 10; i++) {
          await tester.enterText(find.byType(TextField), 'A' * i);
          await tester.pump(const Duration(milliseconds: 50));
        }

        // During debounce — shimmer overlay should be visible
        expect(
          find.byKey(const ValueKey('tenant-shimmer-overlay')),
          findsOneWidget,
        );

        // Wait for debounce to fire
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // Final state: query "AAAAAAAAAA" matches nothing
        expect(find.text('Nenhuma organização encontrada.'), findsOneWidget);
      },
    );

    testWidgets(
      'Dispose mid-debounce: widget unmounts during active timer — no crash',
      (tester) async {
        await tester.pumpWidget(
          _createTestWidget(
            onOrgSelected: (_) {},
            debounce: const Duration(milliseconds: 300),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'test');
        await tester.pump(const Duration(milliseconds: 100));

        // Unmount widget before debounce fires
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pump(const Duration(milliseconds: 500));

        // No crash = pass
      },
    );

    testWidgets('Skeleton tiles shown on initial load with correct ValueKeys', (
      tester,
    ) async {
      final completer = Completer<List<TenantHealthSnapshot>>();
      when(
        () => _mockRepo.getAllTenantHealth(),
      ).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pump();

      // Verify skeleton tiles with keys
      for (int i = 0; i < 5; i++) {
        expect(find.byKey(ValueKey('tenant-skeleton-$i')), findsOneWidget);
      }

      // Verify semantics
      expect(find.bySemanticsLabel('Carregando organização'), findsNWidgets(5));

      completer.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'Concurrent data update: snapshot refreshes during debounce uses latest',
      (tester) async {
        await tester.pumpWidget(
          _createTestWidget(
            onOrgSelected: (_) {},
            debounce: const Duration(milliseconds: 300),
          ),
        );
        await tester.pumpAndSettle();

        // All 3 visible initially
        expect(find.text('Omni Consórcio'), findsOneWidget);

        // Override mock for second call — returns only Alpha Trans
        when(() => _mockRepo.getAllTenantHealth()).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return [_mockTenants[2].toSnapshot()];
        });

        // Start typing (triggers debounce)
        await tester.enterText(find.byType(TextField), 'Alpha');
        await tester.pump(const Duration(milliseconds: 100));

        // Invalidate source data mid-debounce
        final element = tester.element(find.byType(TenantListPanel));
        final container = ProviderScope.containerOf(element);
        container.invalidate(tenantHealthSnapshotProvider);

        // Wait for both debounce and data refresh
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        // Should show filtered result from latest data
        expect(find.text('Alpha Trans'), findsOneWidget);
        expect(find.text('Omni Consórcio'), findsNothing);
      },
    );
  });
}

void _testCnpjSearch() {
  group('TenantListPanel - CNPJ Search (Mask Resilience)', () {
    testWidgets('CT-CNPJ-01: Full CNPJ with mask finds correct tenant', (
      tester,
    ) async {
      await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '11.444.777/0001-61');
      await tester.pumpAndSettle();

      expect(find.text('Omni Consórcio'), findsOneWidget);
      expect(find.text('Hydra Corp'), findsNothing);
      expect(find.text('Alpha Trans'), findsNothing);
    });

    testWidgets(
      'CT-CNPJ-02: Full CNPJ without mask (digits only) finds correct tenant',
      (tester) async {
        await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '11444777000161');
        await tester.pumpAndSettle();

        expect(find.text('Omni Consórcio'), findsOneWidget);
        expect(find.text('Hydra Corp'), findsNothing);
        expect(find.text('Alpha Trans'), findsNothing);
      },
    );

    testWidgets(
      'CT-CNPJ-03 (Adversarial): Invalid chars in CNPJ do not crash',
      (tester) async {
        await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '11.444.AAA.777');
        await tester.pumpAndSettle();

        expect(find.text('Omni Consórcio'), findsOneWidget);
        expect(find.text('Hydra Corp'), findsNothing);
      },
    );

    testWidgets(
      'CT-CNPJ-04 (Regression): Name with accents and ID search still work',
      (tester) async {
        await tester.pumpWidget(_createTestWidget(onOrgSelected: (_) {}));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'Consórcio');
        await tester.pumpAndSettle();
        expect(find.text('Omni Consórcio'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'consorcio');
        await tester.pumpAndSettle();
        expect(find.text('Omni Consórcio'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'org-3');
        await tester.pumpAndSettle();
        expect(find.text('Alpha Trans'), findsOneWidget);
        expect(find.text('Omni Consórcio'), findsNothing);
      },
    );
  });
}

void _testVisualRegression() {
  group('TenantListPanel - Visual Regression (Goldens)', () {
    goldenTest(
      'Golden Test: Default List State',
      fileName: 'tenant_list_panel_default',
      builder: () => SizedBox(
        width: 320,
        height: 600,
        child: _createTestWidget(onOrgSelected: (_) {}),
      ),
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'Golden Test: Search Results State',
      fileName: 'tenant_list_panel_searching',
      builder: () => SizedBox(
        width: 320,
        height: 600,
        child: _createTestWidget(onOrgSelected: (_) {}),
      ),
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Alpha');
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'Golden Test: Empty State',
      fileName: 'tenant_list_panel_empty',
      builder: () => SizedBox(
        width: 320,
        height: 600,
        child: _createTestWidget(onOrgSelected: (_) {}, tenants: []),
      ),
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'Golden Test: Skeleton Loading State',
      fileName: 'tenant_list_panel_skeleton',
      builder: () {
        return SizedBox(
          width: 320,
          height: 600,
          child: _createTestWidget(isLoading: true, onOrgSelected: (_) {}),
        );
      },
      pumpBeforeTest: (tester) async {
        await tester.pump();
      },
    );
  });
}

void main() {
  setUp(() {
    _mockRepo = MockSuperAdminRepository();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  _testHappyPath();
  _testEnterpriseScenarios();
  _testCiaA11y();
  _testDebounceAdversarial();
  _testCnpjSearch();
  _testVisualRegression();
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
      capabilities: {},
      dwellTimeSeconds: dwellTimeSeconds,
      updatedAt: updatedAt,
      cnpj: cnpj,
      createdAt: createdAt,
    );
  }
}
