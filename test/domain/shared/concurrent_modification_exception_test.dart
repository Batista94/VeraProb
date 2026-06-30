import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/concurrent_modification_exception.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';

void main() {
  group('ConcurrentModificationException', () {
    test('should inherit from IdempotencyProcessingException', () {
      const exception = ConcurrentModificationException(
        idempotencyKey: 'key1',
        commandPath: 'path1',
      );

      expect(exception, isA<IdempotencyProcessingException>());
    });

    test('should correctly set fields and default message', () {
      const exception = ConcurrentModificationException(
        idempotencyKey: 'test_key',
        commandPath: 'test_path',
      );

      expect(exception.idempotencyKey, 'test_key');
      expect(exception.commandPath, 'test_path');
      expect(
        exception.message,
        'Este cartão já está sendo processado por outra transação. Atualize a fila.',
      );
    });

    test('should correctly format toString()', () {
      const exception = ConcurrentModificationException(
        idempotencyKey: 'test_key',
        commandPath: 'test_path',
      );

      expect(
        exception.toString(),
        'ConcurrentModificationException: Este cartão já está sendo processado por outra transação. Atualize a fila. (key: test_key, command: test_path)',
      );
    });

    test('should allow custom message', () {
      const exception = ConcurrentModificationException(
        idempotencyKey: 'test_key',
        commandPath: 'test_path',
        message: 'Custom message.',
      );

      expect(exception.message, 'Custom message.');
      expect(
        exception.toString(),
        'ConcurrentModificationException: Custom message. (key: test_key, command: test_path)',
      );
    });
  });
}
