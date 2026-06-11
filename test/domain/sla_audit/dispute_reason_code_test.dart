import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/dispute_reason_code.dart';

void main() {
  group('DisputeReasonCode', () {
    // T10: identity is the code; labels/category are descriptive only.
    test('two codes with the same code are equal regardless of labels', () {
      const a = DisputeReasonCode(
        code: 'FORCE_MAJEURE',
        category: 'OPERATIONAL',
        labelPt: 'Força maior',
        labelEn: 'Force majeure',
        isActive: true,
      );
      const b = DisputeReasonCode(
        code: 'FORCE_MAJEURE',
        category: 'LEGAL',
        labelPt: 'Outro rótulo',
        labelEn: 'Other label',
        isActive: false,
      );
      expect(a == b, isTrue);
    });

    test('different codes are not equal', () {
      const a = DisputeReasonCode(
        code: 'FORCE_MAJEURE',
        category: 'OPERATIONAL',
        labelPt: 'Força maior',
        labelEn: 'Force majeure',
        isActive: true,
      );
      const b = DisputeReasonCode(
        code: 'SENSOR_FAULT',
        category: 'TECHNICAL',
        labelPt: 'Falha de sensor',
        labelEn: 'Sensor fault',
        isActive: true,
      );
      expect(a == b, isFalse);
    });
  });
}
