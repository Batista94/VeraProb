import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/application/sla_audit/projections/contractual_financial_impact_query_service_in_memory.dart';
import 'package:busflow/application/sla_audit/projections/sla_execution_query_service_in_memory.dart';
import 'package:busflow/infrastructure/persistence/persistence_mode.dart';
import 'package:busflow/infrastructure/persistence/persistence_provider.dart';
import 'package:busflow/state/providers/sla_financial_providers.dart';
import 'package:busflow/state/providers/sla_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('FASE 3 - Read-Model Governance Tests', () {
    test(
      'Default mode should return InMemory implementations for Read-Models',
      () {
        final container =
            ProviderContainer(); // Default mode is PersistenceMode.inMemory
        addTearDown(container.dispose);

        final slaExecutionQueryService = container.read(
          slaExecutionQueryServiceProvider,
        );
        expect(
          slaExecutionQueryService,
          isA<SlaExecutionQueryServiceInMemory>(),
          reason:
              'slaExecutionQueryServiceProvider should be InMemory by default',
        );

        final financialImpactQueryService = container.read(
          financialImpactQueryServiceProvider,
        );
        expect(
          financialImpactQueryService,
          isA<ContractualFinancialImpactQueryServiceInMemory>(),
          reason:
              'financialImpactQueryServiceProvider should be InMemory by default',
        );
      },
    );

    test(
      'Override to Postgres should throw standardized UnimplementedError in governed Read-Model providers',
      () {
        final container = ProviderContainer(
          overrides: [
            persistenceModeProvider.overrideWithValue(PersistenceMode.postgres),
          ],
        );
        addTearDown(container.dispose);

        // Verify the standardized exception message
        final matcher = throwsA(
          isA<UnimplementedError>().having(
            (e) => e.message,
            'message',
            'Read-model Postgres implementation not available yet',
          ),
        );

        expect(
          () => container.read(slaExecutionQueryServiceProvider),
          matcher,
          reason:
              'slaExecutionQueryServiceProvider should block Postgres execution with specific error',
        );

        expect(
          () => container.read(financialImpactQueryServiceProvider),
          matcher,
          reason:
              'financialImpactQueryServiceProvider should block Postgres execution with specific error',
        );
      },
    );
  });
}
