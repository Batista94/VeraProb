import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/cnpj_service_exceptions.dart';

void main() {
  group('CnpjServiceException Subtypes', () {
    group('ExternalApiException', () {
      test('fromStatusCode maps 5xx to upstream_server_error', () {
        final ex = ExternalApiException.fromStatusCode(500);
        expect(ex.sanitizedCode, equals('upstream_server_error'));
      });

      test('fromStatusCode maps 4xx to upstream_client_error', () {
        final ex = ExternalApiException.fromStatusCode(400);
        expect(ex.sanitizedCode, equals('upstream_client_error'));
      });

      test('toString hides sanitizedCode and cnpj (INV-28)', () {
        const ex = ExternalApiException(
          'Fail',
          sanitizedCode: 'secret_code',
          cnpj: '12345',
        );
        expect(ex.toString(), contains('ExternalApiException: Fail'));
        expect(ex.toString(), contains('code: secret_code'));
        expect(ex.toString(), isNot(contains('12345')));
      });
    });

    test('ServiceTimeoutException toString behavior', () {
      const ex = ServiceTimeoutException('Timeout', cnpj: '12345');
      expect(ex.toString(), equals('ServiceTimeoutException: Timeout'));
    });

    test('RateLimitExceededException toString behavior', () {
      const ex = RateLimitExceededException('Limited', cnpj: '12345');
      expect(ex.toString(), equals('RateLimitExceededException: Limited'));
    });
  });
}
