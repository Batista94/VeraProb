import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/utils/cnpj_validator.dart';

void main() {
  group('CnpjValidator (INV-18/INV-21)', () {
    test('isValid recognizes valid CNPJs', () {
      // Valid CNPJs (mathematically correct)
      expect(CnpjValidator.isValid('11.444.777/0001-61'), isTrue);
      expect(CnpjValidator.isValid('11444777000161'), isTrue);
      expect(CnpjValidator.isValid('00.000.000/0001-91'), isTrue);
    });

    test('isValid rejects structurally invalid inputs', () {
      expect(CnpjValidator.isValid('123'), isFalse); // Too short
      expect(CnpjValidator.isValid('123456789012345'), isFalse); // Too long
      expect(CnpjValidator.isValid(''), isFalse); // Empty
    });

    test('isValid rejects all-same-digit sequences (fraud prevention)', () {
      expect(CnpjValidator.isValid('00.000.000/0000-00'), isFalse);
      expect(CnpjValidator.isValid('11.111.111/1111-11'), isFalse);
    });

    test('isValid rejects invalid check digits', () {
      // 13.435.034/0001-45 (last digit changed from 4 to 5)
      expect(CnpjValidator.isValid('13.435.034/0001-45'), isFalse);
    });

    test('format applies Brazilian mask correctly', () {
      expect(CnpjValidator.format('13435034000144'), '13.435.034/0001-44');
      expect(CnpjValidator.format('13.435.034/0001-44'), '13.435.034/0001-44');
    });

    test('format handles partial inputs gracefully', () {
      expect(CnpjValidator.format('13'), '13');
      expect(CnpjValidator.format('134'), '13.4');
      expect(CnpjValidator.format('134350'), '13.435.0');
      expect(CnpjValidator.format('134350340'), '13.435.034/0');
      expect(CnpjValidator.format('1343503400014'), '13.435.034/0001-4');
    });

    test('format returns empty string for empty input', () {
      expect(CnpjValidator.format(''), '');
    });
  });
}
