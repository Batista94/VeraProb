import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

import 'package:veraprob/application/super_admin/super_admin_invitation_command_service.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakePostgrestFilterBuilder<T> extends Mock
    implements PostgrestFilterBuilder<T> {
  final Future<T> _future;
  FakePostgrestFilterBuilder(this._future);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) {
    return _future.then(onValue, onError: onError);
  }
}

void main() {
  group('SuperAdminInvitationCommandService', () {
    late MockSupabaseClient mockClient;
    late SuperAdminInvitationCommandService service;

    const testOrgId = 'test-org-123';
    const testSuperAdminId = 'super-admin-456';
    const testEmail = 'newadmin@example.com';
    const testToken = 'secure-token-789';
    const testInvitationId = 'invitation-abc';
    final testExpiresAt = DateTime.utc(2030, 1, 1, 12, 0, 0);

    setUp(() {
      mockClient = MockSupabaseClient();
      service = SuperAdminInvitationCommandService(
        mockClient,
        orgId: testOrgId,
        superAdminUserId: testSuperAdminId,
      );
    });
    test(
      'inviteUser delegates to super_admin_invite_first_admin RPC correctly',
      () async {
        when(
          () => mockClient.rpc<void>(
            'super_admin_invite_first_admin',
            params: any(named: 'params'),
          ),
        ).thenAnswer((_) => FakePostgrestFilterBuilder<void>(Future.value()));

        await service.inviteUser(
          email: testEmail,
          role: UserRole.admin,
          token: testToken,
          invitationId: testInvitationId,
          expiresAtUtc: testExpiresAt,
        );

        verify(
          () => mockClient.rpc<void>(
            'super_admin_invite_first_admin',
            params: {
              'p_org_id': testOrgId,
              'p_email': testEmail,
              'p_role': 'TENANT_ADMIN',
              'p_token': testToken,
              'p_invitation_id': testInvitationId,
              'p_expires_at': testExpiresAt.toIso8601String(),
              'p_invited_by': testSuperAdminId,
            },
          ),
        ).called(1);
      },
    );

    test('inviteUser maps operator and auditor roles correctly', () async {
      when(
        () => mockClient.rpc<void>(
          'super_admin_invite_first_admin',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder<void>(Future.value()));

      await service.inviteUser(
        email: testEmail,
        role: UserRole.operator,
        token: testToken,
        invitationId: testInvitationId,
        expiresAtUtc: testExpiresAt,
      );

      verify(
        () => mockClient.rpc<void>(
          'super_admin_invite_first_admin',
          params: any(
            named: 'params',
            that: containsPair('p_role', 'OPERATOR'),
          ),
        ),
      ).called(1);

      await service.inviteUser(
        email: testEmail,
        role: UserRole.auditor,
        token: testToken,
        invitationId: testInvitationId,
        expiresAtUtc: testExpiresAt,
      );

      verify(
        () => mockClient.rpc<void>(
          'super_admin_invite_first_admin',
          params: any(named: 'params', that: containsPair('p_role', 'AUDITOR')),
        ),
      ).called(1);
    });

    test(
      'inviteUser blocks assigning superAdmin role via invitation',
      () async {
        expect(
          () => service.inviteUser(
            email: testEmail,
            role: UserRole.superAdmin,
            token: testToken,
            invitationId: testInvitationId,
            expiresAtUtc: testExpiresAt,
          ),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('superAdmin cannot be assigned via invitation'),
            ),
          ),
        );
        verifyNever(
          () => mockClient.rpc<void>(any(), params: any(named: 'params')),
        );
      },
    );

    test('inviteUser blocks contractorViewer role via this flow', () async {
      expect(
        () => service.inviteUser(
          email: testEmail,
          role: UserRole.contractorViewer,
          token: testToken,
          invitationId: testInvitationId,
          expiresAtUtc: testExpiresAt,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('CONTRACTOR_VIEWER invitations require dual-key setup'),
          ),
        ),
      );
      verifyNever(
        () => mockClient.rpc<void>(any(), params: any(named: 'params')),
      );
    });

    test(
      'acceptInvitation throws UnsupportedError to prevent misuse',
      () async {
        expect(
          () => service.acceptInvitation(token: 'any', userId: 'any'),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              contains('does not support acceptInvitation'),
            ),
          ),
        );
      },
    );

    test(
      'revokeInvitation throws UnsupportedError to prevent misuse',
      () async {
        expect(
          () => service.revokeInvitation(invitationId: 'any'),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              contains('does not support revokeInvitation'),
            ),
          ),
        );
      },
    );
  });
}
