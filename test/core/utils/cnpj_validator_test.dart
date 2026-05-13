import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/shared/cnpj_validator.dart';

void main() {
  group('CnpjValidator', () {
    group('isValid', () {
      test('valid known-good CNPJ returns true', () {
        // 11.222.333/0001-81 — well-known valid CNPJ used in BR tests
        expect(CnpjValidator.isValid('11222333000181'), isTrue);
      });

      test('valid formatted CNPJ returns true', () {
        expect(CnpjValidator.isValid('11.222.333/0001-81'), isTrue);
      });

      test('wrong check digit returns false', () {
        // Last digit changed from 1 to 2
        expect(CnpjValidator.isValid('11222333000182'), isFalse);
      });

      test('wrong first check digit returns false', () {
        // 12th digit changed
        expect(CnpjValidator.isValid('11222333000191'), isFalse);
      });

      test('all-same digits fail (11.111.111/1111-11)', () {
        expect(CnpjValidator.isValid('11111111111111'), isFalse);
      });

      test('all zeros fail', () {
        expect(CnpjValidator.isValid('00000000000000'), isFalse);
      });

      test('empty string returns false', () {
        expect(CnpjValidator.isValid(''), isFalse);
      });

      test('too short returns false', () {
        expect(CnpjValidator.isValid('1122233300018'), isFalse);
      });

      test('too long returns false', () {
        expect(CnpjValidator.isValid('112223330001810'), isFalse);
      });

      test('non-digit characters stripped before validation', () {
        // Mask characters should be stripped
        expect(CnpjValidator.isValid('11.222.333/0001-81'), isTrue);
      });

      test('second valid known-good CNPJ', () {
        // Petrobras: 33.000.167/0001-01
        expect(CnpjValidator.isValid('33000167000101'), isTrue);
      });
    });

    group('format', () {
      test('formats bare digits with mask', () {
        expect(CnpjValidator.format('11222333000181'), '11.222.333/0001-81');
      });

      test('strips existing mask before reformatting', () {
        expect(
          CnpjValidator.format('11.222.333/0001-81'),
          '11.222.333/0001-81',
        );
      });

      test('returns empty string for empty input', () {
        expect(CnpjValidator.format(''), '');
      });

      test('partial input formats up to available digits', () {
        expect(CnpjValidator.format('11222'), '11.222');
      });
    });
  });
}
