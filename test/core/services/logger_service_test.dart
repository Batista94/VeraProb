import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/observability/logger_service.dart';

void main() {
  group('LoggerService Coverage', () {
    late LoggerService logger;

    setUp(() {
      logger = LoggerService();
    });

    test('singleton instance', () {
      expect(LoggerService(), same(logger));
    });

    test('log message', () {
      // debugPrint is captured or just ignored in tests, but it hits the lines
      logger.log('test log');
      logger.log('test log', component: 'TestComponent');
    });

    test('error message', () {
      logger.error('test error');
      logger.error('test error', error: 'some error');
      logger.error(
        'test error',
        error: 'some error',
        stackTrace: StackTrace.current,
      );
    });

    test('security message', () {
      logger.security('test security event');
    });
  });
}
