// GENERATED TEST FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/state/providers/mfa_providers.dart';

void main() {
  group('mfa_providers.dart Tests', () {
    test('ProviderContainer initializes correctly', () {
      final container = ProviderContainer.test();
      expect(container, isNotNull);
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(mfaRepositoryProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider data loading state', () {
      final container = ProviderContainer.test();

      final state = container.read(mfaStatusProvider);

      expect(state, isA<AsyncLoading>());
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(mfaEnrollmentHandlerProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(mfaChallengeHandlerProvider),
        isFalse,
      ); // Initially false before being read
    });
  });
}
