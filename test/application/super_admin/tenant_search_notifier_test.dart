import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/tenant_search_notifier.dart';
import 'package:veraprob/application/super_admin/tenant_status_filter.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

void main() {
  late ProviderContainer container;

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

  tearDown(() => container.dispose());

  ProviderContainer createContainer({
    List<TenantHealthView>? tenants,
    Object? error,
    Duration debounce = Duration.zero,
  }) {
    return ProviderContainer(
      overrides: [
        tenantSearchDebounceDurationProvider.overrideWithValue(debounce),
        tenantHealthSnapshotProvider.overrideWith((ref) async {
          if (error != null) throw error;
          return tenants ?? mockTenants;
        }),
      ],
    );
  }

  group('TenantSearchNotifier — build & filtering', () {
    test('initial build returns all tenants when source resolves', () async {
      container = createContainer();
      // Initially loading
      expect(container.read(tenantSearchProvider).isLoading, true);
      // Wait for FutureProvider to resolve
      await container.read(tenantHealthSnapshotProvider.future);
      final state = container.read(tenantSearchProvider);
      expect(state.value?.length, 3);
    });

    test('setQuery filters by name (Duration.zero)', () async {
      container = createContainer();
      await container.read(tenantHealthSnapshotProvider.future);
      container.read(tenantSearchProvider.notifier).setQuery('Alpha');
      final state = container.read(tenantSearchProvider);
      expect(state.value?.length, 1);
      expect(state.value?.first.name, 'Alpha Trans');
    });

    test('setStatusFilter filters immediately', () async {
      container = createContainer();
      await container.read(tenantHealthSnapshotProvider.future);
      container
          .read(tenantSearchProvider.notifier)
          .setStatusFilter(TenantStatusFilter.suspended);
      final state = container.read(tenantSearchProvider);
      expect(state.value?.length, 1);
      expect(state.value?.first.name, 'Hydra Corp');
    });

    test('archived filter shows only archived orgs', () async {
      const archivedTenant = TenantHealthView(
        id: 'org-archived',
        name: 'Defunct SA',
        planType: 'Basic',
        status: OrgStatus.archived,
        maxVehicles: 10,
        maxActiveContracts: 5,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
      );
      container = createContainer(tenants: [...mockTenants, archivedTenant]);
      await container.read(tenantHealthSnapshotProvider.future);
      container
          .read(tenantSearchProvider.notifier)
          .setStatusFilter(TenantStatusFilter.archived);
      final state = container.read(tenantSearchProvider);
      expect(state.value?.length, 1);
      expect(state.value?.first.name, 'Defunct SA');
    });

    test('suspended filter excludes archived orgs', () async {
      const archivedTenant = TenantHealthView(
        id: 'org-archived',
        name: 'Defunct SA',
        planType: 'Basic',
        status: OrgStatus.archived,
        maxVehicles: 10,
        maxActiveContracts: 5,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
      );
      container = createContainer(tenants: [...mockTenants, archivedTenant]);
      await container.read(tenantHealthSnapshotProvider.future);
      container
          .read(tenantSearchProvider.notifier)
          .setStatusFilter(TenantStatusFilter.suspended);
      final state = container.read(tenantSearchProvider);
      expect(state.value?.length, 1);
      expect(state.value?.first.name, 'Hydra Corp');
    });

    test('combination: search + status filter', () async {
      container = createContainer();
      await container.read(tenantHealthSnapshotProvider.future);
      final notifier = container.read(tenantSearchProvider.notifier);
      notifier.setStatusFilter(TenantStatusFilter.active);
      notifier.setQuery('Alpha');
      final state = container.read(tenantSearchProvider);
      expect(state.value?.length, 1);
      expect(state.value?.first.name, 'Alpha Trans');
    });

    test('empty query returns full list', () async {
      container = createContainer();
      await container.read(tenantHealthSnapshotProvider.future);
      final notifier = container.read(tenantSearchProvider.notifier);
      notifier.setQuery('Alpha');
      notifier.setQuery('');
      final state = container.read(tenantSearchProvider);
      expect(state.value?.length, 3);
    });

    test('empty tenant list returns empty result', () async {
      container = createContainer(tenants: []);
      await container.read(tenantHealthSnapshotProvider.future);
      final state = container.read(tenantSearchProvider);
      expect(state.value, isEmpty);
    });

    test('propagates error from source provider', () {
      container = ProviderContainer(
        overrides: [
          tenantSearchDebounceDurationProvider.overrideWithValue(Duration.zero),
          tenantHealthSnapshotProvider.overrideWithValue(
            AsyncError(Exception('DB down'), StackTrace.current),
          ),
        ],
      );
      final state = container.read(tenantSearchProvider);
      expect(state.hasError, true);
    });

    test('returns AsyncLoading when source data is loading', () {
      container = ProviderContainer(
        overrides: [
          tenantSearchDebounceDurationProvider.overrideWithValue(Duration.zero),
          tenantHealthSnapshotProvider.overrideWith((ref) {
            return Completer<List<TenantHealthView>>().future;
          }),
        ],
      );
      final state = container.read(tenantSearchProvider);
      expect(state.isLoading, true);
      expect(state.hasValue, false);
    });
  });

  group('TenantSearchNotifier — Debounce behavior', () {
    test('debounce delays filtering and exposes isDebouncing', () async {
      container = createContainer(debounce: const Duration(milliseconds: 300));
      await container.read(tenantHealthSnapshotProvider.future);

      final notifier = container.read(tenantSearchProvider.notifier);
      notifier.setQuery('Alpha');

      // During debounce: state is still AsyncData (unfiltered), isDebouncing=true
      var state = container.read(tenantSearchProvider);
      expect(state.hasValue, true);
      expect(state.value!.length, 3); // Previous unfiltered data
      expect(notifier.isDebouncing, true);

      // After debounce fires
      await Future<void>.delayed(const Duration(milliseconds: 350));
      state = container.read(tenantSearchProvider);
      expect(state.value!.length, 1);
      expect(state.value!.first.name, 'Alpha Trans');
      expect(notifier.isDebouncing, false);
    });

    test('rapid typing — only last query fires', () async {
      container = createContainer(debounce: const Duration(milliseconds: 300));
      await container.read(tenantHealthSnapshotProvider.future);

      final notifier = container.read(tenantSearchProvider.notifier);
      notifier.setQuery('A');
      notifier.setQuery('Al');
      notifier.setQuery('Alp');

      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = container.read(tenantSearchProvider);
      expect(state.value!.length, 1);
      expect(state.value!.first.name, 'Alpha Trans');
    });

    test('setQuery cancels previous timer', () async {
      container = createContainer(debounce: const Duration(milliseconds: 300));
      await container.read(tenantHealthSnapshotProvider.future);

      final notifier = container.read(tenantSearchProvider.notifier);
      notifier.setQuery('first');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      notifier.setQuery('Hydra');
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final state = container.read(tenantSearchProvider);
      expect(state.value!.length, 1);
      expect(state.value!.first.name, 'Hydra Corp');
    });

    test('timer cancelled on dispose — no leak', () {
      fakeAsync((async) {
        container = ProviderContainer(
          overrides: [
            tenantSearchDebounceDurationProvider.overrideWithValue(
              const Duration(milliseconds: 300),
            ),
            tenantHealthSnapshotProvider.overrideWith(
              (ref) => Future.value(mockTenants),
            ),
          ],
        );
        container.listen(tenantSearchProvider, (_, _) {});
        async.flushMicrotasks();

        container.read(tenantSearchProvider.notifier).setQuery('test');
        container.dispose();

        // Advance time — should not throw
        async.elapse(const Duration(milliseconds: 500));
      });
    });
  });

  group('TenantSearchNotifier — Accent & CNPJ filtering', () {
    test('filters by normalized name (accents)', () async {
      container = createContainer();
      await container.read(tenantHealthSnapshotProvider.future);
      container.read(tenantSearchProvider.notifier).setQuery('consorcio');
      final state = container.read(tenantSearchProvider);
      expect(state.value?.length, 1);
      expect(state.value?.first.name, 'Omni Consórcio');
    });

    test('filters by CNPJ digits only', () async {
      container = createContainer();
      await container.read(tenantHealthSnapshotProvider.future);
      container.read(tenantSearchProvider.notifier).setQuery('11444777');
      final state = container.read(tenantSearchProvider);
      expect(state.value?.length, 1);
      expect(state.value?.first.id, 'org-1');
    });

    test('filters by legal name', () async {
      container = createContainer();
      await container.read(tenantHealthSnapshotProvider.future);
      container.read(tenantSearchProvider.notifier).setQuery('Logistica');
      final state = container.read(tenantSearchProvider);
      expect(state.value?.length, 1);
      expect(state.value?.first.name, 'Hydra Corp');
    });

    test('filters by ID (exact match)', () async {
      container = createContainer();
      await container.read(tenantHealthSnapshotProvider.future);
      container.read(tenantSearchProvider.notifier).setQuery('org-3');
      final state = container.read(tenantSearchProvider);
      // org-3 matches by ID; also matches CNPJs containing digit '3'
      expect(state.value!.any((t) => t.name == 'Alpha Trans'), true);
    });
  });

  group('normalizeText & extractDigits — Pure Functions', () {
    test('normalizes accented characters', () {
      expect(normalizeText('Consórcio'), 'consorcio');
      expect(normalizeText('AÇÃO'), 'acao');
      expect(normalizeText('Ñoño'), 'nono');
    });

    test('extractDigits strips non-numeric', () {
      expect(extractDigits('11.444.777/0001-61'), '11444777000161');
      expect(extractDigits('abc'), '');
      expect(extractDigits('12abc34'), '1234');
    });
  });
}
