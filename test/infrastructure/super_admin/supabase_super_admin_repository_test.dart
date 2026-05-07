/// Unit tests for [SupabaseSuperAdminRepository] — Edge Proxy path (Phase 9.6.A.1).
///
/// These tests verify that the repository routes reads through the Edge Function
/// `super-admin-proxy` instead of using a service_role client directly (INV-3/INV-14).
///
/// TDD: Tests were written BEFORE the refactor — they fail on the old two-client
/// constructor and pass once the repository is migrated to functions.invoke.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/features/super_admin/infrastructure/supabase_super_admin_repository.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockSupabaseClient mockClient;
  late MockFunctionsClient mockFunctions;
  late SupabaseSuperAdminRepository repo;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();
    when(() => mockClient.functions).thenReturn(mockFunctions);
    // Constructor takes ONE client — no service_role (INV-3)
    repo = SupabaseSuperAdminRepository(mockClient);
  });

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(HttpMethod.post);
  });

  group('SupabaseSuperAdminRepository — Edge Proxy', () {
    // ── INV-3: No service_role field ─────────────────────────────────────────

    test(
      'constructor accepts exactly one SupabaseClient (no service_role field)',
      () {
        // The repository must be instantiable with a single client.
        // If the old two-arg constructor still exists, this test fails to compile.
        expect(repo, isNotNull);
      },
    );

    // ── getAllTenantHealth ────────────────────────────────────────────────────

    group('getAllTenantHealth', () {
      test(
        'invokes super-admin-proxy with action=list_tenant_health',
        () async {
          when(
            () => mockFunctions.invoke(
              'super-admin-proxy',
              body: any(named: 'body'),
            ),
          ).thenAnswer(
            (_) async => FunctionResponse(
              data: {
                'data': [
                  {
                    'id': 'org-uuid-1',
                    'name': 'Transportes Silva',
                    'active_contract_count': 2,
                    'open_critical_alert_count': 0,
                    'total_vehicles': 5,
                    'is_active': true,
                  },
                ],
              },
              status: 200,
            ),
          );

          final result = await repo.getAllTenantHealth();

          final captured = verify(
            () => mockFunctions.invoke(
              'super-admin-proxy',
              body: captureAny(named: 'body'),
            ),
          ).captured;

          expect(captured, hasLength(1));
          final body = captured.first as Map<String, dynamic>;
          expect(body['action'], equals('list_tenant_health'));

          expect(result, hasLength(1));
          expect(result.first.id, equals('org-uuid-1'));
        },
      );

      test('returns empty list when proxy returns empty data', () async {
        when(
          () => mockFunctions.invoke(
            'super-admin-proxy',
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => FunctionResponse(
            data: <String, dynamic>{'data': []},
            status: 200,
          ),
        );

        final result = await repo.getAllTenantHealth();
        expect(result, isEmpty);
      });
    });

    // ── getSystemAuditLog ─────────────────────────────────────────────────────

    group('getSystemAuditLog', () {
      test('invokes super-admin-proxy with action=get_audit_log', () async {
        when(
          () => mockFunctions.invoke(
            'super-admin-proxy',
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => FunctionResponse(
            data: <String, dynamic>{'data': []},
            status: 200,
          ),
        );

        await repo.getSystemAuditLog(limit: 10);

        final captured = verify(
          () => mockFunctions.invoke(
            'super-admin-proxy',
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final body = captured.first as Map<String, dynamic>;
        expect(body['action'], equals('get_audit_log'));
        expect(body['params'], isA<Map<String, dynamic>>());
      });

      test('passes limit in params', () async {
        when(
          () => mockFunctions.invoke(
            'super-admin-proxy',
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => FunctionResponse(
            data: <String, dynamic>{'data': []},
            status: 200,
          ),
        );

        await repo.getSystemAuditLog(limit: 42);

        final captured = verify(
          () => mockFunctions.invoke(
            'super-admin-proxy',
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final params =
            (captured.first as Map<String, dynamic>)['params']
                as Map<String, dynamic>;
        expect(params['limit'], equals(42));
      });

      test('passes organizationId filter in params when provided', () async {
        when(
          () => mockFunctions.invoke(
            'super-admin-proxy',
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => FunctionResponse(
            data: <String, dynamic>{'data': []},
            status: 200,
          ),
        );

        await repo.getSystemAuditLog(organizationId: 'org-uuid-99', limit: 20);

        final captured = verify(
          () => mockFunctions.invoke(
            'super-admin-proxy',
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final params =
            (captured.first as Map<String, dynamic>)['params']
                as Map<String, dynamic>;
        expect(params['organization_id'], equals('org-uuid-99'));
      });

      test('passes severity filter in params when provided', () async {
        when(
          () => mockFunctions.invoke(
            'super-admin-proxy',
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => FunctionResponse(
            data: <String, dynamic>{'data': []},
            status: 200,
          ),
        );

        await repo.getSystemAuditLog(severity: 'error', limit: 10);

        final captured = verify(
          () => mockFunctions.invoke(
            'super-admin-proxy',
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final params =
            (captured.first as Map<String, dynamic>)['params']
                as Map<String, dynamic>;
        expect(params['severity'], equals('error'));
      });

      test('omits null filters from params', () async {
        when(
          () => mockFunctions.invoke(
            'super-admin-proxy',
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => FunctionResponse(
            data: <String, dynamic>{'data': []},
            status: 200,
          ),
        );

        await repo.getSystemAuditLog(limit: 5);

        final captured = verify(
          () => mockFunctions.invoke(
            'super-admin-proxy',
            body: captureAny(named: 'body'),
          ),
        ).captured;

        final params =
            (captured.first as Map<String, dynamic>)['params']
                as Map<String, dynamic>;
        expect(params.containsKey('organization_id'), isFalse);
        expect(params.containsKey('severity'), isFalse);
      });
    });
  });
}
