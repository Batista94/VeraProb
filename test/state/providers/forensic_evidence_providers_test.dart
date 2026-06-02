import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/state/providers/forensic_evidence_providers.dart';

void main() {
  group('forensic_evidence_providers', () {
    test('ProviderContainer initializes correctly', () {
      final container = ProviderContainer.test();
      expect(container, isNotNull);
    });

    test('sealForensicEvidenceHandlerProvider not eagerly instantiated', () {
      final container = ProviderContainer.test();
      expect(container.exists(sealForensicEvidenceHandlerProvider), isFalse);
    });
  });
}
