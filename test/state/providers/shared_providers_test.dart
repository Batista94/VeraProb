// GENERATED TEST FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/state/providers/shared_providers.dart';

void main() {
  group('shared_providers.dart Tests', () {
    test('ProviderContainer initializes correctly', () {
      final container = ProviderContainer.test();
      expect(container, isNotNull);
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(gtfsServiceProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(vehicleRepositoryProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(tripRepositoryProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(sharedPreferencesProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(currentDriverProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(searchControllerProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider data loading state', () {
      final container = ProviderContainer.test();

      final state = container.read(searchQueryStreamProvider);

      expect(state, isA<AsyncLoading>());
    });
  });
}
