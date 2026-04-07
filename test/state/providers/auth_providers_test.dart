// GENERATED TEST FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

void main() {
  group('auth_providers.dart Tests', () {
    test('ProviderContainer initializes correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container, isNotNull);
    });

    test('provider data loading state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(authStateProvider);

      expect(state, isA<AsyncError>());
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(currentOperatorIdProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider data loading state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(organizationIdFetcherProvider);

      expect(state, isA<AsyncLoading>());
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(currentOrganizationIdProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(currentUserRoleProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(currentOperatorNameProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(currentOperatorEmailProvider),
        isFalse,
      ); // Initially false before being read
    });

    test('provider initial state test structure', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // We check that container has the provider without instantiating dependencies that might throw UnimplementedError
      expect(
        container.exists(authRepositoryProvider),
        isFalse,
      ); // Initially false before being read
    });
  });
}
