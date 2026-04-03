import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  // ── Shared helper ──────────────────────────────────────────

  SLAPenalties makePenalties() => SLAPenalties.create(
    noShowPenaltyBps: 15000,
    delayToleranceMinutes: 15,
    delayPenaltyPerMinute: const Money(50),
    downgradePenaltyFlat: const Money(5000),
  );

  // ── SlaTemplate.create ─────────────────────────────────────

  group('SlaTemplate.create', () {
    test('gera UUID v4', () {
      final t1 = SlaTemplate.create(
        organizationId: 'org-1',
        name: 'Template A',
        penalties: makePenalties(),
      );
      final t2 = SlaTemplate.create(
        organizationId: 'org-1',
        name: 'Template B',
        penalties: makePenalties(),
      );

      expect(t1.id, isNotEmpty);
      expect(t2.id, isNotEmpty);
      expect(t1.id, isNot(equals(t2.id)));
    });

    test('preserva campos', () {
      final penalties = makePenalties();
      final t = SlaTemplate.create(
        organizationId: 'org-42',
        name: 'Meu Template',
        description: 'Descrição de teste',
        penalties: penalties,
      );

      expect(t.organizationId, 'org-42');
      expect(t.name, 'Meu Template');
      expect(t.description, 'Descrição de teste');
      expect(t.penalties, penalties);
      expect(t.createdAt.isUtc, isTrue);
    });

    test('lança DomainException se name vazio', () {
      expect(
        () => SlaTemplate.create(
          organizationId: 'org-1',
          name: '',
          penalties: makePenalties(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('lança DomainException se name > 100 chars', () {
      expect(
        () => SlaTemplate.create(
          organizationId: 'org-1',
          name: 'x' * 101,
          penalties: makePenalties(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('lança DomainException se organizationId vazio', () {
      expect(
        () => SlaTemplate.create(
          organizationId: '',
          name: 'Template',
          penalties: makePenalties(),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('preserva vertical quando informado', () {
      final t = SlaTemplate.create(
        organizationId: 'org-1',
        name: 'Fretamento Padrão',
        vertical: TransportVertical.fretamento,
        penalties: makePenalties(),
      );

      expect(t.vertical, TransportVertical.fretamento);
    });

    test('vertical é null por padrão (backward compat)', () {
      final t = SlaTemplate.create(
        organizationId: 'org-1',
        name: 'Template Sem Vertical',
        penalties: makePenalties(),
      );

      expect(t.vertical, isNull);
    });
  });

  // ── SlaTemplate.reconstitute ───────────────────────────────

  group('SlaTemplate.reconstitute', () {
    test('não revalida (aceita name vazio)', () {
      final t = SlaTemplate.reconstitute(
        id: 'uuid-123',
        organizationId: 'org-1',
        name: '',
        penalties: makePenalties(),
        createdAt: DateTime.utc(2026, 1, 1),
      );

      expect(t.id, 'uuid-123');
      expect(t.name, '');
    });

    test('preserva vertical na reconstituição', () {
      final t = SlaTemplate.reconstitute(
        id: 'uuid-456',
        organizationId: 'org-1',
        name: 'Template',
        vertical: TransportVertical.escolar,
        penalties: makePenalties(),
        createdAt: DateTime.utc(2026, 3, 1),
      );

      expect(t.vertical, TransportVertical.escolar);
    });

    test('vertical null na reconstituição (backward compat)', () {
      final t = SlaTemplate.reconstitute(
        id: 'uuid-789',
        organizationId: 'org-1',
        name: 'Template Legado',
        penalties: makePenalties(),
        createdAt: DateTime.utc(2026, 1, 1),
      );

      expect(t.vertical, isNull);
    });
  });
}
