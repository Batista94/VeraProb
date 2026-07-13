import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/application/shared/super_admin_bypass_tenant_validator.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/super_admin/evidence_volume_view.dart';
import 'package:veraprob/application/super_admin/system_audit_log_view.dart';
import 'package:veraprob/application/super_admin/tenant_health_view.dart';
import 'package:veraprob/application/super_admin/tenant_technical_health_view.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/super_admin/i_cnpj_lookup_service.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/super_admin/system_audit_log_entry.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MOCKS
// ═══════════════════════════════════════════════════════════════════════════════

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockCnpjLookupService extends Mock implements ICnpjLookupService {}

class MockSystemAuditLogService extends Mock implements SystemAuditLogService {}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

TenantHealthSnapshot _makeSnapshot({
  String id = 'org-1',
  String name = 'Acme Corp',
  OrgStatus? status = OrgStatus.active,
}) {
  return TenantHealthSnapshot(
    id: id,
    name: name,
    isActive: status == OrgStatus.active,
    status: status,
    maxVehicles: 50,
    maxActiveContracts: 10,
    activeContractCount: 3,
    openCriticalAlertCount: 0,
  );
}

SystemAuditLogEntry _makeAuditEntry({
  String severity = 'info',
  String eventType = 'QUOTA_CHANGE',
  String occurredAt = '2026-01-01T00:00:00Z',
  String? organizationId = 'org-1',
  String? source = 'flutter_web',
  String? actorType = 'HUMAN',
  String? reason = 'test reason',
  String? impersonatorId,
}) {
  return SystemAuditLogEntry(
    severity: severity,
    eventType: eventType,
    occurredAt: occurredAt,
    organizationId: organizationId,
    payload: {'key': 'value'},
    source: source,
    actorType: actorType,
    reason: reason,
    impersonatorId: impersonatorId,
  );
}

/// Creates a container with mocked dependencies for isolated provider tests.
ProviderContainer _createContainer({
  MockSuperAdminRepository? repo,
  MockSupabaseClient? client,
}) {
  final mockClient = client ?? MockSupabaseClient();
  final mockRepo = repo ?? MockSuperAdminRepository();

  return ProviderContainer.test(
    overrides: [
      supabaseClientProvider.overrideWithValue(mockClient),
      superAdminRepositoryProvider.overrideWithValue(mockRepo),
    ],
  );
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════════
  // GROUP 0: hmacRequestKeyProvider Resolution (INV-31)
  // ═════════════════════════════════════════════════════════════════════════════
  group('hmacRequestKeyProvider Resolution (INV-31)', () {
    tearDown(() {
      // Limpa o estado do dotenv após cada teste
      dotenv.clean();
    });

    test(
      'Caso 1: Resolve com sucesso a partir das SharedPreferences',
      () async {
        SharedPreferences.setMockInitialValues({
          'hmac_request_key_v1': 'key-from-shared-prefs',
        });
        final prefs = await SharedPreferences.getInstance();

        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );

        final key = container.read(hmacRequestKeyProvider);
        expect(key, equals('key-from-shared-prefs'));
        container.dispose();
      },
    );

    test(
      'Caso 2: Resolve a partir do dotenv quando SharedPreferences estiver vazio',
      () async {
        // Configura o mock do SharedPreferences vazio
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        // Inicializa o dotenv no contexto do teste
        dotenv.loadFromString(envString: 'HMAC_SECRET_KEY_V1=test-key');

        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );

        final key = container.read(hmacRequestKeyProvider);
        expect(key, equals('test-key'));
        container.dispose();
      },
    );

    test(
      'Caso 3: Lança IntegrityException quando ausente em ambas as fontes',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );

        expect(
          () => container.read(hmacRequestKeyProvider),
          throwsA(isA<ProviderException>()),
        );
        container.dispose();
      },
    );
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // GROUP 1: SECURITY INVARIANTS (CIA TRIAD)
  // ═════════════════════════════════════════════════════════════════════════════
  group('Security Invariants (CIA Triad)', () {
    test(
      'INV-3/14: superAdminRepositoryProvider injects supabaseClientProvider',
      () {
        final mockClient = MockSupabaseClient();
        final container = ProviderContainer.test(
          overrides: [
            supabaseClientProvider.overrideWithValue(mockClient),
            hmacRequestKeyProvider.overrideWithValue(
              'test-hmac-key-v1-32chars-padding00',
            ),
          ],
        );

        // Reading the provider should not throw — proves DI wiring is correct
        final repo = container.read(superAdminRepositoryProvider);
        expect(repo, isNotNull);
        container.dispose();
      },
    );

    test(
      'INV-3/14: cnpjLookupServiceProvider injects supabaseClientProvider',
      () {
        final mockClient = MockSupabaseClient();
        final container = ProviderContainer.test(
          overrides: [
            supabaseClientProvider.overrideWithValue(mockClient),
            hmacRequestKeyProvider.overrideWithValue(
              'test-hmac-key-v1-32chars-padding00',
            ),
          ],
        );

        final service = container.read(cnpjLookupServiceProvider);
        expect(service, isNotNull);
        container.dispose();
      },
    );

    test(
      'INV-30: systemAuditLogServiceProvider uses global Supabase client',
      () {
        final mockClient = MockSupabaseClient();
        final container = ProviderContainer.test(
          overrides: [supabaseClientProvider.overrideWithValue(mockClient)],
        );

        final service = container.read(systemAuditLogServiceProvider);
        expect(service, isNotNull);
        container.dispose();
      },
    );

    test(
      'Isolation: SuperAdminBypassTenantValidator is no-op for assertTenantMatches',
      () async {
        const validator = SuperAdminBypassTenantValidator();

        // Must complete without throwing — proves bypass semantics
        await expectLater(
          validator.assertTenantMatches(
            payloadOrgId: 'any-org',
            sessionId: 'any-session',
          ),
          completes,
        );
      },
    );

    test(
      'Isolation: SuperAdminBypassTenantValidator is no-op for verifySourceOwnership',
      () {
        const validator = SuperAdminBypassTenantValidator();

        // Must not throw — proves bypass semantics for INV-27
        expect(
          () => validator.verifySourceOwnership(
            resourceOrgId: 'org-a',
            requesterOrgId: 'org-b',
          ),
          returnsNormally,
        );
      },
    );

    test(
      'Isolation: SuperAdminBypassTenantValidator implements TenantValidationService',
      () {
        const validator = SuperAdminBypassTenantValidator();
        expect(validator, isA<TenantValidationService>());
      },
    );

    test('INV-30: supabaseClientProvider throws when not overridden', () {
      final container = ProviderContainer.test();
      expect(
        () => container.read(supabaseClientProvider),
        throwsA(isA<ProviderException>()),
      );
      container.dispose();
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // GROUP 2: TIMEOUT ENFORCEMENT (Requirement 5.6)
  // ═════════════════════════════════════════════════════════════════════════════
  group('Timeout Enforcement', () {
    test(
      'tenantHealthSnapshotProvider emits TimeoutException on hanging repo',
      () {
        fakeAsync((async) {
          final mockRepo = MockSuperAdminRepository();
          when(
            () => mockRepo.getAllTenantHealth(),
          ).thenAnswer((_) => Completer<List<TenantHealthSnapshot>>().future);

          final container = _createContainer(repo: mockRepo);
          // Subscribe to trigger provider build
          container.listen(tenantHealthSnapshotProvider, (_, _) {});
          async.flushMicrotasks();

          // Provider should be loading
          expect(
            container.read(tenantHealthSnapshotProvider).isLoading,
            isTrue,
          );

          // Advance past 30s timeout
          async.elapse(const Duration(seconds: 31));

          final state = container.read(tenantHealthSnapshotProvider);
          expect(state.hasError, isTrue);
          expect(state.error, isA<TimeoutException>());
          container.dispose();
        });
      },
    );

    test(
      'tenantTechnicalHealthProvider emits TimeoutException on hanging repo',
      () {
        fakeAsync((async) {
          final mockRepo = MockSuperAdminRepository();
          when(
            () => mockRepo.getTenantTechnicalHealth(any()),
          ).thenAnswer((_) => Completer<Map<String, dynamic>>().future);

          final container = _createContainer(repo: mockRepo);
          container.listen(tenantTechnicalHealthProvider('org-1'), (_, _) {});
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 31));

          final state = container.read(tenantTechnicalHealthProvider('org-1'));
          expect(state.hasError, isTrue);
          expect(state.error, isA<TimeoutException>());
          container.dispose();
        });
      },
    );

    test('evidenceVolumeProvider emits TimeoutException on hanging repo', () {
      fakeAsync((async) {
        final mockRepo = MockSuperAdminRepository();
        when(
          () => mockRepo.getEvidenceVolume(any()),
        ).thenAnswer((_) => Completer<Map<String, dynamic>>().future);

        final container = _createContainer(repo: mockRepo);
        container.listen(evidenceVolumeProvider('org-1'), (_, _) {});
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 31));

        final state = container.read(evidenceVolumeProvider('org-1'));
        expect(state.hasError, isTrue);
        expect(state.error, isA<TimeoutException>());
        container.dispose();
      });
    });

    test('systemAuditLogProvider emits TimeoutException on hanging repo', () {
      fakeAsync((async) {
        final mockRepo = MockSuperAdminRepository();
        when(
          () => mockRepo.getSystemAuditLog(
            organizationId: any(named: 'organizationId'),
            severity: any(named: 'severity'),
            fromDate: any(named: 'fromDate'),
            toDate: any(named: 'toDate'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) => Completer<List<SystemAuditLogEntry>>().future);

        final container = _createContainer(repo: mockRepo);
        const params = AuditLogParams(organizationId: 'org-1');
        container.listen(systemAuditLogProvider(params), (_, _) {});
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 31));

        final state = container.read(systemAuditLogProvider(params));
        expect(state.hasError, isTrue);
        expect(state.error, isA<TimeoutException>());
        container.dispose();
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // GROUP 3: NETWORK CORRUPTION
  // ═════════════════════════════════════════════════════════════════════════════
  group('Network Corruption', () {
    test(
      'tenantHealthSnapshotProvider emits AsyncError on SocketException',
      () {
        fakeAsync((async) {
          final mockRepo = MockSuperAdminRepository();
          when(() => mockRepo.getAllTenantHealth()).thenAnswer(
            (_) async => throw const SocketException('Connection refused'),
          );

          final container = _createContainer(repo: mockRepo);
          container.listen(tenantHealthSnapshotProvider, (_, _) {});
          async.flushMicrotasks();

          final state = container.read(tenantHealthSnapshotProvider);
          expect(state.hasError, isTrue);
          expect(state.error, isA<SocketException>());
          container.dispose();
        });
      },
    );

    test(
      'tenantTechnicalHealthProvider emits AsyncError on SocketException',
      () {
        fakeAsync((async) {
          final mockRepo = MockSuperAdminRepository();
          when(() => mockRepo.getTenantTechnicalHealth(any())).thenAnswer(
            (_) async => throw const SocketException('Network unreachable'),
          );

          final container = _createContainer(repo: mockRepo);
          container.listen(tenantTechnicalHealthProvider('org-1'), (_, _) {});
          async.flushMicrotasks();

          final state = container.read(tenantTechnicalHealthProvider('org-1'));
          expect(state.hasError, isTrue);
          expect(state.error, isA<SocketException>());
          container.dispose();
        });
      },
    );

    test('evidenceVolumeProvider emits AsyncError on SocketException', () {
      fakeAsync((async) {
        final mockRepo = MockSuperAdminRepository();
        when(() => mockRepo.getEvidenceVolume(any())).thenAnswer(
          (_) async => throw const SocketException('Host not found'),
        );

        final container = _createContainer(repo: mockRepo);
        container.listen(evidenceVolumeProvider('org-1'), (_, _) {});
        async.flushMicrotasks();

        final state = container.read(evidenceVolumeProvider('org-1'));
        expect(state.hasError, isTrue);
        expect(state.error, isA<SocketException>());
        container.dispose();
      });
    });

    test('systemAuditLogProvider emits AsyncError on server 500', () {
      fakeAsync((async) {
        final mockRepo = MockSuperAdminRepository();
        when(
          () => mockRepo.getSystemAuditLog(
            organizationId: any(named: 'organizationId'),
            severity: any(named: 'severity'),
            fromDate: any(named: 'fromDate'),
            toDate: any(named: 'toDate'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => throw Exception('500 Internal Server Error'));

        final container = _createContainer(repo: mockRepo);
        const params = AuditLogParams(organizationId: 'org-1');
        container.listen(systemAuditLogProvider(params), (_, _) {});
        async.flushMicrotasks();

        final state = container.read(systemAuditLogProvider(params));
        expect(state.hasError, isTrue);
        expect(state.error, isA<Exception>());
        container.dispose();
      });
    });

    test(
      'tenantHealthSnapshotProvider propagates error type in AsyncValue',
      () {
        fakeAsync((async) {
          final mockRepo = MockSuperAdminRepository();
          when(() => mockRepo.getAllTenantHealth()).thenAnswer(
            (_) async => throw const SocketException('Connection reset'),
          );

          final container = _createContainer(repo: mockRepo);
          container.listen(tenantHealthSnapshotProvider, (_, _) {});
          async.flushMicrotasks();

          final asyncValue = container.read(tenantHealthSnapshotProvider);
          expect(asyncValue.hasError, isTrue);
          expect(asyncValue.error, isA<SocketException>());
          container.dispose();
        });
      },
    );
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // GROUP 4: RACE CONDITIONS
  // ═════════════════════════════════════════════════════════════════════════════
  group('Race Conditions', () {
    test(
      'rapid invalidation of tenantsListProvider yields consistent state',
      () async {
        final mockRepo = MockSuperAdminRepository();
        var callCount = 0;

        when(() => mockRepo.getAllTenantHealth()).thenAnswer((_) async {
          callCount++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return [_makeSnapshot(name: 'Call-$callCount')];
        });

        final container = _createContainer(repo: mockRepo);

        // Trigger initial load
        container.read(tenantHealthSnapshotProvider);

        // Rapid invalidations while loading
        container.invalidate(tenantHealthSnapshotProvider);
        container.invalidate(tenantHealthSnapshotProvider);
        container.invalidate(tenantHealthSnapshotProvider);

        // Wait for settlement
        final result = await container.read(
          tenantHealthSnapshotProvider.future,
        );

        // State must be consistent — single list, no corruption
        expect(result, isA<List<TenantHealthView>>());
        expect(result.length, 1);
        container.dispose();
      },
    );

    test(
      'tenantDetailProvider remains consistent during tenantsListProvider refresh',
      () async {
        final mockRepo = MockSuperAdminRepository();
        when(() => mockRepo.getAllTenantHealth()).thenAnswer(
          (_) async => [
            _makeSnapshot(id: 'org-1', name: 'Acme'),
            _makeSnapshot(id: 'org-2', name: 'Beta'),
          ],
        );

        final container = _createContainer(repo: mockRepo);

        // Load initial data
        await container.read(tenantHealthSnapshotProvider.future);

        // Read detail while parent is stable
        final detail = await container.read(
          tenantDetailProvider('org-1').future,
        );
        expect(detail, isNotNull);
        expect(detail!.id, 'org-1');

        // Invalidate parent — detail should still resolve correctly after refresh
        container.invalidate(tenantHealthSnapshotProvider);
        final detailAfter = await container.read(
          tenantDetailProvider('org-1').future,
        );
        expect(detailAfter, isNotNull);
        expect(detailAfter!.id, 'org-1');
        container.dispose();
      },
    );

    test(
      'concurrent reads of family providers with different IDs do not cross-contaminate',
      () async {
        final mockRepo = MockSuperAdminRepository();
        when(() => mockRepo.getTenantTechnicalHealth('org-1')).thenAnswer(
          (_) async => {
            'replication_status': 'healthy',
            'schema_integrity_status': 'compliant',
            'schema_version': 'v1.0',
          },
        );
        when(() => mockRepo.getTenantTechnicalHealth('org-2')).thenAnswer(
          (_) async => {
            'replication_status': 'failed',
            'schema_integrity_status': 'critical_drift',
            'schema_version': 'v0.9',
          },
        );

        final container = _createContainer(repo: mockRepo);

        // Read both concurrently
        final results = await Future.wait([
          container.read(tenantTechnicalHealthProvider('org-1').future),
          container.read(tenantTechnicalHealthProvider('org-2').future),
        ]);

        expect(results[0].replicationStatus, ReplicationStatus.healthy);
        expect(results[1].replicationStatus, ReplicationStatus.failed);
        expect(results[0].schemaVersion, 'v1.0');
        expect(results[1].schemaVersion, 'v0.9');
        container.dispose();
      },
    );

    test('container disposal does not leak pending futures', () async {
      final mockRepo = MockSuperAdminRepository();
      final completer = Completer<List<TenantHealthSnapshot>>();
      when(
        () => mockRepo.getAllTenantHealth(),
      ).thenAnswer((_) => completer.future);

      final container = _createContainer(repo: mockRepo);

      // Start loading but don't await
      container.read(tenantHealthSnapshotProvider);

      // Dispose while still loading — must not throw
      expect(() => container.dispose(), returnsNormally);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // GROUP 5: FutureProvider.family BEHAVIOR
  // ═════════════════════════════════════════════════════════════════════════════
  group('FutureProvider.family behavior', () {
    test('tenantDetailProvider returns null for non-existent orgId', () async {
      final mockRepo = MockSuperAdminRepository();
      when(
        () => mockRepo.getAllTenantHealth(),
      ).thenAnswer((_) async => [_makeSnapshot(id: 'org-1')]);

      final container = _createContainer(repo: mockRepo);
      final result = await container.read(
        tenantDetailProvider('non-existent').future,
      );

      expect(result, isNull);
      container.dispose();
    });

    test('tenantDetailProvider returns correct tenant from list', () async {
      final mockRepo = MockSuperAdminRepository();
      when(() => mockRepo.getAllTenantHealth()).thenAnswer(
        (_) async => [
          _makeSnapshot(id: 'org-1', name: 'Alpha'),
          _makeSnapshot(id: 'org-2', name: 'Beta'),
          _makeSnapshot(id: 'org-3', name: 'Gamma'),
        ],
      );

      final container = _createContainer(repo: mockRepo);
      final result = await container.read(tenantDetailProvider('org-2').future);

      expect(result, isNotNull);
      expect(result!.name, 'Beta');
      container.dispose();
    });

    test('tenantTechnicalHealthProvider caches per orgId', () async {
      final mockRepo = MockSuperAdminRepository();
      var callCount = 0;
      when(() => mockRepo.getTenantTechnicalHealth('org-1')).thenAnswer((
        _,
      ) async {
        callCount++;
        return {
          'replication_status': 'healthy',
          'schema_integrity_status': 'compliant',
          'schema_version': 'v1.0',
        };
      });

      final container = _createContainer(repo: mockRepo);

      // Read twice — second read should use cached value
      await container.read(tenantTechnicalHealthProvider('org-1').future);
      await container.read(tenantTechnicalHealthProvider('org-1').future);

      expect(callCount, 1);
      container.dispose();
    });

    test('evidenceVolumeProvider returns distinct data per orgId', () async {
      final mockRepo = MockSuperAdminRepository();
      when(() => mockRepo.getEvidenceVolume('org-1')).thenAnswer(
        (_) async => {'total_historical': 1000, 'total_monthly': 50},
      );
      when(
        () => mockRepo.getEvidenceVolume('org-2'),
      ).thenAnswer((_) async => {'total_historical': 500, 'total_monthly': 25});

      final container = _createContainer(repo: mockRepo);

      final vol1 = await container.read(evidenceVolumeProvider('org-1').future);
      final vol2 = await container.read(evidenceVolumeProvider('org-2').future);

      expect(vol1.totalHistorical, 1000);
      expect(vol2.totalHistorical, 500);
      expect(vol1.totalMonthly, 50);
      expect(vol2.totalMonthly, 25);
      container.dispose();
    });

    test(
      'systemAuditLogProvider differentiates by AuditLogParams equality',
      () async {
        final mockRepo = MockSuperAdminRepository();
        when(
          () => mockRepo.getSystemAuditLog(
            organizationId: 'org-1',
            severity: any(named: 'severity'),
            fromDate: any(named: 'fromDate'),
            toDate: any(named: 'toDate'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => [_makeAuditEntry()]);
        when(
          () => mockRepo.getSystemAuditLog(
            organizationId: 'org-2',
            severity: any(named: 'severity'),
            fromDate: any(named: 'fromDate'),
            toDate: any(named: 'toDate'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => [_makeAuditEntry(severity: 'critical')]);

        final container = _createContainer(repo: mockRepo);

        const p1 = AuditLogParams(organizationId: 'org-1');
        const p2 = AuditLogParams(organizationId: 'org-2');

        final r1 = await container.read(systemAuditLogProvider(p1).future);
        final r2 = await container.read(systemAuditLogProvider(p2).future);

        expect(r1.first.severity, 'info');
        expect(r2.first.severity, 'critical');
        container.dispose();
      },
    );

    test('AuditLogParams equality and hashCode contract', () {
      const a = AuditLogParams(organizationId: 'org-1', limit: 50);
      const b = AuditLogParams(organizationId: 'org-1', limit: 50);
      const c = AuditLogParams(organizationId: 'org-2', limit: 50);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // GROUP 6: VIEW MAPPING LOSSLESS VERIFICATION
  // ═════════════════════════════════════════════════════════════════════════════
  group('View mapping lossless verification', () {
    test('TenantHealthView.fromDomain preserves all fields', () {
      final snapshot = TenantHealthSnapshot(
        id: 'org-abc',
        name: 'Test Corp',
        legalName: 'Test Corp LTDA',
        planType: 'enterprise',
        isActive: true,
        status: OrgStatus.active,
        maxVehicles: 100,
        maxActiveContracts: 20,
        activeContractCount: 5,
        lastTelemetryAt: DateTime.utc(2026, 1, 15),
        openCriticalAlertCount: 2,
        capabilities: {'gps_tracking': true, 'evidence_photos': true},
        toolCostCents: 5000,
        dwellTimeSeconds: 600,
        billingDay: 15,
        contactEmail: 'admin@test.com',
        externalId: 'ext-123',
        cnpj: '12345678000199',
      );

      final view = TenantHealthView.fromDomain(snapshot);

      expect(view.id, snapshot.id);
      expect(view.name, snapshot.name);
      expect(view.legalName, snapshot.legalName);
      expect(view.planType, snapshot.planType);
      expect(view.status, snapshot.status);
      expect(view.maxVehicles, snapshot.maxVehicles);
      expect(view.maxActiveContracts, snapshot.maxActiveContracts);
      expect(view.activeContractCount, snapshot.activeContractCount);
      expect(view.lastTelemetryAt, snapshot.lastTelemetryAt);
      expect(view.openCriticalAlertCount, snapshot.openCriticalAlertCount);
      expect(view.toolCostCents, snapshot.toolCostCents);
      expect(view.dwellTimeSeconds, snapshot.dwellTimeSeconds);
      expect(view.billingDay, snapshot.billingDay);
      expect(view.contactEmail, snapshot.contactEmail);
      expect(view.externalId, snapshot.externalId);
      expect(view.cnpj, snapshot.cnpj);
    });

    test('TenantHealthView.fromDomain handles null optional fields', () {
      const snapshot = TenantHealthSnapshot(
        id: 'org-min',
        name: 'Minimal',
        isActive: false,
        status: null,
        maxVehicles: 0,
        maxActiveContracts: 0,
        activeContractCount: 0,
        openCriticalAlertCount: 0,
      );

      final view = TenantHealthView.fromDomain(snapshot);

      expect(view.legalName, isNull);
      expect(view.planType, isNull);
      expect(view.status, isNull);
      expect(view.lastTelemetryAt, isNull);
      expect(view.toolCostCents, isNull);
      expect(view.billingDay, isNull);
      expect(view.contactEmail, isNull);
      expect(view.cnpj, isNull);
    });

    test('SystemAuditLogView.fromDomain preserves all fields losslessly', () {
      const entry = SystemAuditLogEntry(
        severity: 'critical',
        eventType: 'IMPERSONATION_START',
        occurredAt: '2026-03-15T10:30:00Z',
        organizationId: 'org-target',
        payload: {'before': 'active', 'after': 'impersonated'},
        source: 'edge_function',
        actorType: 'IMPERSONATOR',
        reason: 'Support ticket #1234',
        impersonatorId: 'super-admin-uuid',
      );

      final view = SystemAuditLogView.fromDomain(entry);

      expect(view.severity, entry.severity);
      expect(view.eventType, entry.eventType);
      expect(view.occurredAt, entry.occurredAt);
      expect(view.organizationId, entry.organizationId);
      expect(view.payload, entry.payload);
      expect(view.source, entry.source);
      expect(view.actorType, entry.actorType);
      expect(view.reason, entry.reason);
      expect(view.impersonatorId, entry.impersonatorId);
    });

    test('SystemAuditLogView.fromDomain handles null optional fields', () {
      const entry = SystemAuditLogEntry(
        severity: 'info',
        eventType: 'QUOTA_CHANGE',
        occurredAt: '2026-01-01T00:00:00Z',
      );

      final view = SystemAuditLogView.fromDomain(entry);

      expect(view.organizationId, isNull);
      expect(view.payload, isNull);
      expect(view.source, isNull);
      expect(view.actorType, isNull);
      expect(view.reason, isNull);
      expect(view.impersonatorId, isNull);
    });

    test('TenantTechnicalHealthView.fromJson maps all enum variants', () {
      final json = <String, Object?>{
        'replication_status': 'delayed',
        'schema_integrity_status': 'minor_drift',
        'schema_version': 'v2.1',
        'last_check_at': '2026-05-01T12:00:00Z',
      };

      final view = TenantTechnicalHealthView.fromJson(json);

      expect(view.replicationStatus, ReplicationStatus.delayed);
      expect(view.schemaIntegrityStatus, SchemaIntegrityStatus.minorDrift);
      expect(view.schemaVersion, 'v2.1');
      expect(view.lastCheckAt, DateTime.utc(2026, 5, 1, 12));
    });

    test(
      'TenantTechnicalHealthView.fromJson defaults unknown values safely',
      () {
        final json = <String, Object?>{
          'replication_status': 'garbage',
          'schema_integrity_status': null,
          'schema_version': null,
        };

        final view = TenantTechnicalHealthView.fromJson(json);

        expect(view.replicationStatus, ReplicationStatus.unknown);
        expect(view.schemaIntegrityStatus, SchemaIntegrityStatus.unknown);
        expect(view.schemaVersion, 'unknown');
        expect(view.lastCheckAt, isNull);
      },
    );

    test('EvidenceVolumeView.fromJson maps numeric fields correctly', () {
      final json = <String, Object?>{
        'total_historical': 12345,
        'total_monthly': 678,
      };

      final view = EvidenceVolumeView.fromJson(json);

      expect(view.totalHistorical, 12345);
      expect(view.totalMonthly, 678);
    });

    test('EvidenceVolumeView.fromJson defaults to zero on null', () {
      final json = <String, Object?>{};

      final view = EvidenceVolumeView.fromJson(json);

      expect(view.totalHistorical, 0);
      expect(view.totalMonthly, 0);
    });
  });
}
