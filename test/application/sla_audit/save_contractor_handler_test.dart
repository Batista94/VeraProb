import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/save_contractor_command.dart';
import 'package:veraprob/application/sla_audit/save_contractor_handler.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/sla_audit/contractor.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import '../../mocks/fake_date_time_provider.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockContractorRepository extends Mock implements ContractorRepository {}

void main() {
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;
  late MockContractorRepository repository;
  late SaveContractorHandler handler;

  setUpAll(() {
    registerFallbackValue(
      Contractor(
        id: '',
        organizationId: '',
        name: '',
        primaryEmail: '',
        contactName: '',
        createdAtUtc: DateTime.now().toUtc(),
      ),
    );
  });

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    repository = MockContractorRepository();
    handler = SaveContractorHandler(
      tenantValidator: tenantValidator,
      repository: repository,
      clock: FakeDateTimeProvider(DateTime.utc(2026, 1, 1)),
    );
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'test@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  SaveContractorCommand makeCommand({
    UserRole role = UserRole.admin,
    String? id,
  }) {
    return SaveContractorCommand(
      organizationId: 'org-1',
      callerRole: role,
      id: id,
      name: 'Contractor X',
      primaryEmail: 'x@x.com',
      contactName: 'Mr X',
      sessionId: 'session-1',
    );
  }

  group('SaveContractorHandler', () {
    test('Rejeita auditor', () async {
      expect(
        () => handler.handle(makeCommand(role: UserRole.auditor)),
        throwsException,
      );
      verifyNever(() => repository.save(any()));
    });

    test('Passa para admin e operator', () async {
      when(() => repository.save(any())).thenAnswer((_) async => {});

      await handler.handle(makeCommand(role: UserRole.admin));
      await handler.handle(makeCommand(role: UserRole.operator));

      verify(() => repository.save(any())).called(2);
    });

    test('Gera UUID se id == null', () async {
      when(() => repository.save(any())).thenAnswer((_) async => {});

      await handler.handle(makeCommand(id: null));

      final captured =
          verify(() => repository.save(captureAny())).captured.single
              as Contractor;
      expect(captured.id, isNotEmpty);
      expect(captured.id, hasLength(36)); // UUID v4 format
    });

    test('Reutiliza ID se fornecido', () async {
      final existing = Contractor(
        id: 'existing-id',
        organizationId: 'org-1',
        name: 'Old',
        primaryEmail: 'old@a.com',
        contactName: 'Old',
        createdAtUtc: DateTime.utc(2025),
      );
      when(
        () => repository.findById('org-1', 'existing-id'),
      ).thenAnswer((_) async => existing);
      when(() => repository.save(any())).thenAnswer((_) async => {});

      await handler.handle(makeCommand(id: 'existing-id'));

      final captured =
          verify(() => repository.save(captureAny())).captured.single
              as Contractor;
      expect(captured.id, 'existing-id');
      expect(captured.createdAtUtc, existing.createdAtUtc);
      expect(captured.name, 'Contractor X');
    });

    test('Erro quando contractor não encontrado no update', () async {
      when(
        () => repository.findById(any(), any()),
      ).thenAnswer((_) async => null);

      expect(() => handler.handle(makeCommand(id: 'missing')), throwsException);
    });
  });
}
