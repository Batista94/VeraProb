// GENERATED TEST FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/state/providers/sla_financial_providers.dart';

void main() {
  group('sla_financial_providers.dart Tests', () {
    test('ProviderContainer initializes correctly', () {
      final container = ProviderContainer.test();
      expect(container, isNotNull);
    });

    test('provider data loading state', () {
      final container = ProviderContainer.test();

      final state = container.read(financialImpactProvider);

      expect(state, isA<AsyncLoading<Object?>>());
    });
  });
}
