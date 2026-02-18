import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/features/driver/domain/entities/driver.dart';

void main() {
  group('Driver Entity', () {
    const driver1 = Driver(
      id: '1',
      name: 'João Silva',
      licenseNumber: '12345678900',
    );
    const driver2 = Driver(
      id: '2',
      name: 'Maria Oliveira',
      licenseNumber: '98765432100',
    );
    const driver1Copy = Driver(
      id: '1',
      name: 'João Silva',
      licenseNumber: '12345678900',
    );

    test('should instantiate with correct properties', () {
      expect(driver1.id, '1');
      expect(driver1.name, 'João Silva');
      expect(driver1.licenseNumber, '12345678900');
    });

    test('two drivers with same id should be equal', () {
      expect(driver1, equals(driver1Copy));
    });

    test('two drivers with different ids should not be equal', () {
      expect(driver1, isNot(equals(driver2)));
    });

    test('hashCode should be based on id', () {
      expect(driver1.hashCode, equals(driver1Copy.hashCode));
      expect(driver1.hashCode, isNot(equals(driver2.hashCode)));
    });

    test('identical instances should be equal', () {
      expect(driver1, equals(driver1));
    });
  });
}
