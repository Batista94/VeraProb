import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/clone_sla_template_handler.dart';
import 'package:veraprob/application/sla_audit/sla_template_presets.dart';
import 'package:veraprob/domain/auth/auth_user.dart' as domain;
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_template_repository.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late InMemorySlaTemplateRepository repository;
  late CloneSlaTemplateHandler handler;
  late MockAuthRepository mockAuthRepo;
  late TenantValidationService tenantValidator;

  setUp(() {
    repository = InMemorySlaTemplateRepository();
    mockAuthRepo = MockAuthRepository();
    tenantValidator = TenantValidationService(authRepository: mockAuthRepo);
    handler = CloneSlaTemplateHandler(
      tenantValidator: tenantValidator,
      repository: repository,
    );
    when(() => mockAuthRepo.getUserBySessionId(any())).thenAnswer(
      (_) async => const domain.AuthUser(
        id: 'user-1',
        email: 'test@test.com',
        tenantId: 'org-1',
      ),
    );
  });

  SLAPenalties makePenalties() => SLAPenalties.create(
    noShowPenaltyBps: 15000,
    delayToleranceMinutes: 15,
    delayPenaltyPerMinute: const Money(50),
    downgradePenaltyFlat: const Money(5000),
  );

  group('CloneSlaTemplateHandler', () {
    test('clona preset do sistema para org', () async {
      final clone = await handler.handle(
        sourceId: 'preset:fretamento',
        organizationId: 'org-1',
        sessionId: 'session-1',
      );

      expect(clone.organizationId, 'org-1');
      expect(clone.name, contains('Fretamento'));
      expect(clone.name, contains('Cópia'));
      expect(clone.vertical, TransportVertical.fretamento);
      expect(SlaTemplatePresets.isPreset(clone.id), isFalse);
    });

    test('clona template existente da org', () async {
      final original = SlaTemplate.create(
        organizationId: 'org-1',
        name: 'Original',
        vertical: TransportVertical.cargaSeca,
        penalties: makePenalties(),
      );
      await repository.save(original);

      final clone = await handler.handle(
        sourceId: original.id,
        organizationId: 'org-1',
        sessionId: 'session-1',
      );

      expect(clone.name, 'Original (Cópia)');
      expect(clone.vertical, TransportVertical.cargaSeca);
      expect(clone.penalties, original.penalties);
      expect(clone.id, isNot(equals(original.id)));
    });

    test('permite override de nome', () async {
      final clone = await handler.handle(
        sourceId: 'preset:escolar',
        organizationId: 'org-1',
        sessionId: 'session-1',
        nameOverride: 'Meu Escolar Customizado',
      );

      expect(clone.name, 'Meu Escolar Customizado');
    });

    test('lança DomainException se source não existe', () {
      expect(
        () => handler.handle(
          sourceId: 'uuid-nao-existe',
          organizationId: 'org-1',
          sessionId: 'session-1',
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('lança DomainException se preset ID inválido', () {
      expect(
        () => handler.handle(
          sourceId: 'preset:nao-existe',
          organizationId: 'org-1',
          sessionId: 'session-1',
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test(
      'não acessa template de outra org — lança SovereigntyViolationException',
      () async {
        final original = SlaTemplate.create(
          organizationId: 'org-A',
          name: 'Template Org A',
          penalties: makePenalties(),
        );
        await repository.save(original);

        expect(
          () => handler.handle(
            sourceId: original.id,
            organizationId: 'org-B',
            sessionId: 'session-1',
          ),
          throwsA(isA<SovereigntyViolationException>()),
        );
      },
    );
  });
}
