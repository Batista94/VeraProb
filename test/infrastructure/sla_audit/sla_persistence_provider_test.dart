import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';

void main() {
  group('sla_persistence_provider', () {
    test('ProviderContainer initializes correctly', () {
      final container = ProviderContainer.test();
      expect(container, isNotNull);
    });

    test('forensicEvidenceSnapshotRepositoryProvider not eagerly instantiated', () {
      final container = ProviderContainer.test();
      expect(container.exists(forensicEvidenceSnapshotRepositoryProvider), isFalse);
    });

    test('planDeclarationRepositoryProvider not eagerly instantiated', () {
      final container = ProviderContainer.test();
      expect(container.exists(planDeclarationRepositoryProvider), isFalse);
    });

    test('slaAuditLedgerRepositoryProvider not eagerly instantiated', () {
      final container = ProviderContainer.test();
      expect(container.exists(slaAuditLedgerRepositoryProvider), isFalse);
    });

    test('idempotencyStoreProvider not eagerly instantiated', () {
      final container = ProviderContainer.test();
      expect(container.exists(idempotencyStoreProvider), isFalse);
    });

    test('contractRepositoryProvider not eagerly instantiated', () {
      final container = ProviderContainer.test();
      expect(container.exists(contractRepositoryProvider), isFalse);
    });
  });
}
