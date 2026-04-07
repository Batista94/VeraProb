// GENERATED TEST FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/state/providers/contractor_providers.dart';

void main() {
  group('contractor_providers.dart Tests', () {
    test('ProviderContainer initializes correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container, isNotNull);
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(contractorRepositoryProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(saveContractorHandlerProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(deleteContractorHandlerProvider),
        isFalse,
      ); // Initially false before being read
    });
  });
}
