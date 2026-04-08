import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/save_sla_template_handler.dart';
import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_template_repository.dart';
import '../../mocks/fake_date_time_provider.dart';

void main() {
  late InMemorySlaTemplateRepository repository;
  late SaveSlaTemplateHandler handler;
  late FakeDateTimeProvider clock;

  setUp(() {
    repository = InMemorySlaTemplateRepository();
    clock = FakeDateTimeProvider(DateTime.utc(2026, 4, 8, 12, 0));
    handler = SaveSlaTemplateHandler(repository: repository, clock: clock);
  });

  PenaltiesFormData makePenalties() => PenaltiesFormData(
    noShowPenaltyBps: 15000,
    delayToleranceMinutes: 15,
    delayPenaltyPerMinuteCents: 50,
    downgradePenaltyFlatCents: 5000,
    noShowThresholdMinutes: 60,
    earlyArrivalToleranceMinutes: 5,
    dwellTimeMinutes: 3,
    gracePeriodMinutes: 0,
    baseTripValueCents: 0,
  );

  group('SaveSlaTemplateHandler', () {
    test('cria template e persiste no repositório', () async {
      final result = await handler.handle(
        organizationId: 'org-1',
        name: 'Meu Template',
        penalties: makePenalties(),
      );

      expect(result.id, isNotEmpty);
      expect(result.organizationId, 'org-1');
      expect(result.name, 'Meu Template');

      final saved = await repository.findByOrganization('org-1');
      expect(saved, hasLength(1));
      expect(saved.first.id, result.id);
    });

    test('preserva vertical quando informado', () async {
      final result = await handler.handle(
        organizationId: 'org-1',
        name: 'Fretamento',
        vertical: TransportVertical.fretamento,
        penalties: makePenalties(),
      );

      expect(result.vertical, TransportVertical.fretamento);
    });

    test('preserva description quando informado', () async {
      final result = await handler.handle(
        organizationId: 'org-1',
        name: 'Test',
        description: 'Descrição',
        penalties: makePenalties(),
      );

      expect(result.description, 'Descrição');
    });

    test('lança DomainException se name vazio', () {
      expect(
        () => handler.handle(
          organizationId: 'org-1',
          name: '',
          penalties: makePenalties(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('lança DomainException se organizationId vazio', () {
      expect(
        () => handler.handle(
          organizationId: '',
          name: 'Test',
          penalties: makePenalties(),
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });
}
