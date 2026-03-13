import 'package:pactaflow/infrastructure/sla_audit/postgres_contractual_financial_trend_query_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pactaflow/application/sla_audit/projections/contractual_financial_impact_query_service_in_memory.dart';
import 'package:pactaflow/application/sla_audit/projections/contractual_financial_trend_query_service_in_memory.dart';
import 'package:pactaflow/application/sla_audit/projections/sla_execution_query_service_in_memory.dart';
import 'package:pactaflow/infrastructure/persistence/persistence_mode.dart';
import 'package:pactaflow/infrastructure/persistence/persistence_provider.dart';
import 'package:pactaflow/infrastructure/providers/supabase_provider.dart';
import 'package:pactaflow/infrastructure/sla_audit/postgres_contractual_financial_impact_query_service.dart';
import 'package:pactaflow/infrastructure/sla_audit/postgres_sla_execution_query_service.dart';
import 'package:pactaflow/state/providers/sla_financial_providers.dart';
import 'package:pactaflow/state/providers/sla_providers.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('FASE 4 - Read-Model Governance Tests', () {
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

        final financialTrendQueryService = container.read(
          financialTrendQueryServiceProvider,
        );
        expect(
          financialTrendQueryService,
          isA<ContractualFinancialTrendQueryServiceInMemory>(),
          reason:
              'financialTrendQueryServiceProvider should be InMemory by default',
        );
      },
    );

    test(
      'Override to Postgres should return Postgres implementations for Read-Models',
      () {
        final mockSupabase = MockSupabaseClient();
        final container = ProviderContainer(
          overrides: [
            persistenceModeProvider.overrideWithValue(PersistenceMode.postgres),
            supabaseClientProvider.overrideWithValue(mockSupabase),
          ],
        );
        addTearDown(container.dispose);

        // Verify the provider instantiates the PG Query Service
        final slaExecutionQueryService = container.read(
          slaExecutionQueryServiceProvider,
        );
        expect(
          slaExecutionQueryService,
          isA<SlaExecutionQueryServicePostgres>(),
          reason:
              'slaExecutionQueryServiceProvider should return Postgres implementation when overridden',
        );

        final financialImpactQueryService = container.read(
          financialImpactQueryServiceProvider,
        );
        expect(
          financialImpactQueryService,
          isA<ContractualFinancialImpactQueryServicePostgres>(),
          reason:
              'financialImpactQueryServiceProvider should return Postgres implementation when overridden',
        );

        final financialTrendQueryService = container.read(
          financialTrendQueryServiceProvider,
        );
        expect(
          financialTrendQueryService,
          isA<ContractualFinancialTrendQueryServicePostgres>(),
          reason:
              'financialTrendQueryServiceProvider should return Postgres implementation when overridden',
        );
      },
    );
  });
}
