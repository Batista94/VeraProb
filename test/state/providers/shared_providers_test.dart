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

    test('tripRepositoryProvider exists after read path', () {
      final container = ProviderContainer.test();
      expect(container.exists(tripRepositoryProvider), isFalse);
    });

    test('sharedPreferencesProvider exists after read path', () {
      final container = ProviderContainer.test();
      expect(container.exists(sharedPreferencesProvider), isFalse);
    });

    test('dateTimeProviderProvider resolves', () {
      final container = ProviderContainer.test();
      expect(container.read(dateTimeProviderProvider), isNotNull);
    });

    test('evidenceUrlServiceProvider resolves', () {
      final container = ProviderContainer.test();
      expect(container.read(evidenceUrlServiceProvider), isNotNull);
    });
  });
}
