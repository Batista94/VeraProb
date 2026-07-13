// Goldens for TenantListPanel — generate EXCLUSIVAMENTE via `make goldens`.

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
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';
import 'package:veraprob/features/super_admin/presentation/screens/tenant_list_panel.dart';
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
  bool isLoading = false,
}) {
  if (isLoading) {
    final completer = Completer<List<TenantHealthSnapshot>>();
    when(
      () => _mockRepo.getAllTenantHealth(),
    ).thenAnswer((_) => completer.future);
    addTearDown(() {
      if (!completer.isCompleted) completer.complete([]);
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
      tenantSearchDebounceDurationProvider.overrideWithValue(Duration.zero),
      if (isLoading)
        tenantHealthSnapshotProvider.overrideWith(
          (ref) => Completer<List<TenantHealthView>>().future,
        ),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: TenantListPanel(selectedOrgId: null, onOrgSelected: (_) {}),
      ),
    ),
  );
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
      cnpj: cnpj,
    );
  }
}

void main() {
  setUp(() {
    _mockRepo = MockSuperAdminRepository();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('TenantListPanel - Visual Regression (Goldens)', () {
    goldenTest(
      'Golden Test: Default List State',
      fileName: 'tenant_list_panel_default',
      builder: () =>
          SizedBox(width: 320, height: 600, child: _createTestWidget()),
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'Golden Test: Search Results State',
      fileName: 'tenant_list_panel_searching',
      builder: () =>
          SizedBox(width: 320, height: 600, child: _createTestWidget()),
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
        child: _createTestWidget(tenants: []),
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
          child: _createTestWidget(isLoading: true),
        );
      },
      pumpBeforeTest: (tester) async {
        await tester.pump();
      },
    );
  });
}
