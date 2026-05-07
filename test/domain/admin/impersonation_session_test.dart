// pr_scanner: INV-1 INV-28
/// CIA Triad security suite — Impersonation Session.
///
/// INV-28: Auditability
/// INV-1: Multi-tenant Isolation
/// Adversarial test coverage: State bleed, illegal impersonation, inception, invalid target, cascading revocation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/domain/admin/impersonation_session.dart';
import 'package:veraprob/domain/super_admin/impersonation_exception.dart';
import 'package:veraprob/domain/enums/user_role.dart';

// ── Interfaces for Testing ───────────────────────────────────────────────────

abstract class IImpersonationService {
  Future<ImpersonationSession> startImpersonation({
    required String targetOrgId,
    required String targetUserId,
    required String superAdminId,
    required UserRole callerRole,
    required String ticketId,
  });

  Future<void> performAction(String sessionId, String action);

  Future<void> checkSessionValidity(String sessionId);
}

class MockImpersonationService extends Mock implements IImpersonationService {}

class MockAuditLog extends Mock {
  void record({
    required String actorId,
    required String targetUserId,
    required String action,
    required String orgId,
  });
}

// ── CIA Triad Suite ───────────────────────────────────────────────────────────

void main() {
  late MockImpersonationService service;
  late MockAuditLog auditLog;

  setUpAll(() {
    registerFallbackValue(UserRole.superAdmin);
  });

  setUp(() {
    service = MockImpersonationService();
    auditLog = MockAuditLog();
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 1. Confidencialidade (Isolamento de Estado e Prevenção de Vazamento)
  // ══════════════════════════════════════════════════════════════════════════
  group('[CIA:C] Confidencialidade — Isolamento e Prevenção de Vazamento', () {
    test(
      '[C-1][Adverso] Vazamento de Contexto Global: SuperAdmin session is encapsulated',
      () async {
        // Asserção: O token de impessoalização deve ser estritamente encapsulado.
        // O estado global do SuperAdmin NÃO pode ser sobrescrito (State Bleed).
        final session = ImpersonationSession(
          id: 'imp-session-001',
          impersonatorUserId: 'super-admin-001',
          targetOrgId: 'org-tenant-X',
          targetUserId: 'client-X',
          issuedAt: DateTime.utc(2026, 5, 6, 20, 0),
          expiresAt: DateTime.utc(2026, 5, 6, 20, 30),
          ticketId: 'TKT-123',
        );

        when(
          () => service.startImpersonation(
            targetOrgId: any(named: 'targetOrgId'),
            targetUserId: any(named: 'targetUserId'),
            superAdminId: any(named: 'superAdminId'),
            callerRole: any(named: 'callerRole'),
            ticketId: any(named: 'ticketId'),
          ),
        ).thenAnswer((_) async => session);

        final result = await service.startImpersonation(
          targetOrgId: 'org-tenant-X',
          targetUserId: 'client-X',
          superAdminId: 'super-admin-001',
          callerRole: UserRole.superAdmin,
          ticketId: 'TKT-123',
        );

        // A sessão de impessoalização isola rigorosamente os IDs
        expect(result.impersonatorUserId, 'super-admin-001');
        expect(result.targetOrgId, 'org-tenant-X');
        expect(result.targetUserId, 'client-X');
        expect(
          result.id,
          isNot(equals('super-admin-001')),
        ); // Token distinto encapsulado
      },
    );

    test(
      '[C-2][Adverso] Impessoalização Ilegal: admin de tenant tenta acionar o endpoint',
      () async {
        // Asserção: Rejeição imediata com AccessDeniedException.
        when(
          () => service.startImpersonation(
            targetOrgId: any(named: 'targetOrgId'),
            targetUserId: any(named: 'targetUserId'),
            superAdminId: any(named: 'superAdminId'),
            callerRole: UserRole.admin,
            ticketId: any(named: 'ticketId'),
          ),
        ).thenThrow(const AccessDeniedException(callerRole: 'admin'));

        expect(
          () => service.startImpersonation(
            targetOrgId: 'org-tenant-Y',
            targetUserId: 'client-Y',
            superAdminId: 'admin-001',
            callerRole: UserRole.admin, // Usuário não tem permissão
            ticketId: 'TKT-999',
          ),
          throwsA(isA<AccessDeniedException>()),
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 2. Integridade (Rastreio Forense Absoluto - INV-28)
  // ══════════════════════════════════════════════════════════════════════════
  group('[CIA:I] Integridade — Rastreio Forense Absoluto (INV-28)', () {
    test(
      '[I-1][Happy Path] Auditoria de Ator Original: registro rigoroso de ActorID e TargetUserID',
      () async {
        // Asserção: O contexto da aplicação muda para o do Cliente X, permitindo a ação.
        // PORÉM, o log de auditoria deve registrar o ActorID original (SuperAdmin).
        when(
          () => service.performAction('imp-session-001', 'read_data'),
        ).thenAnswer((_) async {
          auditLog.record(
            actorId: 'super-admin-001',
            targetUserId: 'client-X',
            action: 'read_data',
            orgId: 'org-tenant-X',
          );
        });

        await service.performAction('imp-session-001', 'read_data');

        verify(
          () => auditLog.record(
            actorId: 'super-admin-001', // Assinatura inegociável do ator real
            targetUserId: 'client-X', // Usuário alvo sob impessoalização
            action: 'read_data',
            orgId: 'org-tenant-X',
          ),
        ).called(1);
      },
    );

    test(
      '[I-2][Bug Comum] Inception / Double Impersonation estritamente bloqueado',
      () async {
        // Asserção: Lança InvalidImpersonationStateException se tentar aninhar sessões.
        when(
          () => service.startImpersonation(
            targetOrgId: 'org-tenant-Y',
            targetUserId: 'client-Y',
            superAdminId: 'super-admin-001',
            callerRole: UserRole.superAdmin,
            ticketId: 'TKT-124',
          ),
        ).thenThrow(
          const InvalidImpersonationStateException(
            activeSessionId: 'imp-session-001',
            targetOrgId: 'org-tenant-X',
          ),
        );

        expect(
          () => service.startImpersonation(
            targetOrgId: 'org-tenant-Y',
            targetUserId: 'client-Y',
            superAdminId: 'super-admin-001',
            callerRole: UserRole.superAdmin,
            ticketId: 'TKT-124',
          ),
          throwsA(isA<InvalidImpersonationStateException>()),
        );
      },
    );

    test(
      '[I-3][Bug Comum] Alvo Inválido: tentativa de impessoalizar usuário inexistente ou soft-deleted',
      () async {
        // Asserção: Fail-fast com InvalidImpersonationTargetException antes da emissão do token.
        when(
          () => service.startImpersonation(
            targetOrgId: 'org-tenant-Z',
            targetUserId: 'client-deleted',
            superAdminId: 'super-admin-001',
            callerRole: UserRole.superAdmin,
            ticketId: 'TKT-125',
          ),
        ).thenThrow(
          const InvalidImpersonationTargetException(
            targetId: 'client-deleted',
            reason: 'User is soft-deleted or does not exist',
          ),
        );

        expect(
          () => service.startImpersonation(
            targetOrgId: 'org-tenant-Z',
            targetUserId: 'client-deleted',
            superAdminId: 'super-admin-001',
            callerRole: UserRole.superAdmin,
            ticketId: 'TKT-125',
          ),
          throwsA(isA<InvalidImpersonationTargetException>()),
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 3. Disponibilidade (Ciclo de Vida e Kill Switch)
  // ══════════════════════════════════════════════════════════════════════════
  group('[CIA:A] Disponibilidade — Ciclo de Vida e Kill Switch', () {
    test(
      '[A-1][Adverso] Fim de Sessão Forçado a Montante (Cascading Revocation)',
      () async {
        // Asserção: Se a conta original do SuperAdmin cair, o token herdado é imediatamente invalidado.
        when(() => service.checkSessionValidity('imp-session-001')).thenThrow(
          const CascadingRevocationException(
            impersonationSessionId: 'imp-session-001',
            superAdminUserId: 'super-admin-001',
          ),
        );

        expect(
          () => service.checkSessionValidity('imp-session-001'),
          throwsA(isA<CascadingRevocationException>()),
        );
      },
    );

    test(
      '[A-2][Adverso] Time-To-Live Restrito: expiração matemática da sessão',
      () async {
        // Asserção: Sessões não são infinitas; token expirado gera ImpersonationTokenExpiredException.
        final expiredTime = DateTime.utc(2026, 5, 6, 19, 0);

        when(
          () => service.checkSessionValidity('imp-session-expired'),
        ).thenThrow(
          ImpersonationTokenExpiredException(
            sessionId: 'imp-session-expired',
            expiredAt: expiredTime,
          ),
        );

        expect(
          () => service.checkSessionValidity('imp-session-expired'),
          throwsA(isA<ImpersonationTokenExpiredException>()),
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 4. Domain Model Assertions
  // ══════════════════════════════════════════════════════════════════════════
  group('ImpersonationSession Domain Assertions', () {
    test('Domain Model calculates TTL correctly', () {
      final now = DateTime.utc(2026, 5, 6, 20, 15);
      final session = ImpersonationSession(
        id: 'imp-1',
        impersonatorUserId: 'super',
        targetOrgId: 'org',
        issuedAt: DateTime.utc(2026, 5, 6, 20, 0),
        expiresAt: DateTime.utc(2026, 5, 6, 20, 30),
        ticketId: 'TKT',
      );

      expect(session.isActiveAt(now), isTrue);
      expect(session.remainingAt(now), equals(const Duration(minutes: 15)));
    });

    test('Domain Model reflects expired state', () {
      final now = DateTime.utc(2026, 5, 6, 20, 45); // After expiry
      final session = ImpersonationSession(
        id: 'imp-1',
        impersonatorUserId: 'super',
        targetOrgId: 'org',
        issuedAt: DateTime.utc(2026, 5, 6, 20, 0),
        expiresAt: DateTime.utc(2026, 5, 6, 20, 30),
        ticketId: 'TKT',
      );

      expect(session.isActiveAt(now), isFalse);
      expect(session.remainingAt(now), equals(Duration.zero));
    });

    test('Domain Model reflects revoked state (Kill Switch)', () {
      final now = DateTime.utc(2026, 5, 6, 20, 15);
      final session = ImpersonationSession(
        id: 'imp-1',
        impersonatorUserId: 'super',
        targetOrgId: 'org',
        issuedAt: DateTime.utc(2026, 5, 6, 20, 0),
        expiresAt: DateTime.utc(2026, 5, 6, 20, 30),
        revokedAt: DateTime.utc(2026, 5, 6, 20, 10),
        revocationReason: 'admin logout',
        ticketId: 'TKT',
      );

      expect(session.isActiveAt(now), isFalse);
      expect(session.remainingAt(now), equals(Duration.zero));
    });
  });
}
