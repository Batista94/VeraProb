import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/domain/sla_audit/sla_template.dart';
import 'package:busflow/domain/sla_audit/sla_penalties.dart';
import 'package:busflow/domain/sla_audit/domain_exception.dart';
import 'package:busflow/domain/shared/money.dart';

void main() {
  // ── Shared helper ──────────────────────────────────────────

  SLAPenalties makePenalties() => SLAPenalties.create(
        noShowPenaltyMultiplier: 1.5,
        delayToleranceMinutes: 15,
        delayPenaltyPerMinute: Money(50),
        downgradePenaltyFlat: Money(5000),
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
  });
}
