import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/super_admin/application/tenant_health_view.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

// ─── Test Helpers ───────────────────────────────────────────────────────────

/// Creates a [TenantHealthView] with sensible defaults for testing.
TenantHealthView _makeTenant({
  String id = 'test-org-id',
  String name = 'Test Org',
  OrgStatus status = OrgStatus.active,
  int? toolCostCents = 10000,
  int? billingDay,
  int maxVehicles = 10,
}) {
  return TenantHealthView(
    id: id,
    name: name,
    status: status,
    maxVehicles: maxVehicles,
    maxActiveContracts: 5,
    activeContractCount: 2,
    openCriticalAlertCount: 0,
    toolCostCents: toolCostCents,
    billingDay: billingDay,
  );
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // C₄ — cache invalidation after archive/unarchive (deterministic)
  // **Validates: Requirements 1.4**
  //
  // Bug condition: tenantDetailProvider doesn't exist in super_admin_providers.
  // Expected behavior (after fix): tenantDetailProvider(orgId) exists and is
  // invalidated after archive/unarchive.
  //
  // On UNFIXED code: test FAILS because tenantDetailProvider is not defined.
  // This file is intentionally separate from C₁–C₃ tests so that compile
  // errors here don't block the other bug condition tests.
  // ═══════════════════════════════════════════════════════════════════════════

  group('C₄ — cache invalidation after archive/unarchive', () {
    test('tenantDetailProvider should exist in super_admin_providers', () {
      // On UNFIXED code: tenantDetailProvider is not defined, so this
      // test will fail at compile time or with a runtime error.
      //
      // We verify the provider exists by checking it can be accessed
      // from the providers file. If it doesn't exist, the import fails.
      //
      // After fix: tenantDetailProvider is a FutureProvider.family<TenantHealthView?, String>
      final container = ProviderContainer(
        overrides: [
          tenantHealthSnapshotProvider.overrideWith(
            (ref) async => <TenantHealthView>[
              _makeTenant(id: 'org-1', name: 'Org 1'),
              _makeTenant(id: 'org-2', name: 'Org 2'),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      // This line will fail to compile on unfixed code because
      // tenantDetailProvider doesn't exist yet.
      // After fix: it should resolve the tenant by ID.
      expect(
        () => container.read(tenantDetailProvider('org-1')),
        returnsNormally,
        reason:
            'C₄ counterexample: tenantDetailProvider does not exist — '
            'no per-tenant cache invalidation is possible',
      );
    });

    test('tenantsListProvider alias should exist in super_admin_providers', () {
      // On UNFIXED code: tenantsListProvider is not defined.
      // After fix: it's a semantic alias for tenantHealthSnapshotProvider.
      final container = ProviderContainer(
        overrides: [
          tenantHealthSnapshotProvider.overrideWith(
            (ref) async => <TenantHealthView>[],
          ),
        ],
      );
      addTearDown(container.dispose);

      // This line will fail to compile on unfixed code because
      // tenantsListProvider doesn't exist yet.
      expect(
        () => container.read(tenantsListProvider),
        returnsNormally,
        reason:
            'C₄ counterexample: tenantsListProvider alias does not exist — '
            'consumers must use tenantHealthSnapshotProvider directly',
      );
    });
  });
}
