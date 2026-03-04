import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/application/audit/audit_service.dart';
import 'package:busflow/domain/authority/policies/in_memory_policy_evaluator.dart';
import 'package:busflow/domain/authority/repositories/in_memory_forensic_repository.dart';
import 'package:busflow/infrastructure/persistence/persistence_mode.dart';
import 'package:busflow/infrastructure/persistence/persistence_provider.dart';
import 'package:busflow/state/providers/authority_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('FASE 1 - Write-Model Governance Tests', () {
    test('Default mode should return InMemory implementations', () {
      final container =
          ProviderContainer(); // Default mode is PersistenceMode.inMemory
      addTearDown(container.dispose);

      final auditService = container.read(auditServiceProvider);
      expect(
        auditService,
        isA<InMemoryAuditService>(),
        reason:
            'auditServiceProvider should be InMemoryAuditService by default',
      );

      final forensicRepo = container.read(forensicDecisionRepositoryProvider);
      expect(
        forensicRepo,
        isA<InMemoryForensicRepository>(),
        reason:
            'forensicDecisionRepositoryProvider should be InMemoryForensicRepository by default',
      );

      final policyEvaluator = container.read(authorityPolicyEvaluatorProvider);
      expect(
        policyEvaluator,
        isA<InMemoryPolicyEvaluator>(),
        reason:
            'authorityPolicyEvaluatorProvider should be InMemoryPolicyEvaluator by default',
      );
    });

    test(
      'Override to Postgres should throw UnimplementedError in governed providers',
      () {
        final container = ProviderContainer(
          overrides: [
            persistenceModeProvider.overrideWithValue(PersistenceMode.postgres),
          ],
        );
        addTearDown(container.dispose);

        expect(
          () => container.read(auditServiceProvider),
          throwsUnimplementedError,
          reason:
              'auditServiceProvider should throw when postgres mode is selected but not implemented',
        );

        expect(
          () => container.read(forensicDecisionRepositoryProvider),
          throwsUnimplementedError,
          reason:
              'forensicDecisionRepositoryProvider should throw when postgres mode is selected but not implemented',
        );

        expect(
          () => container.read(authorityPolicyEvaluatorProvider),
          throwsUnimplementedError,
          reason:
              'authorityPolicyEvaluatorProvider should throw when postgres mode is selected but not implemented',
        );
      },
    );
  });
}
