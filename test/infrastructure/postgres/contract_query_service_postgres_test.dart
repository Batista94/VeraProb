import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_summary.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contract_query_service.dart';
import 'package:uuid/uuid.dart';

import 'postgres_test_config.dart';

class MockSlaExecutionQueryService extends Mock
    implements SlaExecutionQueryService {}

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  group(
    'PostgresContractQueryService Integration Tests',
    () {
      late SupabaseClient client;
      late MockSlaExecutionQueryService mockSlaService;
      late PostgresContractQueryService service;
      const uuid = Uuid();
      const organizationId = PostgresTestConfig.testOrgId;
      final List<String> createdContracts = [];

      setUpAll(() async {
        if (isRunning) {
          client = await PostgresTestConfig.createClient();
          mockSlaService = MockSlaExecutionQueryService();
          service = PostgresContractQueryService(
            client: client,
            slaExecutionQueryService: mockSlaService,
          );
        }
      });

      tearDown(() async {
        if (isRunning && createdContracts.isNotEmpty) {
          for (final id in createdContracts) {
            await client.from('contracts').delete().eq('id', id);
          }
          createdContracts.clear();
        }
      });

      test('listContracts returns summaries from DB', () async {
        final contractId = uuid.v4();
        createdContracts.add(contractId);

        // Seed a contract
        await client.from('contracts').insert({
          'id': contractId,
          'organization_id': organizationId,
          'name': 'Query Service Test Contract',
          'contractor_name': 'Test Contractor',
          'status': 'active',
          'valid_from_utc': DateTime.now().toUtc().toIso8601String(),
          'valid_until_utc': DateTime.now()
              .toUtc()
              .add(const Duration(days: 365))
              .toIso8601String(),
          'financial_ceiling_cents': 1000000,
        });

        final result = await service.listContracts(
          organizationId: organizationId,
        );

        expect(result.any((c) => c.id == contractId), isTrue);
        final summary = result.firstWhere((c) => c.id == contractId);
        expect(summary.name, 'Query Service Test Contract');
        expect(summary.financialCeilingCents, 1000000);
      });

      test(
        'getContractDetail returns full detail including financial summary',
        () async {
          final contractId = uuid.v4();
          createdContracts.add(contractId);

          // Seed contract
          await client.from('contracts').insert({
            'id': contractId,
            'organization_id': organizationId,
            'name': 'Detail Test Contract',
            'contractor_name': 'Test Contractor',
            'status': 'active',
            'valid_from_utc': DateTime.now().toUtc().toIso8601String(),
            'valid_until_utc': DateTime.now()
                .toUtc()
                .add(const Duration(days: 365))
                .toIso8601String(),
          });

          // Mock financial summary
          final mockSummary = SlaExecutionSummary(
            contractId: contractId,
            totalPending: 5,
            totalExecuted: 10,
            totalNoShow: 1,
            totalEvidenceGap: 0,
            generatedAtUtc: DateTime.now().toUtc(),
            protectedRevenue: const Money(50000),
          );

          when(
            () => mockSlaService.getSummary(
              organizationId: any(named: 'organizationId'),
              contractId: any(named: 'contractId'),
            ),
          ).thenAnswer((_) async => mockSummary);

          final detail = await service.getContractDetail(
            organizationId: organizationId,
            contractId: contractId,
          );

          expect(detail, isNotNull);
          expect(detail!.summary.id, contractId);
          expect(detail.financialSummary.totalExecuted, 10);
          expect(detail.financialSummary.protectedRevenue.cents, 50000);
        },
      );

      test('getContractDetail returns null for missing contract', () async {
        final detail = await service.getContractDetail(
          organizationId: organizationId,
          contractId: uuid.v4(),
        );
        expect(detail, isNull);
      });
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
