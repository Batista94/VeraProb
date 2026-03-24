import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state_repository.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/investigation_providers.dart';
import 'package:veraprob/state/providers/sla_providers.dart';

class MockSlaAuditLedgerRepository extends Mock
    implements SlaAuditLedgerRepository {}

class MockEvaluationTraceRepository extends Mock
    implements EvaluationTraceRepository {}

class MockContractualExecutionStateRepository extends Mock
    implements ContractualExecutionStateRepository {}

SlaLedgerEntry _makeEntry({
  String organizationId = 'org-1',
  String setId = 'set-1',
  DateTime? occurredAtUtc,
}) {
  return SlaLedgerEntry(
    organizationId: organizationId,
    setId: setId,
    contractId: 'contract-1',
    type: 'PLAN_DECLARED',
    planVersion: 1,
    occurredAtUtc: occurredAtUtc ?? DateTime.utc(2026, 1, 1),
  );
}

void main() {
  late MockSlaAuditLedgerRepository mockLedger;
  late MockEvaluationTraceRepository mockTraceRepo;
  late MockContractualExecutionStateRepository mockExecutionRepo;

  setUp(() {
    mockLedger = MockSlaAuditLedgerRepository();
    mockTraceRepo = MockEvaluationTraceRepository();
    mockExecutionRepo = MockContractualExecutionStateRepository();
  });

  ProviderContainer makeContainer({String? organizationId}) {
    return ProviderContainer(
      overrides: [
        currentOrganizationIdProvider.overrideWithValue(organizationId),
        slaAuditLedgerRepositoryProvider.overrideWithValue(mockLedger),
        evaluationTraceRepositoryProvider.overrideWithValue(mockTraceRepo),
        contractualExecutionStateRepositoryProvider
            .overrideWithValue(mockExecutionRepo),
      ],
    );
  }

  group('ledgerEntriesProvider', () {
    test('returns empty list when currentOrganizationIdProvider is null',
        () async {
      final container = makeContainer(organizationId: null);
      addTearDown(container.dispose);

      final result = await container.read(
        ledgerEntriesProvider('set-1').future,
      );
      expect(result, isEmpty);
      verifyNever(
        () => mockLedger.getEntriesBySetId(any(), organizationId: any(named: 'organizationId')),
      );
    });

    test('calls getEntriesBySetId with correct organizationId', () async {
      when(
        () => mockLedger.getEntriesBySetId(
          'set-1',
          organizationId: 'org-1',
        ),
      ).thenAnswer((_) async => [_makeEntry()]);

      final container = makeContainer(organizationId: 'org-1');
      addTearDown(container.dispose);

      final result = await container.read(
        ledgerEntriesProvider('set-1').future,
      );
      expect(result, hasLength(1));
      verify(
        () => mockLedger.getEntriesBySetId('set-1', organizationId: 'org-1'),
      ).called(1);
    });

    test('enforces chronological sort regardless of repository return order',
        () async {
      final entries = [
        _makeEntry(occurredAtUtc: DateTime.utc(2026, 1, 3)),
        _makeEntry(occurredAtUtc: DateTime.utc(2026, 1, 1)),
        _makeEntry(occurredAtUtc: DateTime.utc(2026, 1, 2)),
      ];
      when(
        () => mockLedger.getEntriesBySetId('set-1', organizationId: 'org-1'),
      ).thenAnswer((_) async => entries);

      final container = makeContainer(organizationId: 'org-1');
      addTearDown(container.dispose);

      final result = await container.read(
        ledgerEntriesProvider('set-1').future,
      );
      expect(result[0].occurredAtUtc, DateTime.utc(2026, 1, 1));
      expect(result[1].occurredAtUtc, DateTime.utc(2026, 1, 2));
      expect(result[2].occurredAtUtc, DateTime.utc(2026, 1, 3));
    });

    test('passes setId as positional argument to repository', () async {
      when(
        () => mockLedger.getEntriesBySetId(
          'my-set-id',
          organizationId: 'org-1',
        ),
      ).thenAnswer((_) async => []);

      final container = makeContainer(organizationId: 'org-1');
      addTearDown(container.dispose);

      await container.read(ledgerEntriesProvider('my-set-id').future);

      verify(
        () => mockLedger.getEntriesBySetId(
          'my-set-id',
          organizationId: any(named: 'organizationId'),
        ),
      ).called(1);
    });
  });

  group('evaluationTracesProvider', () {
    test('calls findByEntityId with the correct entityId parameter', () async {
      when(() => mockTraceRepo.findByEntityId('entity-abc'))
          .thenAnswer((_) async => []);

      final container = makeContainer(organizationId: 'org-1');
      addTearDown(container.dispose);

      await container.read(evaluationTracesProvider('entity-abc').future);

      verify(() => mockTraceRepo.findByEntityId('entity-abc')).called(1);
    });

    test('returns empty list when repository returns no traces', () async {
      when(() => mockTraceRepo.findByEntityId(any()))
          .thenAnswer((_) async => []);

      final container = makeContainer(organizationId: 'org-1');
      addTearDown(container.dispose);

      final result = await container.read(
        evaluationTracesProvider('entity-abc').future,
      );
      expect(result, isEmpty);
    });
  });

  group('executionStateProvider', () {
    test('calls findBySetId with the correct setId parameter', () async {
      when(() => mockExecutionRepo.findBySetId('set-xyz'))
          .thenAnswer((_) async => null);

      final container = makeContainer(organizationId: 'org-1');
      addTearDown(container.dispose);

      await container.read(executionStateProvider('set-xyz').future);

      verify(() => mockExecutionRepo.findBySetId('set-xyz')).called(1);
    });

    test('returns null when execution state does not exist', () async {
      when(() => mockExecutionRepo.findBySetId(any()))
          .thenAnswer((_) async => null);

      final container = makeContainer(organizationId: 'org-1');
      addTearDown(container.dispose);

      final result = await container.read(
        executionStateProvider('set-xyz').future,
      );
      expect(result, isNull);
    });
  });
}
