import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/sla_audit/simulation_seed_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

class MockPostgrestFilterBuilder extends Mock
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {}

// We create a fake implementation of PostgrestFilterBuilder to handle the fluent method chaining
class FakePostgrestFilterBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  final List<Map<String, dynamic>> _mockResult;

  FakePostgrestFilterBuilder(this._mockResult);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([
    String columns = '*',
  ]) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(
    String column,
    Object value,
  ) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> isFilter(
    String column,
    Object? value,
  ) => this;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> gte(
    String column,
    Object value,
  ) => this;

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> limit(
    int count, {
    String? referencedTable,
  }) {
    return FakePostgrestTransformBuilder(_mockResult);
  }
}

class FakePostgrestTransformBuilder extends Fake
    implements PostgrestTransformBuilder<List<Map<String, dynamic>>> {
  final List<Map<String, dynamic>> _mockResult;

  FakePostgrestTransformBuilder(this._mockResult);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) async {
    return onValue(_mockResult);
  }

  @override
  Stream<List<Map<String, dynamic>>> asStream() => Stream.value(_mockResult);
}

// For insert mocking
class FakeInsertBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) async {
    return onValue([]);
  }
}

class FakeInsertQueryBuilder extends Fake implements SupabaseQueryBuilder {
  final FakeInsertBuilder _builder = FakeInsertBuilder();

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> insert(
    Object values, {
    bool defaultToNull = true,
  }) {
    return _builder;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(const <Map<String, dynamic>>[]);
  });

  group('SimulationSeedService', () {
    group('_NoOpSimulationSeedService', () {
      test('should always return 0', () async {
        final service = noOpSimulationSeedService();
        final result = await service.seedFinancialSnapshots('org-123');
        expect(result, 0);
      });
    });

    group('PostgresSimulationSeedService', () {
      late MockSupabaseClient mockClient;
      late PostgresSimulationSeedService service;

      setUp(() {
        mockClient = MockSupabaseClient();
        service = PostgresSimulationSeedService(mockClient);
      });

      test('should return 0 if records already exist', () async {
        final mockQueryBuilder = MockSupabaseQueryBuilder();
        final fakeFilter = FakePostgrestFilterBuilder([
          {'id': '123'},
        ]);

        when(
          () => mockClient.from('contractual_financial_snapshot'),
        ).thenAnswer((_) => mockQueryBuilder);

        when(() => mockQueryBuilder.select('id')).thenAnswer((_) => fakeFilter);

        final result = await service.seedFinancialSnapshots('org-123');

        expect(result, 0);
      });

      test('should insert 7 records if no records exist', () async {
        // Setup select builder to return empty (no records exist)
        final selectQueryBuilder = MockSupabaseQueryBuilder();
        final fakeEmptyFilter = FakePostgrestFilterBuilder([]);

        // Setup insert builder
        final fakeInsertQueryBuilder = FakeInsertQueryBuilder();

        // The service calls client.from() twice: once for select, once for insert
        var callCount = 0;
        when(
          () => mockClient.from('contractual_financial_snapshot'),
        ).thenAnswer((_) {
          callCount++;
          if (callCount == 1) {
            return selectQueryBuilder;
          } else {
            return fakeInsertQueryBuilder;
          }
        });

        when(
          () => selectQueryBuilder.select('id'),
        ).thenAnswer((_) => fakeEmptyFilter);

        final result = await service.seedFinancialSnapshots('org-123');

        expect(result, 7);
      });
    });
  });
}
