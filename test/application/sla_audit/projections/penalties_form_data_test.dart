import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';

void main() {
  group('PenaltiesFormData', () {
    test('defaults constructor provides sensible int values', () {
      final form = PenaltiesFormData.defaults();
      expect(form.noShowPenaltyBps, isA<int>());
      expect(form.delayToleranceMinutes, isA<int>());
      expect(form.delayPenaltyPerMinuteCents, isA<int>());
      expect(form.downgradePenaltyFlatCents, isA<int>());
      expect(form.baseTripValueCents, isA<int>());
    });

    test('all fields are int (no double allowed)', () {
      final form = PenaltiesFormData.defaults();
      expect(form.noShowPenaltyBps, isA<int>());
      expect(form.delayPenaltyPerMinuteCents, isA<int>());
      expect(form.downgradePenaltyFlatCents, isA<int>());
      expect(form.baseTripValueCents, isA<int>());
    });

    test('toDomain() converts back to SLAPenalties', () {
      final form = PenaltiesFormData.defaults();
      final domain = form.toDomain();
      expect(domain.noShowPenaltyBps, form.noShowPenaltyBps);
      expect(
        domain.delayPenaltyPerMinute.cents,
        form.delayPenaltyPerMinuteCents,
      );
      expect(domain.downgradePenaltyFlat.cents, form.downgradePenaltyFlatCents);
    });

    test('can be mutated (mutable form model)', () {
      final form = PenaltiesFormData.defaults();
      form.noShowPenaltyBps = 20000;
      expect(form.noShowPenaltyBps, 20000);
    });
  });
}
