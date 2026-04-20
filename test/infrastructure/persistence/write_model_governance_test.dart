import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/infrastructure/audit/audit_providers.dart';
import 'package:veraprob/infrastructure/audit/in_memory_audit_service.dart';
import 'package:veraprob/domain/authority/policies/in_memory_policy_evaluator.dart';
import 'package:veraprob/domain/authority/repositories/in_memory_forensic_repository.dart';
import 'package:veraprob/infrastructure/audit/postgres_audit_service.dart';
import 'package:veraprob/infrastructure/authority/postgres_forensic_repository.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/authority_providers.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('FASE 2 - Write-Model Governance Tests', () {
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
      'Override to Postgres should return Postgres implementations in governed providers',
      () {
        final mockSupabase = MockSupabaseClient();
        final container = ProviderContainer(
          overrides: [
            persistenceModeProvider.overrideWithValue(PersistenceMode.postgres),
            supabaseClientProvider.overrideWithValue(mockSupabase),
          ],
        );
        addTearDown(container.dispose);

        final auditService = container.read(auditServiceProvider);
        expect(
          auditService,
          isA<PostgresAuditService>(),
          reason:
              'auditServiceProvider should return PostgresAuditService when postgres mode is selected',
        );

        final forensicRepo = container.read(forensicDecisionRepositoryProvider);
        expect(
          forensicRepo,
          isA<PostgresForensicRepository>(),
          reason:
              'forensicDecisionRepositoryProvider should return PostgresForensicRepository when postgres mode is selected',
        );

        // Policy Evaluator is purely functional, it should remain InMemory even if mode is postgres.
        final policyEvaluator = container.read(
          authorityPolicyEvaluatorProvider,
        );
        expect(
          policyEvaluator,
          isA<InMemoryPolicyEvaluator>(),
          reason:
              'authorityPolicyEvaluatorProvider should always return InMemoryPolicyEvaluator as it lacks persistence',
        );
      },
    );
  });
}
