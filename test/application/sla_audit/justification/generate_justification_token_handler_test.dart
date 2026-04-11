import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/generate_justification_token_command.dart';
import 'package:veraprob/application/sla_audit/justification/generate_justification_token_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/in_memory_justification_repository.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late InMemoryJustificationRepository justificationRepo;
  late GenerateJustificationTokenHandler handler;
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;

  GenerateJustificationTokenCommand makeCommand({
    UserRole role = UserRole.operator,
    int expiresInHours = 24,
  }) {
    return GenerateJustificationTokenCommand(
      organizationId: 'org-abc',
      contractId: 'CTR-100',
      setId: 'SET-XYZ',
      callerRole: role,
      callerUserId: 'user-op-1',
      expiresInHours: expiresInHours,
      sessionId: 'session-1',
    );
  }

  setUp(() {
    justificationRepo = InMemoryJustificationRepository();
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    handler = GenerateJustificationTokenHandler(
      tenantValidator: tenantValidator,
      justificationRepo: justificationRepo,
      rbac: RbacService(),
    );
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'test@test.com',
        tenantId: 'org-abc',
      ),
    );
  });

  group('RBAC', () {
    test('throws DomainException for auditor role', () async {
      await expectLater(
        handler.handle(makeCommand(role: UserRole.auditor)),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for contractorViewer role', () async {
      await expectLater(
        handler.handle(makeCommand(role: UserRole.contractorViewer)),
        throwsA(isA<DomainException>()),
      );
    });

    test('allows admin role', () async {
      await expectLater(
        handler.handle(makeCommand(role: UserRole.admin)),
        completes,
      );
    });

    test('allows operator role', () async {
      await expectLater(handler.handle(makeCommand()), completes);
    });
  });

  group('Expiry validation (PO-6)', () {
    test('throws on expiresInHours < 1', () async {
      await expectLater(
        handler.handle(makeCommand(expiresInHours: 0)),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws on expiresInHours > 72', () async {
      await expectLater(
        handler.handle(makeCommand(expiresInHours: 73)),
        throwsA(isA<DomainException>()),
      );
    });

    test('accepts boundary value 1', () async {
      await expectLater(
        handler.handle(makeCommand(expiresInHours: 1)),
        completes,
      );
    });

    test('accepts boundary value 72', () async {
      await expectLater(
        handler.handle(makeCommand(expiresInHours: 72)),
        completes,
      );
    });
  });

  group('Happy path', () {
    test('returns token with correct routing fields', () async {
      final token = await handler.handle(makeCommand());
      expect(token.organizationId, 'org-abc');
      expect(token.contractId, 'CTR-100');
      expect(token.setId, 'SET-XYZ');
      expect(token.isActive, isTrue);
      expect(token.usedAtUtc, isNull);
    });

    test('generated token is distinct each call', () async {
      final t1 = await handler.handle(makeCommand());
      final t2 = await handler.handle(makeCommand());
      expect(t1.token, isNot(t2.token));
    });
  });
}
