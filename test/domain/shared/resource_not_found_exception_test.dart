import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';

void main() {
  group('ResourceNotFoundException', () {
    test('creates with default message and no resource details', () {
      const exception = ResourceNotFoundException();

      expect(exception.message, 'Resource not found.');
      expect(exception.resourceType, isNull);
      expect(exception.resourceId, isNull);
    });

    test('creates with resource type and ID for internal logging', () {
      const exception = ResourceNotFoundException(
        resourceType: 'contract',
        resourceId: 'contract-123',
      );

      expect(exception.resourceType, 'contract');
      expect(exception.resourceId, 'contract-123');
      expect(exception.message, 'Resource not found.');
    });

    test('creates with custom forensic message', () {
      const exception = ResourceNotFoundException(
        resourceType: 'asset',
        resourceId: 'asset-456',
        message: 'Source resource not accessible.',
      );

      expect(exception.message, 'Source resource not accessible.');
      expect(exception.resourceType, 'asset');
      expect(exception.resourceId, 'asset-456');
    });

    test('toString is sanitized — NO forensic fields for generic loggers', () {
      const exception = ResourceNotFoundException(
        resourceType: 'contract',
        resourceId: 'contract-secret-123',
      );

      final str = exception.toString();

      // Sanitized: only the message, no resource details
      expect(str, contains('ResourceNotFoundException'));
      expect(str, contains('Resource not found.'));
      expect(str, isNot(contains('contract')));
      expect(str, isNot(contains('contract-secret-123')));
    });

    test('toString omits resource fields when null', () {
      const exception = ResourceNotFoundException();

      final str = exception.toString();

      expect(str, contains('ResourceNotFoundException'));
      expect(str, contains('Resource not found.'));
    });

    test('toForensicString includes resource details for internal logging', () {
      const exception = ResourceNotFoundException(
        resourceType: 'contract',
        resourceId: 'contract-789',
      );

      final forensic = exception.toForensicString();

      expect(forensic, contains('ResourceNotFoundException'));
      expect(forensic, contains('contract'));
      expect(forensic, contains('contract-789'));
    });

    test('toForensicString uses custom message when provided', () {
      const exception = ResourceNotFoundException(
        resourceType: 'asset',
        resourceId: 'asset-456',
        message: 'Custom forensic message',
      );

      final forensic = exception.toForensicString();
      expect(forensic, contains('Custom forensic message'));
      expect(forensic, contains('asset'));
      expect(forensic, contains('asset-456'));
    });

    test('toForensicString omits resource fields when null', () {
      const exception = ResourceNotFoundException();

      final forensic = exception.toForensicString();

      expect(forensic, contains('ResourceNotFoundException'));
      expect(forensic, contains('Resource not found.'));
      expect(forensic, isNot(contains('resourceType:')));
      expect(forensic, isNot(contains('resourceId:')));
    });

    test('equality is based on all fields', () {
      const ex1 = ResourceNotFoundException(
        resourceType: 'contract',
        resourceId: 'c-1',
        message: 'msg',
      );
      const ex2 = ResourceNotFoundException(
        resourceType: 'contract',
        resourceId: 'c-1',
        message: 'msg',
      );
      const ex3 = ResourceNotFoundException(
        resourceType: 'asset',
        resourceId: 'c-1',
        message: 'msg',
      );

      expect(ex1, equals(ex2));
      expect(ex1, isNot(equals(ex3)));
    });

    test('hashCode is consistent with equality', () {
      const ex1 = ResourceNotFoundException(
        resourceType: 'contract',
        resourceId: 'c-1',
        message: 'msg',
      );
      const ex2 = ResourceNotFoundException(
        resourceType: 'contract',
        resourceId: 'c-1',
        message: 'msg',
      );

      expect(ex1.hashCode, equals(ex2.hashCode));
    });

    test('equality works when all fields are null', () {
      const ex1 = ResourceNotFoundException();
      const ex2 = ResourceNotFoundException();

      expect(ex1, equals(ex2));
    });

    test('implements Exception', () {
      const exception = ResourceNotFoundException();

      expect(exception, isA<Exception>());
    });
  });
}
