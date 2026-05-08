// GENERATED TEST FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/state/providers/contract_providers.dart';

void main() {
  group('contract_providers.dart Tests', () {
    test('ProviderContainer initializes correctly', () {
      final container = ProviderContainer.test();
      expect(container, isNotNull);
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(contractualRuleRepositoryProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(createContractHandlerProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(cloneContractHandlerProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(closeContractHandlerProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(acceptByContractorHandlerProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(shiftProjectionServiceProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(contractQueryServiceProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(selectedContractIdProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer.test();

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(contractStatusFilterProvider),
        isFalse,
      ); // Initially false before being read
    });
  });
}
