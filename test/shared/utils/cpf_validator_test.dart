import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/shared/utils/cpf_validator.dart';

void main() {
  group('CpfValidator', () {
    test('C1: valid CPF digits only', () {
      expect(CpfValidator.isValid('52998224725'), true);
    });

    test('C2: valid CPF with mask', () {
      expect(CpfValidator.isValid('529.982.247-25'), true);
    });

    test('C3: rejects all-same-digit sequence', () {
      expect(CpfValidator.isValid('111.111.111-11'), false);
      expect(CpfValidator.isValid('00000000000'), false);
    });

    test('C4: rejects wrong check digit', () {
      expect(CpfValidator.isValid('52998224720'), false);
    });

    test('C5: rejects input with wrong length', () {
      expect(CpfValidator.isValid('1234567890'), false); // 10 digits
      expect(CpfValidator.isValid('123456789012'), false); // 12 digits
      expect(CpfValidator.isValid(''), false);
    });
  });
}
