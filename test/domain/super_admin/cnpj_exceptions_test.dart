import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/super_admin/cnpj_exceptions.dart';

void main() {
  group('CnpjLookupException Subtypes', () {
    test('InvalidCnpjException toString does not leak sensitive details', () {
      const ex = InvalidCnpjException(
        'Invalid format',
        reason: 'invalid_format',
        cnpj: '12345',
      );
      expect(ex.toString(), equals('InvalidCnpjException: Invalid format'));
      expect(ex.toString(), isNot(contains('12345')));
      expect(ex.toString(), isNot(contains('invalid_format')));
    });

    test(
      'DataParsingException toString includes field but not sensitive data',
      () {
        const ex = DataParsingException(
          'Parse error',
          field: 'legalName',
          cnpj: '12345678000190',
        );
        expect(ex.toString(), contains('DataParsingException: Parse error'));
        expect(ex.toString(), contains('field: legalName'));
        expect(ex.toString(), isNot(contains('12345678000190')));
      },
    );

    test('DataParsingException defaults field to unknown in toString', () {
      const ex = DataParsingException('Parse error');
      expect(ex.toString(), contains('field: unknown'));
    });
  });
}
