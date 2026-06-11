import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_dispute_reason_code_repository.dart';

/// Pure-mapping coverage for the reason-code row decoder. The live `.select()`
/// path is exercised by the pgTAP catalogue test + in-memory parity test; here
/// we pin the column→field contract so a silent rename can't ship.
void main() {
  test('mapRow decodes a catalogue row into the domain VO', () {
    final code = PostgresDisputeReasonCodeRepository.mapRow(<String, dynamic>{
      'code': 'FORCE_MAJEURE',
      'category': 'ENVIRONMENTAL',
      'label_pt': 'Força Maior',
      'label_en': 'Force Majeure',
      'is_active': true,
    });

    expect(code.code, 'FORCE_MAJEURE');
    expect(code.category, 'ENVIRONMENTAL');
    expect(code.labelPt, 'Força Maior');
    expect(code.labelEn, 'Force Majeure');
    expect(code.isActive, isTrue);
  });
}
