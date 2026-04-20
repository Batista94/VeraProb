import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/sla_template_view.dart';

void main() {
  group('SlaTemplateView', () {
    test('can be constructed with required fields', () {
      final now = DateTime.utc(2026, 4, 1);
      final view = SlaTemplateView(
        id: 'tpl-1',
        organizationId: 'org-1',
        name: 'Padrão Urbano',
        noShowPenaltyBps: 15000,
        delayToleranceMinutes: 5,
        delayPenaltyPerMinuteCents: 50,
        downgradePenaltyFlatCents: 2000,
        noShowThresholdMinutes: 60,
        earlyArrivalToleranceMinutes: 5,
        dwellTimeMinutes: 3,
        gracePeriodMinutes: 0,
        baseTripValueCents: 50000,
        createdAt: now,
      );
      expect(view.id, 'tpl-1');
      expect(view.name, 'Padrão Urbano');
    });

    test('all financial fields are int (BPS compliance)', () {
      final now = DateTime.utc(2026, 4, 1);
      final view = SlaTemplateView(
        id: 'tpl-2',
        organizationId: 'org-1',
        name: 'Test Template',
        noShowPenaltyBps: 15000,
        delayToleranceMinutes: 5,
        delayPenaltyPerMinuteCents: 50,
        downgradePenaltyFlatCents: 2000,
        noShowThresholdMinutes: 60,
        earlyArrivalToleranceMinutes: 5,
        dwellTimeMinutes: 3,
        gracePeriodMinutes: 0,
        baseTripValueCents: 50000,
        createdAt: now,
      );
      expect(view.noShowPenaltyBps, isA<int>());
      expect(view.delayPenaltyPerMinuteCents, isA<int>());
      expect(view.downgradePenaltyFlatCents, isA<int>());
      expect(view.baseTripValueCents, isA<int>());
      expect(view.delayToleranceMinutes, isA<int>());
    });

    test('noShowPenaltyBps=15000 means 150% of contractual value', () {
      final now = DateTime.utc(2026, 4, 1);
      final view = SlaTemplateView(
        id: 'tpl-3',
        organizationId: 'org-1',
        name: 'Template 150%',
        noShowPenaltyBps: 15000,
        delayToleranceMinutes: 0,
        delayPenaltyPerMinuteCents: 0,
        downgradePenaltyFlatCents: 0,
        noShowThresholdMinutes: 60,
        earlyArrivalToleranceMinutes: 5,
        dwellTimeMinutes: 3,
        gracePeriodMinutes: 0,
        baseTripValueCents: 0,
        createdAt: now,
      );
      // 15000 bps = 150% — not 1.5 (no double)
      expect(view.noShowPenaltyBps, 15000);
    });
  });
}
