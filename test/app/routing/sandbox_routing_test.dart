import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/app/routing/sandbox_route_redirect.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/sla_audit/projections/contract_detail_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_summary_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_summary.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/features/admin/presentation/screens/sla_sandbox_screen.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/presentation/sandbox/providers/sandbox_wizard_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/sandbox_providers.dart';

const _validContractId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

void main() {
  group('sandboxRouteRedirect — UUID integrity', () {
    test('missing contractId segment redirects to contracts list', () {
      expect(
        sandboxRouteRedirect('/admin/hub/contracts/sandbox'),
        AdminNavRoute(AdminNav.contracts).path,
      );
    });

    test('malformed UUID redirects to contracts list', () {
      expect(
        sandboxRouteRedirect('/admin/hub/contracts/not-a-uuid/sandbox'),
        AdminNavRoute(AdminNav.contracts).path,
      );
    });

    test('valid UUID sandbox path proceeds (null redirect)', () {
      expect(
        sandboxRouteRedirect('/admin/hub/contracts/$_validContractId/sandbox'),
        isNull,
      );
    });

    test('non-sandbox path is ignored (null)', () {
      expect(
        sandboxRouteRedirect('/admin/hub/contracts/$_validContractId/rules'),
        isNull,
      );
    });
  });

  group('SlaSandboxScreen — session isolation (A/B Delta leakage guard)', () {
    testWidgets('mounting sandbox screen resets wizard + controller state', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWithValue(UserRole.admin),
          permissionServiceProvider.overrideWithValue(
            const PermissionService(permissions: {'*'}, scopes: {}),
          ),
          currentOrganizationIdProvider.overrideWithValue('org-1'),
          contractDetailProvider.overrideWith2(
            (_) => _StaticDetailNotifier(_detail(_validContractId)),
          ),
          sandboxSimulationControllerProvider.overrideWith(
            _DirtySimulationController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      final wizardSub = container.listen(sandboxWizardProvider, (_, _) {});
      final simSub = container.listen(
        sandboxSimulationControllerProvider,
        (_, _) {},
      );
      addTearDown(wizardSub.close);
      addTearDown(simSub.close);

      container.read(sandboxWizardProvider.notifier).setContractId('stale-id');
      container.read(sandboxWizardProvider.notifier).setSessionLabel('leaked');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SlaSandboxScreen(contractId: _validContractId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final wizard = container.read(sandboxWizardProvider);
      expect(wizard.sessionLabel, isEmpty);
      expect(wizard.contractId, isNot('stale-id'));
      expect(
        wizard.contractId == null || wizard.contractId == _validContractId,
        isTrue,
      );

      expect(
        container.read(sandboxSimulationControllerProvider),
        const AsyncData<String?>(null),
      );
    });

    testWidgets('dispose annihilates dirty wizard + controller state', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWithValue(UserRole.admin),
          currentOperatorIdProvider.overrideWithValue('user-1'),
          permissionServiceProvider.overrideWithValue(
            const PermissionService(permissions: {'*'}, scopes: {}),
          ),
          currentOrganizationIdProvider.overrideWithValue('org-1'),
          contractDetailProvider.overrideWith2(
            (_) => _StaticDetailNotifier(_detail(_validContractId)),
          ),
          sandboxSimulationControllerProvider.overrideWith(
            _DirtySimulationController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      final wizardSub = container.listen(sandboxWizardProvider, (_, _) {});
      final simSub = container.listen(
        sandboxSimulationControllerProvider,
        (_, _) {},
      );
      addTearDown(wizardSub.close);
      addTearDown(simSub.close);

      container.read(sandboxWizardProvider.notifier).setContractId('stale-id');
      container.read(sandboxWizardProvider.notifier).setSessionLabel('leaked');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SlaSandboxScreen(contractId: _validContractId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(container.read(sandboxWizardProvider), const SandboxWizardState());
      expect(
        container.read(sandboxSimulationControllerProvider),
        const AsyncData<String?>(null),
      );
    });
  });
}

class _DirtySimulationController extends SandboxSimulationController {
  @override
  AsyncValue<String?> build() => const AsyncData('old-session');
}

final _utc = DateTime.utc(2026, 3, 10, 12, 0);

class _StaticDetailNotifier extends ContractDetailNotifier {
  _StaticDetailNotifier(this._detail) : super('test-contract-id');
  final ContractDetailView? _detail;

  @override
  Future<ContractDetailView?> build() async => _detail;
}

ContractDetailView _detail(String id) => ContractDetailView(
  summary: ContractSummaryView(
    id: id,
    name: 'Contrato Sandbox',
    contractorName: 'Carrier X',
    status: ContractStatusView.active,
    validFromUtc: _utc,
    validUntilUtc: _utc.add(const Duration(days: 365)),
    createdAtUtc: _utc,
    activatedAtUtc: _utc,
    planCount: 1,
    activePlanVersion: 1,
    totalSetsInProgress: 0,
    slaHealthBps: 9000,
    previousHash: null,
    currentHash: 'hash',
  ),
  recentExecutions: [
    SlaExecutionItemView(
      setId: 'set-1',
      contractId: id,
      status: ExecutionStatus.completed,
      windowStartUtc: _utc,
      windowEndUtc: _utc.add(const Duration(hours: 1)),
      plannedVehicleId: 'VEH-001',
      startLatitude: -23.5,
      startLongitude: -46.6,
      startRadiusMeters: 100,
      contractualValue: 50000,
      noShowPenaltyBps: 10000,
    ),
  ],
  financialSummary: SlaExecutionSummary(
    contractId: id,
    totalPlanned: 1,
    totalCompleted: 1,
    totalFailed: 0,
    totalCompletedWithGaps: 0,
    generatedAtUtc: _utc,
    protectedRevenue: 50000,
    revenueAtRisk: 0,
    lostRevenue: 0,
  ),
);
