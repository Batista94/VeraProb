import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/config/environment.dart';

void main() {
  group('EnvironmentConfig Coverage', () {
    test('AppEnvironment.fromString', () {
      expect(AppEnvironment.fromString('dev'), AppEnvironment.dev);
      expect(AppEnvironment.fromString('staging'), AppEnvironment.staging);
      expect(AppEnvironment.fromString('prod'), AppEnvironment.prod);
      expect(AppEnvironment.fromString('UNKNOWN'), AppEnvironment.dev);
    });

    test('EnvironmentConfig getters (default values)', () {
      // Since we are not running with --dart-define, they should be defaults
      expect(EnvironmentConfig.environment, AppEnvironment.dev);
      expect(EnvironmentConfig.isDev, true);
      expect(EnvironmentConfig.isStaging, false);
      expect(EnvironmentConfig.isProd, false);

      expect(
        EnvironmentConfig.sentryEnabled,
        false,
      ); // dev || staging || prod? wait: isStaging || isProd
      expect(EnvironmentConfig.posthogEnabled, false);
      expect(EnvironmentConfig.showDebugBanner, true);

      expect(EnvironmentConfig.sentryEnvironment, 'dev');
      expect(EnvironmentConfig.label, '🔧 DEV');
    });
  });
}
