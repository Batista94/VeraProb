import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/super_admin/cnpj_lookup_exceptions.dart'
    as app_ex;

void main() {
  test('cnpj_lookup_exceptions re-exports domain exceptions', () {
    // This just verifies the types are accessible via the application layer export
    // to maintain INV-13 (presentation layer only imports from application).
    expect(
      const app_ex.InvalidCnpjException('test', reason: 'test'),
      isA<app_ex.CnpjLookupException>(),
    );
  });
}
