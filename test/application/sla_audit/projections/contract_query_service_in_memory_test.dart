import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/projections/contract_query_service_in_memory.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_query_service.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state_repository.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration_repository.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_summary.dart';

class MockContractRepo extends Mock implements ContractRepository {}

class MockPlanRepo extends Mock implements PlanDeclarationRepository {}

class MockExecutionRepo extends Mock
    implements ContractualExecutionStateRepository {}

class MockSlaQueryService extends Mock implements SlaExecutionQueryService {}

void main() {
  group('ContractQueryServiceInMemory Coverage', () {
    late MockContractRepo mockContractRepo;
    late MockPlanRepo mockPlanRepo;
    late MockExecutionRepo mockExecutionRepo;
    late MockSlaQueryService mockSlaQueryService;
    late ContractQueryServiceInMemory service;

    setUp(() {
      mockContractRepo = MockContractRepo();
      mockPlanRepo = MockPlanRepo();
      mockExecutionRepo = MockExecutionRepo();
      mockSlaQueryService = MockSlaQueryService();
      service = ContractQueryServiceInMemory(
        contractRepository: mockContractRepo,
        planRepository: mockPlanRepo,
        executionStateRepository: mockExecutionRepo,
        slaExecutionQueryService: mockSlaQueryService,
      );
    });

    test('listContracts success', () async {
      final contract = Contract.reconstitute(
        id: 'c1-id',
        organizationId: 'org1',
        name: 'c1',
        contractorName: 'contractor1',
        validFromUtc: DateTime.now().toUtc(),
        validUntilUtc: DateTime.now().toUtc().add(const Duration(days: 365)),
        status: ContractStatus.active,
        createdAtUtc: DateTime.now().toUtc(),
        financialCeiling: const Money(1000000),
        penaltyMultiplierBps: 10000,
      );

      when(
        () => mockContractRepo.findByOrganization(
          any(),
          status: any(named: 'status'),
        ),
      ).thenAnswer((_) async => [contract]);

      // Need to handle _buildSummary inside listContracts
      when(
        () => mockContractRepo.findById(
          any(),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => contract);
      when(
        () => mockPlanRepo.findByContract(
          any(),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => []);
      when(
        () => mockExecutionRepo.findByContract(
          any(),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => []);

      final result = await service.listContracts(
        organizationId: 'org1',
        status: ContractStatusView.active,
      );

      expect(result, hasLength(1));
      expect(result.first.name, 'c1');
    });

    test('getContractDetail success', () async {
      final contract = Contract.reconstitute(
        id: 'c1-id',
        organizationId: 'org1',
        name: 'c1',
        contractorName: 'contractor1',
        validFromUtc: DateTime.now().toUtc(),
        validUntilUtc: DateTime.now().toUtc().add(const Duration(days: 365)),
        status: ContractStatus.active,
        createdAtUtc: DateTime.now().toUtc(),
        penaltyMultiplierBps: 10000,
      );

      when(
        () => mockContractRepo.findById(
          any(),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => contract);
      when(
        () => mockPlanRepo.findByContract(
          any(),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => []);

      final execState = ContractualExecutionState.create(
        organizationId: 'org1',
        setId: 's1',
        contractId: 'c1',
        planVersion: 1,
        startLatitude: 0,
        startLongitude: 0,
        startRadiusMeters: 100,
        contractualValue: const Money(10000),
        noShowPenaltyBps: 10000,
        windowStartUtc: DateTime.now().toUtc(),
        windowEndUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      when(
        () => mockExecutionRepo.findByContract(
          any(),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => [execState]);

      when(
        () => mockSlaQueryService.getSummary(
          organizationId: any(named: 'organizationId'),
          contractId: any(named: 'contractId'),
        ),
      ).thenAnswer(
        (_) async =>
            SlaExecutionSummary.empty(generatedAtUtc: DateTime.utc(2026, 1, 1)),
      );

      final result = await service.getContractDetail(
        organizationId: 'org1',
        contractId: 'c1',
      );

      expect(result, isNotNull);
      expect(result!.summary.name, 'c1');
      expect(result.recentExecutions, hasLength(1));
    });

    test('getContractDetail not found', () async {
      when(
        () => mockContractRepo.findById(
          any(),
          organizationId: any(named: 'organizationId'),
        ),
      ).thenAnswer((_) async => null);

      final result = await service.getContractDetail(
        organizationId: 'org1',
        contractId: 'c1',
      );
      expect(result, isNull);
    });
  });
}
