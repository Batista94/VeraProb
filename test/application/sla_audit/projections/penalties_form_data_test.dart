import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';

void main() {
  group('PenaltiesFormData', () {
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
  });
}
