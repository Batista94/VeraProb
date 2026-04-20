import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/service_manifest.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  SLAPenalties makePenalties() => SLAPenalties.create(
    noShowPenaltyBps: 15000,
    delayToleranceMinutes: 15,
    delayPenaltyPerMinute: const Money(50),
    downgradePenaltyFlat: const Money(5000),
  );

  group('ServiceManifest.create', () {
    test('gera UUID e preserva campos', () {
      final penalties = makePenalties();
      final m = ServiceManifest.create(
        organizationId: 'org-1',
        contractId: 'contract-1',
        name: 'Fretamento Diário',
        description: 'Serviço padrão',
        slaTemplateId: 'tpl-1',
        vertical: TransportVertical.fretamento,
        penalties: penalties,
      );

      expect(m.id, isNotEmpty);
      expect(m.organizationId, 'org-1');
      expect(m.contractId, 'contract-1');
      expect(m.name, 'Fretamento Diário');
      expect(m.description, 'Serviço padrão');
      expect(m.slaTemplateId, 'tpl-1');
      expect(m.vertical, TransportVertical.fretamento);
      expect(m.penalties, penalties);
      expect(m.createdAtUtc.isUtc, isTrue);
    });

    test('gera IDs únicos', () {
      final m1 = ServiceManifest.create(
        organizationId: 'org-1',
        contractId: 'c-1',
        name: 'A',
        vertical: TransportVertical.cargaSeca,
        penalties: makePenalties(),
      );
      final m2 = ServiceManifest.create(
        organizationId: 'org-1',
        contractId: 'c-1',
        name: 'B',
        vertical: TransportVertical.cargaSeca,
        penalties: makePenalties(),
      );

      expect(m1.id, isNot(equals(m2.id)));
    });

    test('description e slaTemplateId são opcionais', () {
      final m = ServiceManifest.create(
        organizationId: 'org-1',
        contractId: 'c-1',
        name: 'Sem Extras',
        vertical: TransportVertical.custom,
        penalties: makePenalties(),
      );

      expect(m.description, isNull);
      expect(m.slaTemplateId, isNull);
    });

    test('lança DomainException se organizationId vazio', () {
      expect(
        () => ServiceManifest.create(
          organizationId: '',
          contractId: 'c-1',
          name: 'Test',
          vertical: TransportVertical.fretamento,
          penalties: makePenalties(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('lança DomainException se contractId vazio', () {
      expect(
        () => ServiceManifest.create(
          organizationId: 'org-1',
          contractId: '',
          name: 'Test',
          vertical: TransportVertical.fretamento,
          penalties: makePenalties(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('lança DomainException se name vazio', () {
      expect(
        () => ServiceManifest.create(
          organizationId: 'org-1',
          contractId: 'c-1',
          name: '   ',
          vertical: TransportVertical.fretamento,
          penalties: makePenalties(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('lança DomainException se name > 150 chars', () {
      expect(
        () => ServiceManifest.create(
          organizationId: 'org-1',
          contractId: 'c-1',
          name: 'x' * 151,
          vertical: TransportVertical.fretamento,
          penalties: makePenalties(),
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('ServiceManifest.reconstitute', () {
    test('reconstitui sem revalidar', () {
      final m = ServiceManifest.reconstitute(
        id: 'manifest-123',
        organizationId: 'org-1',
        contractId: 'c-1',
        name: '',
        vertical: TransportVertical.escolar,
        penalties: makePenalties(),
        createdAtUtc: DateTime.utc(2026, 3, 1),
      );

      expect(m.id, 'manifest-123');
      expect(m.name, '');
      expect(m.vertical, TransportVertical.escolar);
    });

    test('preserva slaTemplateId na reconstituição', () {
      final m = ServiceManifest.reconstitute(
        id: 'manifest-456',
        organizationId: 'org-1',
        contractId: 'c-1',
        name: 'Test',
        slaTemplateId: 'tpl-99',
        vertical: TransportVertical.cargaRefrigerada,
        penalties: makePenalties(),
        createdAtUtc: DateTime.utc(2026, 3, 1),
      );

      expect(m.slaTemplateId, 'tpl-99');
    });
  });

  group('ServiceManifest equality', () {
    test('igualdade por id', () {
      final penalties = makePenalties();
      final a = ServiceManifest.reconstitute(
        id: 'same-id',
        organizationId: 'org-1',
        contractId: 'c-1',
        name: 'A',
        vertical: TransportVertical.fretamento,
        penalties: penalties,
        createdAtUtc: DateTime.utc(2026, 1, 1),
      );
      final b = ServiceManifest.reconstitute(
        id: 'same-id',
        organizationId: 'org-2',
        contractId: 'c-2',
        name: 'B',
        vertical: TransportVertical.escolar,
        penalties: penalties,
        createdAtUtc: DateTime.utc(2026, 6, 1),
      );

      expect(a, equals(b));
    });
  });
}
