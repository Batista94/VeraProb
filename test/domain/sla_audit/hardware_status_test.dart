import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/hardware_status.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

void main() {
  group('HardwareStatus.fromRpcValue', () {
    test('parses every known RPC TEXT value', () {
      expect(HardwareStatus.fromRpcValue('HEALTHY'), HardwareStatus.healthy);
      expect(HardwareStatus.fromRpcValue('DELAYED'), HardwareStatus.delayed);
      expect(HardwareStatus.fromRpcValue('OFFLINE'), HardwareStatus.offline);
      expect(
        HardwareStatus.fromRpcValue('NEVER_SEEN'),
        HardwareStatus.neverSeen,
      );
    });

    test('throws ArgumentError on an unknown value (INV-7 strict)', () {
      expect(
        () => HardwareStatus.fromRpcValue('GARBAGE'),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('is case-sensitive — lowercase is rejected', () {
      expect(
        () => HardwareStatus.fromRpcValue('healthy'),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  group('HardwareStatus.label', () {
    test('every status carries a Portuguese label', () {
      expect(HardwareStatus.healthy.label, 'Saudável');
      expect(HardwareStatus.delayed.label, 'Atrasado');
      expect(HardwareStatus.offline.label, 'Offline');
      expect(HardwareStatus.neverSeen.label, 'Nunca Visto');
    });
  });
}
