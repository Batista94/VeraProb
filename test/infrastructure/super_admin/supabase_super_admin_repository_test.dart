/// Unit tests for [SupabaseSuperAdminRepository].
///
/// Covers RPC delegation, Edge Function proxy paths, IntegrityException
/// invariants on createOrganization (INV-28), and PostgrestException mapping
/// (INV-26).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Resolves to [_result] when awaited — mirrors PostgREST's PostgrestFilterBuilder.
class FakePostgrestFilterBuilder extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  final dynamic _result;

  FakePostgrestFilterBuilder(this._result);

  @override
  Future<S> then<S>(
    FutureOr<S> Function(dynamic value) onValue, {
    Function? onError,
  }) => Future<dynamic>.value(_result).then(onValue, onError: onError);

  @override
  Future<dynamic> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => Future<dynamic>.value(_result);

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) =>
      Future<dynamic>.value(_result).whenComplete(action);

  @override
  Stream<dynamic> asStream() => Stream.value(_result);

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) => Future<dynamic>.value(_result);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

PostgrestException _pgError(String code, {String message = 'db error'}) =>
    PostgrestException(message: message, code: code);

// ── File-level state ──────────────────────────────────────────────────────────

late MockSupabaseClient _mockClient;
late MockFunctionsClient _mockFunctions;
late SupabaseSuperAdminRepository _repo;

// ── Test groups ───────────────────────────────────────────────────────────────

void _testCreateOrganization() {
  group('createOrganization', () {
    const cmd = CreateOrganizationCommand(
      legalName: 'Acme Ltda',
      tradeName: 'Acme',
      cnpj: '12.345.678/0001-90',
      timezone: 'America/Sao_Paulo',
      currencyCode: 'BRL',
      planType: PlanType.starter,
      adminEmails: ['admin@acme.com'],
      superAdminUserId: 'sa-uuid',
      reason: 'onboarding',
    );

    void stubRpc(dynamic result) {
      when(
        () => _mockClient.rpc<dynamic>(
          'super_admin_create_organization',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(result));
    }

    test('returns orgId and plaintextSecret on success', () async {
      stubRpc([
        {'org_id': 'org-1', 'plaintext_secret': 'abc123'},
      ]);

      final result = await _repo.createOrganization(cmd);

      expect(result.orgId, 'org-1');
      expect(result.plaintextSecret, 'abc123');
    });

    test('strips CNPJ formatting before sending to RPC', () async {
      stubRpc([
        {'org_id': 'org-2', 'plaintext_secret': 'secret'},
      ]);

      await _repo.createOrganization(cmd);

      final captured =
          verify(
                () => _mockClient.rpc<dynamic>(
                  'super_admin_create_organization',
                  params: captureAny(named: 'params'),
                ),
              ).captured.first
              as Map<String, dynamic>;
      expect(captured['p_cnpj'], '12345678000190');
    });

    test('throws IntegrityException when RPC returns empty list', () async {
      stubRpc(<dynamic>[]);

      await expectLater(
        _repo.createOrganization(cmd),
        throwsA(
          isA<IntegrityException>().having((e) => e.field, 'field', 'org_id'),
        ),
      );
    });

    test('throws IntegrityException when org_id is null', () async {
      stubRpc([
        {'org_id': null, 'plaintext_secret': 'secret'},
      ]);

      await expectLater(
        _repo.createOrganization(cmd),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('throws IntegrityException when org_id is empty string', () async {
      stubRpc([
        {'org_id': '', 'plaintext_secret': 'secret'},
      ]);

      await expectLater(
        _repo.createOrganization(cmd),
        throwsA(
          isA<IntegrityException>().having((e) => e.field, 'field', 'org_id'),
        ),
      );
    });

    test(
      'throws IntegrityException (INV-28) when plaintext_secret is null',
      () async {
        stubRpc([
          {'org_id': 'org-3', 'plaintext_secret': null},
        ]);

        await expectLater(
          _repo.createOrganization(cmd),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.field,
              'field',
              'plaintext_secret',
            ),
          ),
        );
      },
    );

    test(
      'throws IntegrityException (INV-28) when plaintext_secret is empty',
      () async {
        stubRpc([
          {'org_id': 'org-4', 'plaintext_secret': ''},
        ]);

        await expectLater(
          _repo.createOrganization(cmd),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.field,
              'field',
              'plaintext_secret',
            ),
          ),
        );
      },
    );

    test('maps PostgrestException P0001 → IntegrityException', () async {
      when(
        () => _mockClient.rpc<dynamic>(
          'super_admin_create_organization',
          params: any(named: 'params'),
        ),
      ).thenThrow(_pgError('P0001', message: 'CNPJ already registered'));

      await expectLater(
        _repo.createOrganization(cmd),
        throwsA(isA<IntegrityException>()),
      );
    });

    test(
      'maps PostgrestException 42501 → SovereigntyViolationException',
      () async {
        when(
          () => _mockClient.rpc<dynamic>(
            'super_admin_create_organization',
            params: any(named: 'params'),
          ),
        ).thenThrow(_pgError('42501'));

        await expectLater(
          _repo.createOrganization(cmd),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );

    test('maps PostgrestException 22P02 → ResourceNotFoundException', () async {
      when(
        () => _mockClient.rpc<dynamic>(
          'super_admin_create_organization',
          params: any(named: 'params'),
        ),
      ).thenThrow(_pgError('22P02'));

      await expectLater(
        _repo.createOrganization(cmd),
        throwsA(isA<ResourceNotFoundException>()),
      );
    });
  });
}

void _testCheckCnpjExists() {
  group('checkCnpjExists', () {
    void stubRpc(dynamic result) {
      when(
        () => _mockClient.rpc<dynamic>(
          'super_admin_check_cnpj_exists',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(result));
    }

    test('returns true when CNPJ exists', () async {
      stubRpc(true);
      expect(await _repo.checkCnpjExists('12345678000190'), isTrue);
    });

    test('returns false when CNPJ does not exist', () async {
      stubRpc(false);
      expect(await _repo.checkCnpjExists('99999999000191'), isFalse);
    });

    test('maps PostgrestException to domain exception', () async {
      when(
        () => _mockClient.rpc<dynamic>(
          'super_admin_check_cnpj_exists',
          params: any(named: 'params'),
        ),
      ).thenThrow(_pgError('PGRST116'));

      await expectLater(
        _repo.checkCnpjExists('00000000000000'),
        throwsA(isA<ResourceNotFoundException>()),
      );
    });
  });
}

void _testGetAllTenantHealth() {
  group('getAllTenantHealth', () {
    test('returns parsed TenantHealthSnapshot list', () async {
      when(
        () => _mockFunctions.invoke(
          'super-admin-proxy',
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          status: 200,
          data: {
            'data': [
              {
                'id': 'org-1',
                'name': 'Acme',
                'is_active': true,
                'max_vehicles': 10,
                'max_active_contracts': 5,
                'active_contract_count': 2,
                'open_critical_alert_count': 0,
              },
            ],
          },
        ),
      );

      final result = await _repo.getAllTenantHealth();

      expect(result, hasLength(1));
      expect(result.first.id, 'org-1');
      expect(result.first.name, 'Acme');
    });

    test('wraps Edge Function error in DomainException', () async {
      when(
        () => _mockFunctions.invoke(
          'super-admin-proxy',
          body: any(named: 'body'),
        ),
      ).thenThrow(Exception('network failure'));

      await expectLater(
        _repo.getAllTenantHealth(),
        throwsA(isA<DomainException>()),
      );
    });
  });
}

void _testGetSystemAuditLog() {
  group('getSystemAuditLog', () {
    test('returns parsed SystemAuditLogEntry list', () async {
      when(
        () => _mockFunctions.invoke(
          'super-admin-proxy',
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          status: 200,
          data: {
            'data': [
              {
                'severity': 'info',
                'event_type': 'ORG_CREATED',
                'occurred_at': '2026-01-01T00:00:00Z',
              },
            ],
          },
        ),
      );

      final result = await _repo.getSystemAuditLog();

      expect(result, hasLength(1));
      expect(result.first.eventType, 'ORG_CREATED');
    });

    test('wraps Edge Function error in DomainException', () async {
      when(
        () => _mockFunctions.invoke(
          'super-admin-proxy',
          body: any(named: 'body'),
        ),
      ).thenThrow(Exception('timeout'));

      await expectLater(
        _repo.getSystemAuditLog(),
        throwsA(isA<DomainException>()),
      );
    });
  });
}

void _testUpdateOrganizationQuota() {
  group('updateOrganizationQuota', () {
    const cmd = UpdateOrganizationQuotaCommand(
      organizationId: 'org-1',
      newPlanType: 'professional',
      superAdminUserId: 'sa-uuid',
      sessionId: 'session-1',
    );

    test('calls RPC with correct params', () async {
      when(
        () => _mockClient.rpc<dynamic>(
          'super_admin_update_organization_quota',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(null));

      await _repo.updateOrganizationQuota(cmd);

      verify(
        () => _mockClient.rpc<dynamic>(
          'super_admin_update_organization_quota',
          params: any(named: 'params'),
        ),
      ).called(1);
    });
  });
}

void _testArchiveOrganization() {
  group('archiveOrganization', () {
    const cmd = ArchiveOrganizationCommand(
      orgId: 'org-1',
      reason: 'churn',
      superAdminUserId: 'sa-uuid',
      currentStatus: OrgStatus.active,
      sessionId: 'session-1',
    );

    test('calls super_admin_archive_organization RPC', () async {
      when(
        () => _mockClient.rpc<dynamic>(
          'super_admin_archive_organization',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(null));

      await _repo.archiveOrganization(cmd);

      verify(
        () => _mockClient.rpc<dynamic>(
          'super_admin_archive_organization',
          params: any(named: 'params'),
        ),
      ).called(1);
    });

    test('maps PostgrestException to domain exception', () async {
      when(
        () => _mockClient.rpc<dynamic>(
          'super_admin_archive_organization',
          params: any(named: 'params'),
        ),
      ).thenThrow(_pgError('P0001', message: 'Org not found'));

      await expectLater(
        _repo.archiveOrganization(cmd),
        throwsA(isA<IntegrityException>()),
      );
    });
  });
}

void _testAddAdminToOrganization() {
  group('addAdminToOrganization', () {
    Future<void> callAdd() => _repo.addAdminToOrganization(
      orgId: 'org-1',
      email: 'admin@acme.com',
      invitationId: 'inv-uuid',
      token: 'token-abc',
      expiresAtUtc: DateTime.utc(2026, 12, 31),
      superAdminUserId: 'sa-uuid',
      reason: 'new admin',
    );

    test('calls super_admin_add_org_admin RPC on success', () async {
      when(
        () => _mockClient.rpc<dynamic>(
          'super_admin_add_org_admin',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(null));

      await callAdd();

      verify(
        () => _mockClient.rpc<dynamic>(
          'super_admin_add_org_admin',
          params: any(named: 'params'),
        ),
      ).called(1);
    });

    test(
      'P0005 (pending invite) → DomainException with descriptive message',
      () async {
        when(
          () => _mockClient.rpc<dynamic>(
            'super_admin_add_org_admin',
            params: any(named: 'params'),
          ),
        ).thenThrow(_pgError('P0005'));

        await expectLater(
          callAdd(),
          throwsA(
            isA<DomainException>().having(
              (e) => e.toString(),
              'message',
              contains('convite pendente'),
            ),
          ),
        );
      },
    );

    test(
      'P0006 (active member) → DomainException with descriptive message',
      () async {
        when(
          () => _mockClient.rpc<dynamic>(
            'super_admin_add_org_admin',
            params: any(named: 'params'),
          ),
        ).thenThrow(_pgError('P0006'));

        await expectLater(
          callAdd(),
          throwsA(
            isA<DomainException>().having(
              (e) => e.toString(),
              'message',
              contains('perfil ativo'),
            ),
          ),
        );
      },
    );
  });
}

void _testRevokeInvitation() {
  group('revokeInvitation', () {
    Future<void> callRevoke() => _repo.revokeInvitation(
      orgId: 'org-1',
      email: 'admin@acme.com',
      superAdminUserId: 'sa-uuid',
      reason: 'mistake',
    );

    test('calls super_admin_revoke_invitation RPC on success', () async {
      when(
        () => _mockClient.rpc<dynamic>(
          'super_admin_revoke_invitation',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(null));

      await callRevoke();

      verify(
        () => _mockClient.rpc<dynamic>(
          'super_admin_revoke_invitation',
          params: any(named: 'params'),
        ),
      ).called(1);
    });

    test('P0008 (no pending invite) → DomainException', () async {
      when(
        () => _mockClient.rpc<dynamic>(
          'super_admin_revoke_invitation',
          params: any(named: 'params'),
        ),
      ).thenThrow(_pgError('P0008'));

      await expectLater(
        callRevoke(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.toString(),
            'message',
            contains('convite pendente'),
          ),
        ),
      );
    });
  });
}

void _testUpdateAllowedDomains() {
  group('updateAllowedDomains', () {
    test(
      'normalizes domains: lowercase, trim, deduplicate before RPC',
      () async {
        when(
          () => _mockClient.rpc<dynamic>(
            'super_admin_update_allowed_domains',
            params: any(named: 'params'),
          ),
        ).thenAnswer((_) => FakePostgrestFilterBuilder(null));

        await _repo.updateAllowedDomains('org-1', [
          'ACME.COM',
          ' acme.com ',
          'FLEET.IO',
        ], 'sa-uuid');

        final captured =
            verify(
                  () => _mockClient.rpc<dynamic>(
                    'super_admin_update_allowed_domains',
                    params: captureAny(named: 'params'),
                  ),
                ).captured.first
                as Map<String, dynamic>;
        final domains = captured['p_allowed_domains'] as List<String>;
        expect(domains, hasLength(2));
        expect(domains, containsAll(['acme.com', 'fleet.io']));
      },
    );
  });
}

void _testGetTenantTechnicalHealth() {
  group('getTenantTechnicalHealth', () {
    test('returns data map from Edge Function', () async {
      when(
        () => _mockFunctions.invoke(
          'super-admin-proxy',
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          status: 200,
          data: {
            'data': {'replication_lag_ms': 5, 'schema_ok': true},
          },
        ),
      );

      final result = await _repo.getTenantTechnicalHealth('org-1');
      expect(result['schema_ok'], isTrue);
    });

    test('wraps Edge Function error in DomainException', () async {
      when(
        () => _mockFunctions.invoke(
          'super-admin-proxy',
          body: any(named: 'body'),
        ),
      ).thenThrow(Exception('503'));

      await expectLater(
        _repo.getTenantTechnicalHealth('org-1'),
        throwsA(isA<DomainException>()),
      );
    });
  });
}

void _testGetEvidenceVolume() {
  group('getEvidenceVolume', () {
    test('returns volume metrics map', () async {
      when(
        () => _mockFunctions.invoke(
          'super-admin-proxy',
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          status: 200,
          data: {
            'data': {'total': 1000, 'current_month': 42},
          },
        ),
      );

      final result = await _repo.getEvidenceVolume('org-1');
      expect(result['total'], 1000);
    });

    test('wraps Edge Function error in DomainException', () async {
      when(
        () => _mockFunctions.invoke(
          'super-admin-proxy',
          body: any(named: 'body'),
        ),
      ).thenThrow(Exception('unavailable'));

      await expectLater(
        _repo.getEvidenceVolume('org-1'),
        throwsA(isA<DomainException>()),
      );
    });
  });
}

void _testCheckSchemaIntegrity() {
  group('checkSchemaIntegrity', () {
    test('returns integrity check result map', () async {
      when(
        () => _mockFunctions.invoke(
          'super-admin-proxy',
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          status: 200,
          data: {
            'data': {'ok': true, 'missing_tables': <dynamic>[]},
          },
        ),
      );

      final result = await _repo.checkSchemaIntegrity('org-1');
      expect(result['ok'], isTrue);
    });

    test('wraps Edge Function error in DomainException', () async {
      when(
        () => _mockFunctions.invoke(
          'super-admin-proxy',
          body: any(named: 'body'),
        ),
      ).thenThrow(Exception('edge fn down'));

      await expectLater(
        _repo.checkSchemaIntegrity('org-1'),
        throwsA(isA<DomainException>()),
      );
    });
  });
}

// ── Entry point ───────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    _mockClient = MockSupabaseClient();
    _mockFunctions = MockFunctionsClient();
    when(() => _mockClient.functions).thenReturn(_mockFunctions);
    _repo = SupabaseSuperAdminRepository(_mockClient);
  });

  _testCreateOrganization();
  _testCheckCnpjExists();
  _testGetAllTenantHealth();
  _testGetSystemAuditLog();
  _testUpdateOrganizationQuota();
  _testArchiveOrganization();
  _testAddAdminToOrganization();
  _testRevokeInvitation();
  _testUpdateAllowedDomains();
  _testGetTenantTechnicalHealth();
  _testGetEvidenceVolume();
  _testCheckSchemaIntegrity();
}
