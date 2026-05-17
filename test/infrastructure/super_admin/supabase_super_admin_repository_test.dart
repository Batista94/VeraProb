// ignore_for_file: lines_longer_than_80_chars
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/archive_organization_command.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/plan_type.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';
import 'package:veraprob/infrastructure/super_admin/supabase_super_admin_repository.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kOrgId = 'org-00000000-0000-0000-0000-000000000001';
const _kUserId = 'usr-00000000-0000-0000-0000-000000000001';
const _kEmail = 'admin@acme.com';
const _kToken = 'tok-secure-random-256';
const _kInvitationId = 'inv-00000000-0000-0000-0000-000000000001';

CreateOrganizationCommand _createOrgCmd({String cnpj = '12.345.678/0001-90'}) =>
    CreateOrganizationCommand(
      legalName: 'Acme Ltda',
      tradeName: 'Acme',
      cnpj: cnpj,
      timezone: 'America/Sao_Paulo',
      currencyCode: 'BRL',
      planType: PlanType.professional,
      maxVehicles: 50,
      maxActiveContracts: 10,
      adminEmails: [_kEmail],
      superAdminUserId: _kUserId,
      capabilities: const OrgCapabilities(),
      toolCostCents: 9900,
      dwellTimeSeconds: 300,
      reason: 'New client onboarding',
      billingDay: 15,
      contactEmail: _kEmail,
      externalId: 'CRM-001',
      organizationType: 'CARGO',
      allowedDomains: ['acme.com'],
    );

UpdateOrganizationQuotaCommand _updateQuotaCmd() =>
    UpdateOrganizationQuotaCommand(
      organizationId: _kOrgId,
      newPlanType: 'enterprise',
      newMaxVehicles: 200,
      newMaxActiveContracts: 50,
      superAdminUserId: _kUserId,
      reason: 'Upgrade request',
      sessionId: 'session-001',
      expectedUpdatedAt: DateTime.utc(2026, 5, 1),
    );

ArchiveOrganizationCommand _archiveCmd() => const ArchiveOrganizationCommand(
  orgId: _kOrgId,
  reason: 'Client churned',
  superAdminUserId: _kUserId,
  currentStatus: OrgStatus.active,
  sessionId: 'session-001',
);

// ── PostgREST Error Factory ───────────────────────────────────────────────────

PostgrestException _pgError(String code, {String? message, String? details}) =>
    PostgrestException(
      message: message ?? 'pg error $code',
      code: code,
      details: details,
    );

// ── Edge Function Response Factory ────────────────────────────────────────────

FunctionResponse _fnOk(dynamic data) =>
    FunctionResponse(status: 200, data: data);

// ── Fake PostgrestFilterBuilder ────────────────────────────────────────────────

class _FakePostgrestFilterBuilder extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  final dynamic _result;
  final Object? _error;

  _FakePostgrestFilterBuilder(this._result, {Object? error}) : _error = error;

  @override
  Future<S> then<S>(
    FutureOr<S> Function(dynamic value) onValue, {
    Function? onError,
  }) {
    if (_error != null) {
      return Future<dynamic>.error(_error).then(onValue, onError: onError);
    }
    return Future<dynamic>.value(_result).then(onValue, onError: onError);
  }

  @override
  Future<dynamic> catchError(Function onError, {bool Function(Object)? test}) {
    if (_error != null) {
      return Future<dynamic>.error(_error).catchError(onError, test: test);
    }
    return Future<dynamic>.value(_result);
  }

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) {
    if (_error != null) {
      return Future<dynamic>.error(_error).whenComplete(action);
    }
    return Future<dynamic>.value(_result).whenComplete(action);
  }

  @override
  Stream<dynamic> asStream() =>
      _error != null ? Stream.error(_error) : Stream.value(_result);

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) {
    if (_error != null) return Future<dynamic>.error(_error);
    return Future<dynamic>.value(_result);
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

void main() {
  late MockSupabaseClient mockClient;
  late MockFunctionsClient mockFunctions;
  late SupabaseSuperAdminRepository repo;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();
    when(() => mockClient.functions).thenReturn(mockFunctions);
    repo = SupabaseSuperAdminRepository(mockClient);
  });

  // ── Helper: stub RPC success ──────────────────────────────────────────────
  void stubRpc(String name, dynamic result) {
    when(
      () => mockClient.rpc<dynamic>(name, params: any(named: 'params')),
    ).thenAnswer((_) => _FakePostgrestFilterBuilder(result));
  }

  // ── Helper: stub RPC failure ──────────────────────────────────────────────
  void stubRpcThrows(String name, PostgrestException error) {
    when(
      () => mockClient.rpc<dynamic>(name, params: any(named: 'params')),
    ).thenThrow(error);
  }

  // ── Helper: stub Edge Function success ────────────────────────────────────
  void stubEdgeFn(dynamic data) {
    when(
      () => mockFunctions.invoke(any(), body: any(named: 'body')),
    ).thenAnswer((_) async => _fnOk(data));
  }

  // ── Helper: stub Edge Function failure ────────────────────────────────────
  void stubEdgeFnThrows(Exception error) {
    when(
      () => mockFunctions.invoke(any(), body: any(named: 'body')),
    ).thenThrow(error);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // createOrganization
  // ═══════════════════════════════════════════════════════════════════════════
  group('createOrganization', () {
    const rpcName = 'super_admin_create_organization';

    test('returns org UUID on success', () async {
      stubRpc(rpcName, _kOrgId);
      final result = await repo.createOrganization(_createOrgCmd());
      expect(result, _kOrgId);
    });

    test('strips CNPJ non-digit characters before RPC call', () async {
      stubRpc(rpcName, _kOrgId);
      await repo.createOrganization(_createOrgCmd(cnpj: '12.345.678/0001-90'));

      final captured =
          verify(
                () => mockClient.rpc<dynamic>(
                  rpcName,
                  params: captureAny(named: 'params'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['p_cnpj'], '12345678000190');
    });

    test(
      'maps 23505 unique_violation → IntegrityException with field',
      () async {
        stubRpcThrows(
          rpcName,
          _pgError(
            '23505',
            message: 'duplicate key',
            details: 'Key (cnpj)=(12345678000190) already exists.',
          ),
        );
        expect(
          () => repo.createOrganization(_createOrgCmd()),
          throwsA(
            isA<IntegrityException>().having((e) => e.field, 'field', 'cnpj'),
          ),
        );
      },
    );

    test('maps P0001 RAISE EXCEPTION → IntegrityException', () async {
      stubRpcThrows(rpcName, _pgError('P0001', message: 'Quota exceeded'));
      expect(
        () => repo.createOrganization(_createOrgCmd()),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.message,
            'msg',
            'Quota exceeded',
          ),
        ),
      );
    });

    test(
      'maps 22P02 invalid UUID → ResourceNotFoundException (INV-26)',
      () async {
        stubRpcThrows(rpcName, _pgError('22P02'));
        expect(
          () => repo.createOrganization(_createOrgCmd()),
          throwsA(isA<ResourceNotFoundException>()),
        );
      },
    );

    test(
      'maps 23503 FK violation → ResourceNotFoundException (INV-26)',
      () async {
        stubRpcThrows(rpcName, _pgError('23503'));
        expect(
          () => repo.createOrganization(_createOrgCmd()),
          throwsA(isA<ResourceNotFoundException>()),
        );
      },
    );

    test(
      'maps 42501 insufficient_privilege → SovereigntyViolationException',
      () async {
        stubRpcThrows(rpcName, _pgError('42501'));
        expect(
          () => repo.createOrganization(_createOrgCmd()),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );

    test(
      'rethrows unknown PostgrestException codes (fail-fast INV-10)',
      () async {
        final unknown = _pgError('XX000', message: 'internal error');
        stubRpcThrows(rpcName, unknown);
        expect(
          () => repo.createOrganization(_createOrgCmd()),
          throwsA(same(unknown)),
        );
      },
    );

    test(
      'type cast failure when RPC returns non-String throws TypeError',
      () async {
        stubRpc(rpcName, 12345); // int instead of String
        expect(
          () => repo.createOrganization(_createOrgCmd()),
          throwsA(isA<TypeError>()),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // inviteFirstAdmin
  // ═══════════════════════════════════════════════════════════════════════════
  group('inviteFirstAdmin', () {
    const rpcName = 'super_admin_invite_first_admin';
    final expiresAt = DateTime.utc(2026, 6, 1);

    Future<void> call() => repo.inviteFirstAdmin(
      orgId: _kOrgId,
      email: _kEmail,
      token: _kToken,
      invitationId: _kInvitationId,
      expiresAtUtc: expiresAt,
      superAdminUserId: _kUserId,
    );

    test('completes successfully on valid RPC response', () async {
      stubRpc(rpcName, null);
      await expectLater(call(), completes);
    });

    test('passes correct params including ISO8601 date', () async {
      stubRpc(rpcName, null);
      await call();

      final captured =
          verify(
                () => mockClient.rpc<dynamic>(
                  rpcName,
                  params: captureAny(named: 'params'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['p_org_id'], _kOrgId);
      expect(captured['p_email'], _kEmail);
      expect(captured['p_role'], 'TENANT_ADMIN');
      expect(captured['p_expires_at'], expiresAt.toIso8601String());
    });

    test('maps PGRST116 → ResourceNotFoundException', () async {
      stubRpcThrows(rpcName, _pgError('PGRST116'));
      expect(call, throwsA(isA<ResourceNotFoundException>()));
    });

    test('maps 42501 → SovereigntyViolationException (RBAC)', () async {
      stubRpcThrows(rpcName, _pgError('42501'));
      expect(call, throwsA(isA<SovereigntyViolationException>()));
    });

    test('maps 23505 duplicate invite → IntegrityException', () async {
      stubRpcThrows(
        rpcName,
        _pgError(
          '23505',
          details: 'Key (email)=(admin@acme.com) already exists.',
        ),
      );
      expect(
        call,
        throwsA(
          isA<IntegrityException>().having((e) => e.field, 'field', 'email'),
        ),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // checkCnpjExists
  // ═══════════════════════════════════════════════════════════════════════════
  group('checkCnpjExists', () {
    const rpcName = 'super_admin_check_cnpj_exists';

    test('returns true when CNPJ exists', () async {
      stubRpc(rpcName, true);
      expect(await repo.checkCnpjExists('12345678000190'), isTrue);
    });

    test('returns false when CNPJ does not exist', () async {
      stubRpc(rpcName, false);
      expect(await repo.checkCnpjExists('00000000000000'), isFalse);
    });

    test('maps P0001 → IntegrityException', () async {
      stubRpcThrows(rpcName, _pgError('P0001', message: 'Invalid CNPJ format'));
      expect(
        () => repo.checkCnpjExists('invalid'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test(
      'type cast failure when RPC returns non-bool throws TypeError',
      () async {
        stubRpc(rpcName, 'not-a-bool');
        expect(
          () => repo.checkCnpjExists('12345678000190'),
          throwsA(isA<TypeError>()),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getAllTenantHealth (Edge Function)
  // ═══════════════════════════════════════════════════════════════════════════
  group('getAllTenantHealth', () {
    Map<String, dynamic> validRow() => {
      'id': _kOrgId,
      'name': 'Acme',
      'is_active': true,
      'max_vehicles': 50,
      'max_active_contracts': 10,
      'active_contract_count': 3,
      'open_critical_alert_count': 0,
      'dwell_time_seconds': 300,
    };

    test('parses valid response into TenantHealthSnapshot list', () async {
      stubEdgeFn({
        'data': [validRow(), validRow()],
      });
      final result = await repo.getAllTenantHealth();
      expect(result, hasLength(2));
      expect(result.first.id, _kOrgId);
      expect(result.first.name, 'Acme');
    });

    test('returns empty list when data is empty', () async {
      stubEdgeFn({'data': <dynamic>[]});
      final result = await repo.getAllTenantHealth();
      expect(result, isEmpty);
    });

    test('wraps SocketException in DomainException (Availability)', () async {
      stubEdgeFnThrows(const SocketException('Connection refused'));
      expect(
        () => repo.getAllTenantHealth(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'msg',
            contains('unavailable'),
          ),
        ),
      );
    });

    test('wraps HttpException in DomainException', () async {
      stubEdgeFnThrows(const HttpException('503 Service Unavailable'));
      expect(() => repo.getAllTenantHealth(), throwsA(isA<DomainException>()));
    });

    test('wraps FormatException (malformed JSON) in DomainException', () async {
      stubEdgeFnThrows(const FormatException('Unexpected character'));
      expect(() => repo.getAllTenantHealth(), throwsA(isA<DomainException>()));
    });

    test(
      'null data field causes TypeError wrapped in DomainException',
      () async {
        stubEdgeFn(
          null,
        ); // response.data is null → cast fails → caught by on Object
        expect(
          () => repo.getAllTenantHealth(),
          throwsA(isA<DomainException>()),
        );
      },
    );

    test(
      'missing "data" key causes TypeError wrapped in DomainException',
      () async {
        stubEdgeFn({
          'result': <dynamic>[],
        }); // no 'data' key → null cast → caught by on Object
        expect(
          () => repo.getAllTenantHealth(),
          throwsA(isA<DomainException>()),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getSystemAuditLog (Edge Function)
  // ═══════════════════════════════════════════════════════════════════════════
  group('getSystemAuditLog', () {
    Map<String, dynamic> validEntry() => {
      'severity': 'critical',
      'event_type': 'ORG_CREATED',
      'occurred_at': '2026-05-01T00:00:00Z',
      'organization_id': _kOrgId,
    };

    test('parses valid response into SystemAuditLogEntry list', () async {
      stubEdgeFn({
        'data': [validEntry()],
      });
      final result = await repo.getSystemAuditLog();
      expect(result, hasLength(1));
      expect(result.first.eventType, 'ORG_CREATED');
    });

    test('passes optional filters in params', () async {
      stubEdgeFn({'data': <dynamic>[]});
      final from = DateTime.utc(2026, 1, 1);
      final to = DateTime.utc(2026, 5, 1);

      await repo.getSystemAuditLog(
        organizationId: _kOrgId,
        severity: 'critical',
        fromDate: from,
        toDate: to,
        limit: 50,
      );

      final captured =
          verify(
                () => mockFunctions.invoke(
                  'super-admin-proxy',
                  body: captureAny(named: 'body'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      final params = captured['params'] as Map<String, dynamic>;
      expect(params['organization_id'], _kOrgId);
      expect(params['severity'], 'critical');
      expect(params['from_date'], from.toIso8601String());
      expect(params['to_date'], to.toIso8601String());
      expect(params['limit'], 50);
    });

    test('omits null optional params from body', () async {
      stubEdgeFn({'data': <dynamic>[]});
      await repo.getSystemAuditLog();

      final captured =
          verify(
                () => mockFunctions.invoke(
                  'super-admin-proxy',
                  body: captureAny(named: 'body'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      final params = captured['params'] as Map<String, dynamic>;
      expect(params.containsKey('organization_id'), isFalse);
      expect(params.containsKey('severity'), isFalse);
      expect(params['limit'], 100); // default
    });

    test('wraps network failure in DomainException', () async {
      stubEdgeFnThrows(const SocketException('timeout'));
      expect(() => repo.getSystemAuditLog(), throwsA(isA<DomainException>()));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getTenantTechnicalHealth (Edge Function)
  // ═══════════════════════════════════════════════════════════════════════════
  group('getTenantTechnicalHealth', () {
    test('returns parsed map on success', () async {
      final payload = {'replication_lag_ms': 12, 'schema_valid': true};
      stubEdgeFn({'data': payload});
      final result = await repo.getTenantTechnicalHealth(_kOrgId);
      expect(result['replication_lag_ms'], 12);
    });

    test('passes organization_id in params', () async {
      stubEdgeFn({'data': <String, dynamic>{}});
      await repo.getTenantTechnicalHealth(_kOrgId);

      final captured =
          verify(
                () => mockFunctions.invoke(
                  'super-admin-proxy',
                  body: captureAny(named: 'body'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['action'], 'get_tenant_technical_health');
      expect((captured['params'] as Map)['organization_id'], _kOrgId);
    });

    test('wraps Exception in DomainException', () async {
      stubEdgeFnThrows(Exception('500 Internal Server Error'));
      expect(
        () => repo.getTenantTechnicalHealth(_kOrgId),
        throwsA(isA<DomainException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getEvidenceVolume (Edge Function)
  // ═══════════════════════════════════════════════════════════════════════════
  group('getEvidenceVolume', () {
    test('returns parsed map on success', () async {
      final payload = {'total': 1500, 'current_month': 42};
      stubEdgeFn({'data': payload});
      final result = await repo.getEvidenceVolume(_kOrgId);
      expect(result['total'], 1500);
    });

    test('wraps timeout in DomainException', () async {
      stubEdgeFnThrows(const SocketException('Connection timed out'));
      expect(
        () => repo.getEvidenceVolume(_kOrgId),
        throwsA(isA<DomainException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // checkSchemaIntegrity (Edge Function)
  // ═══════════════════════════════════════════════════════════════════════════
  group('checkSchemaIntegrity', () {
    test('returns parsed map on success', () async {
      final payload = {'tables_ok': 42, 'drift_detected': false};
      stubEdgeFn({'data': payload});
      final result = await repo.checkSchemaIntegrity(_kOrgId);
      expect(result['drift_detected'], isFalse);
    });

    test(
      'wraps Exception in DomainException without leaking details',
      () async {
        stubEdgeFnThrows(Exception('secret_key=abc123'));
        expect(
          () => repo.checkSchemaIntegrity(_kOrgId),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'msg',
              contains('unavailable'),
            ),
          ),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateOrganizationQuota
  // ═══════════════════════════════════════════════════════════════════════════
  group('updateOrganizationQuota', () {
    const rpcName = 'super_admin_update_organization_quota';

    test('completes successfully', () async {
      stubRpc(rpcName, null);
      await expectLater(
        repo.updateOrganizationQuota(_updateQuotaCmd()),
        completes,
      );
    });

    test('passes expectedUpdatedAt as ISO8601', () async {
      stubRpc(rpcName, null);
      await repo.updateOrganizationQuota(_updateQuotaCmd());

      final captured =
          verify(
                () => mockClient.rpc<dynamic>(
                  rpcName,
                  params: captureAny(named: 'params'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['p_expected_updated_at'], '2026-05-01T00:00:00.000Z');
    });

    test('maps P0001 (OCC conflict) → IntegrityException', () async {
      stubRpcThrows(
        rpcName,
        _pgError('P0001', message: 'Concurrent modification detected'),
      );
      expect(
        () => repo.updateOrganizationQuota(_updateQuotaCmd()),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.message,
            'msg',
            contains('Concurrent'),
          ),
        ),
      );
    });

    test('maps 42501 → SovereigntyViolationException', () async {
      stubRpcThrows(rpcName, _pgError('42501'));
      expect(
        () => repo.updateOrganizationQuota(_updateQuotaCmd()),
        throwsA(isA<SovereigntyViolationException>()),
      );
    });

    test('rethrows unknown code', () async {
      final err = _pgError('42P01', message: 'undefined_table');
      stubRpcThrows(rpcName, err);
      expect(
        () => repo.updateOrganizationQuota(_updateQuotaCmd()),
        throwsA(same(err)),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // archiveOrganization
  // ═══════════════════════════════════════════════════════════════════════════
  group('archiveOrganization', () {
    const rpcName = 'super_admin_archive_organization';

    test('completes successfully', () async {
      stubRpc(rpcName, null);
      await expectLater(repo.archiveOrganization(_archiveCmd()), completes);
    });

    test('maps PGRST116 not found → ResourceNotFoundException', () async {
      stubRpcThrows(rpcName, _pgError('PGRST116'));
      expect(
        () => repo.archiveOrganization(_archiveCmd()),
        throwsA(isA<ResourceNotFoundException>()),
      );
    });

    test('maps P0001 (already archived) → IntegrityException', () async {
      stubRpcThrows(rpcName, _pgError('P0001', message: 'Already archived'));
      expect(
        () => repo.archiveOrganization(_archiveCmd()),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // unarchiveOrganization
  // ═══════════════════════════════════════════════════════════════════════════
  group('unarchiveOrganization', () {
    const rpcName = 'super_admin_unarchive_organization';

    Future<void> call() => repo.unarchiveOrganization(
      orgId: _kOrgId,
      reason: 'Client reactivated',
      superAdminId: _kUserId,
    );

    test('completes successfully', () async {
      stubRpc(rpcName, null);
      await expectLater(call(), completes);
    });

    test('maps 42501 → SovereigntyViolationException', () async {
      stubRpcThrows(rpcName, _pgError('42501'));
      expect(call, throwsA(isA<SovereigntyViolationException>()));
    });

    test('maps PGRST116 → ResourceNotFoundException', () async {
      stubRpcThrows(rpcName, _pgError('PGRST116'));
      expect(call, throwsA(isA<ResourceNotFoundException>()));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // getTenantMembers
  // ═══════════════════════════════════════════════════════════════════════════
  group('getTenantMembers', () {
    const rpcName = 'super_admin_get_org_members';

    test('returns list of member maps', () async {
      stubRpc(rpcName, [
        {'user_id': 'u1', 'email': 'a@b.com', 'is_active': true},
        {'user_id': 'u2', 'email': 'c@d.com', 'is_active': false},
      ]);
      final result = await repo.getTenantMembers(_kOrgId);
      expect(result, hasLength(2));
      expect(result.first['user_id'], 'u1');
    });

    test('returns empty list when no members', () async {
      stubRpc(rpcName, <dynamic>[]);
      final result = await repo.getTenantMembers(_kOrgId);
      expect(result, isEmpty);
    });

    test('maps 22P02 invalid UUID → ResourceNotFoundException', () async {
      stubRpcThrows(rpcName, _pgError('22P02'));
      expect(
        () => repo.getTenantMembers('not-a-uuid'),
        throwsA(isA<ResourceNotFoundException>()),
      );
    });

    test('maps 42501 → SovereigntyViolationException', () async {
      stubRpcThrows(rpcName, _pgError('42501'));
      expect(
        () => repo.getTenantMembers(_kOrgId),
        throwsA(isA<SovereigntyViolationException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // toggleTenantMemberStatus
  // ═══════════════════════════════════════════════════════════════════════════
  group('toggleTenantMemberStatus', () {
    const rpcName = 'super_admin_toggle_member_status';

    Future<void> call({bool isActive = false}) => repo.toggleTenantMemberStatus(
      orgId: _kOrgId,
      userId: _kUserId,
      isActive: isActive,
    );

    test('completes successfully', () async {
      stubRpc(rpcName, null);
      await expectLater(call(isActive: true), completes);
    });

    test('passes correct params', () async {
      stubRpc(rpcName, null);
      await call(isActive: true);

      final captured =
          verify(
                () => mockClient.rpc<dynamic>(
                  rpcName,
                  params: captureAny(named: 'params'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['p_org_id'], _kOrgId);
      expect(captured['p_user_id'], _kUserId);
      expect(captured['p_is_active'], isTrue);
    });

    test('maps PGRST116 → ResourceNotFoundException', () async {
      stubRpcThrows(rpcName, _pgError('PGRST116'));
      expect(call, throwsA(isA<ResourceNotFoundException>()));
    });

    test('maps P0001 → IntegrityException', () async {
      stubRpcThrows(
        rpcName,
        _pgError('P0001', message: 'Cannot deactivate last admin'),
      );
      expect(
        call,
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.message,
            'msg',
            contains('last admin'),
          ),
        ),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // resendInvitation (Edge Function — rethrow)
  // ═══════════════════════════════════════════════════════════════════════════
  group('resendInvitation', () {
    const rpcName = 'super_admin_audit_resend_invitation';

    Future<void> call() => repo.resendInvitation(
      email: _kEmail,
      orgName: 'Acme',
      orgId: _kOrgId,
      reason: 'User did not receive email',
    );

    test('completes successfully', () async {
      stubRpc(rpcName, null);
      when(
        () => mockFunctions.invoke('notify-invite', body: any(named: 'body')),
      ).thenAnswer((_) async => _fnOk({'sent': true}));
      await expectLater(call(), completes);
    });

    test('calls audit RPC before notify edge function', () async {
      stubRpc(rpcName, null);
      when(
        () => mockFunctions.invoke('notify-invite', body: any(named: 'body')),
      ).thenAnswer((_) async => _fnOk({'sent': true}));
      await call();

      final captured =
          verify(
                () => mockClient.rpc<dynamic>(
                  rpcName,
                  params: captureAny(named: 'params'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['p_org_id'], _kOrgId);
      expect(captured['p_email'], _kEmail);
      expect(captured['p_reason'], 'User did not receive email');
    });

    test('wraps non-Postgrest exceptions as DomainException', () async {
      stubRpc(rpcName, null);
      const error = SocketException('Connection refused');
      when(
        () => mockFunctions.invoke('notify-invite', body: any(named: 'body')),
      ).thenThrow(error);
      expect(call, throwsA(isA<DomainException>()));
    });

    test('wraps FunctionException on 500 as DomainException', () async {
      stubRpc(rpcName, null);
      const error = FunctionException(
        status: 500,
        details: 'Internal Server Error',
      );
      when(
        () => mockFunctions.invoke('notify-invite', body: any(named: 'body')),
      ).thenThrow(error);
      expect(call, throwsA(isA<DomainException>()));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // addAdminToOrganization (custom P0005/P0006 handling)
  // ═══════════════════════════════════════════════════════════════════════════
  group('addAdminToOrganization', () {
    const rpcName = 'super_admin_add_org_admin';
    final expiresAt = DateTime.utc(2026, 6, 1);

    Future<void> call({String email = _kEmail}) => repo.addAdminToOrganization(
      orgId: _kOrgId,
      email: email,
      invitationId: _kInvitationId,
      token: _kToken,
      expiresAtUtc: expiresAt,
      superAdminUserId: _kUserId,
      reason: 'New admin needed',
    );

    test('completes successfully', () async {
      stubRpc(rpcName, null);
      await expectLater(call(), completes);
    });

    test('passes reason to RPC', () async {
      stubRpc(rpcName, null);
      await call();

      final captured =
          verify(
                () => mockClient.rpc<dynamic>(
                  rpcName,
                  params: captureAny(named: 'params'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['p_reason'], 'New admin needed');
    });

    test('P0005 → DomainException with pending invite message', () async {
      stubRpcThrows(rpcName, _pgError('P0005', message: 'pending invite'));
      expect(
        call,
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'msg',
            contains('convite pendente'),
          ),
        ),
      );
    });

    test('P0005 includes email in error message', () async {
      stubRpcThrows(rpcName, _pgError('P0005'));
      expect(
        () => call(email: 'test@org.com'),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'msg',
            contains('test@org.com'),
          ),
        ),
      );
    });

    test('P0006 → DomainException with active profile message', () async {
      stubRpcThrows(rpcName, _pgError('P0006', message: 'already active'));
      expect(
        call,
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'msg',
            contains('perfil ativo'),
          ),
        ),
      );
    });

    test('P0006 includes email in error message', () async {
      stubRpcThrows(rpcName, _pgError('P0006'));
      expect(
        () => call(email: 'existing@org.com'),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'msg',
            contains('existing@org.com'),
          ),
        ),
      );
    });

    test('other codes fall through to interceptor (23505)', () async {
      stubRpcThrows(
        rpcName,
        _pgError('23505', details: 'Key (email)=(x) already exists.'),
      );
      expect(call, throwsA(isA<IntegrityException>()));
    });

    test('other codes fall through to interceptor (42501)', () async {
      stubRpcThrows(rpcName, _pgError('42501'));
      expect(call, throwsA(isA<SovereigntyViolationException>()));
    });

    test('unknown code rethrows PostgrestException', () async {
      final err = _pgError('XX001');
      stubRpcThrows(rpcName, err);
      expect(call, throwsA(same(err)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // revokeInvitation (custom P0008 handling)
  // ═══════════════════════════════════════════════════════════════════════════
  group('revokeInvitation', () {
    const rpcName = 'super_admin_revoke_invitation';

    Future<void> call({String email = _kEmail}) => repo.revokeInvitation(
      orgId: _kOrgId,
      email: email,
      superAdminUserId: _kUserId,
      reason: 'Admin no longer needed',
    );

    test('completes successfully', () async {
      stubRpc(rpcName, null);
      await expectLater(call(), completes);
    });

    test('passes reason to RPC', () async {
      stubRpc(rpcName, null);
      await call();

      final captured =
          verify(
                () => mockClient.rpc<dynamic>(
                  rpcName,
                  params: captureAny(named: 'params'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['p_reason'], 'Admin no longer needed');
    });

    test('P0008 → DomainException with no pending invite message', () async {
      stubRpcThrows(rpcName, _pgError('P0008'));
      expect(
        call,
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'msg',
            contains('Nenhum convite pendente'),
          ),
        ),
      );
    });

    test('P0008 includes email in error message', () async {
      stubRpcThrows(rpcName, _pgError('P0008'));
      expect(
        () => call(email: 'ghost@org.com'),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'msg',
            contains('ghost@org.com'),
          ),
        ),
      );
    });

    test('other codes fall through to interceptor (PGRST116)', () async {
      stubRpcThrows(rpcName, _pgError('PGRST116'));
      expect(call, throwsA(isA<ResourceNotFoundException>()));
    });

    test('other codes fall through to interceptor (42501)', () async {
      stubRpcThrows(rpcName, _pgError('42501'));
      expect(call, throwsA(isA<SovereigntyViolationException>()));
    });

    test('unknown code rethrows', () async {
      final err = _pgError('57014', message: 'statement_timeout');
      stubRpcThrows(rpcName, err);
      expect(call, throwsA(same(err)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // updateAllowedDomains (domain normalization logic)
  // ═══════════════════════════════════════════════════════════════════════════
  group('updateAllowedDomains', () {
    const rpcName = 'super_admin_update_allowed_domains';

    Future<void> call(List<String> domains) =>
        repo.updateAllowedDomains(_kOrgId, domains, _kUserId);

    test('completes successfully', () async {
      stubRpc(rpcName, null);
      await expectLater(call(['acme.com']), completes);
    });

    test('normalizes domains: lowercase + trim', () async {
      stubRpc(rpcName, null);
      await call([' ACME.COM ', '  Beta.IO']);

      final captured =
          verify(
                () => mockClient.rpc<dynamic>(
                  rpcName,
                  params: captureAny(named: 'params'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      final domains = captured['p_allowed_domains'] as List;
      expect(domains, containsAll(['acme.com', 'beta.io']));
    });

    test('deduplicates domains', () async {
      stubRpc(rpcName, null);
      await call(['acme.com', 'ACME.COM', ' acme.com ']);

      final captured =
          verify(
                () => mockClient.rpc<dynamic>(
                  rpcName,
                  params: captureAny(named: 'params'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      final domains = captured['p_allowed_domains'] as List;
      expect(domains, hasLength(1));
      expect(domains.first, 'acme.com');
    });

    test('passes empty list when no domains', () async {
      stubRpc(rpcName, null);
      await call([]);

      final captured =
          verify(
                () => mockClient.rpc<dynamic>(
                  rpcName,
                  params: captureAny(named: 'params'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['p_allowed_domains'], isEmpty);
    });

    test('maps 42501 → SovereigntyViolationException', () async {
      stubRpcThrows(rpcName, _pgError('42501'));
      expect(
        () => call(['x.com']),
        throwsA(isA<SovereigntyViolationException>()),
      );
    });

    test('maps P0001 → IntegrityException', () async {
      stubRpcThrows(
        rpcName,
        _pgError('P0001', message: 'Invalid domain format'),
      );
      expect(() => call(['not valid']), throwsA(isA<IntegrityException>()));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ADVERSARIAL SCENARIOS — CIA Triad & Resilience
  // ═══════════════════════════════════════════════════════════════════════════
  group('Adversarial: CIA Triad & Resilience', () {
    group('Confidentiality — RBAC/JWT enforcement', () {
      test('42501 on any RPC never leaks DB error details', () async {
        stubRpcThrows(
          'super_admin_create_organization',
          _pgError(
            '42501',
            message: 'permission denied for table organizations',
          ),
        );
        try {
          await repo.createOrganization(_createOrgCmd());
        } on SovereigntyViolationException catch (e) {
          // toString() must NOT contain table names
          expect(e.toString(), isNot(contains('organizations')));
          expect(e.toString(), isNot(contains('permission denied')));
        }
      });

      test(
        'ResourceNotFoundException never leaks resource details in toString',
        () async {
          stubRpcThrows(
            'super_admin_archive_organization',
            _pgError(
              '22P02',
              message: 'invalid input syntax for type uuid: "attack-probe"',
            ),
          );
          try {
            await repo.archiveOrganization(_archiveCmd());
          } on ResourceNotFoundException catch (e) {
            expect(e.toString(), isNot(contains('attack-probe')));
            expect(e.toString(), isNot(contains('uuid')));
          }
        },
      );
    });

    group('Integrity — parameter validation', () {
      test('createOrganization passes all params to RPC', () async {
        stubRpc('super_admin_create_organization', _kOrgId);
        final cmd = _createOrgCmd();
        await repo.createOrganization(cmd);

        final captured =
            verify(
                  () => mockClient.rpc<dynamic>(
                    'super_admin_create_organization',
                    params: captureAny(named: 'params'),
                  ),
                ).captured.single
                as Map<String, dynamic>;

        expect(captured['p_legal_name'], cmd.legalName);
        expect(captured['p_trade_name'], cmd.tradeName);
        expect(captured['p_timezone'], cmd.timezone);
        expect(captured['p_currency_code'], cmd.currencyCode);
        expect(captured['p_plan_type'], cmd.planType.name);
        expect(captured['p_max_vehicles'], cmd.maxVehicles);
        expect(captured['p_max_active_contracts'], cmd.maxActiveContracts);
        expect(captured['p_super_admin_user_id'], cmd.superAdminUserId);
        expect(captured['p_tool_cost_cents'], cmd.toolCostCents);
        expect(captured['p_dwell_time_seconds'], cmd.dwellTimeSeconds);
        expect(captured['p_billing_day'], cmd.billingDay);
        expect(captured['p_contact_email'], cmd.contactEmail);
        expect(captured['p_external_id'], cmd.externalId);
        expect(captured['p_reason'], cmd.reason);
        expect(captured['p_organization_type'], cmd.organizationType);
        expect(captured['p_allowed_domains'], cmd.allowedDomains);
      });
    });

    group('Availability — network failures', () {
      test('SocketException on Edge Function → DomainException', () async {
        stubEdgeFnThrows(const SocketException('Network unreachable'));
        expect(
          () => repo.getAllTenantHealth(),
          throwsA(isA<DomainException>()),
        );
      });

      test('HttpException on Edge Function → DomainException', () async {
        stubEdgeFnThrows(const HttpException('503'));
        expect(
          () => repo.getEvidenceVolume(_kOrgId),
          throwsA(isA<DomainException>()),
        );
      });
    });

    group('Type safety — malformed responses', () {
      test(
        'Edge Function returns list instead of map → DomainException',
        () async {
          stubEdgeFn([1, 2, 3]); // List instead of Map → caught by on Object
          expect(
            () => repo.getTenantTechnicalHealth(_kOrgId),
            throwsA(isA<DomainException>()),
          );
        },
      );

      test(
        'Edge Function returns string instead of map → DomainException',
        () async {
          stubEdgeFn('unexpected string'); // caught by on Object
          expect(
            () => repo.checkSchemaIntegrity(_kOrgId),
            throwsA(isA<DomainException>()),
          );
        },
      );

      test(
        'RPC returns list instead of String for createOrganization',
        () async {
          stubRpc('super_admin_create_organization', ['unexpected', 'list']);
          expect(
            () => repo.createOrganization(_createOrgCmd()),
            throwsA(isA<TypeError>()),
          );
        },
      );

      test('RPC returns null for checkCnpjExists → TypeError', () async {
        stubRpc('super_admin_check_cnpj_exists', null);
        expect(
          () => repo.checkCnpjExists('12345678000190'),
          throwsA(isA<TypeError>()),
        );
      });
    });

    group('Concurrency — race condition error handling', () {
      test('P0001 OCC conflict on updateOrganizationQuota', () async {
        stubRpcThrows(
          'super_admin_update_organization_quota',
          _pgError('P0001', message: 'Row was modified by another transaction'),
        );
        expect(
          () => repo.updateOrganizationQuota(_updateQuotaCmd()),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'msg',
              contains('another transaction'),
            ),
          ),
        );
      });

      test('23505 race on archiveOrganization → IntegrityException', () async {
        stubRpcThrows(
          'super_admin_archive_organization',
          _pgError('23505', details: 'Key (org_id)=($_kOrgId) already exists.'),
        );
        expect(
          () => repo.archiveOrganization(_archiveCmd()),
          throwsA(
            isA<IntegrityException>().having((e) => e.field, 'field', 'org_id'),
          ),
        );
      });
    });
  });
}
