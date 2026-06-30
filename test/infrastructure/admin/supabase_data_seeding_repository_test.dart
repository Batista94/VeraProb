import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/infrastructure/admin/supabase_data_seeding_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

class FakePostgrestMaybeSingleBuilder extends Fake
    implements PostgrestTransformBuilder<Map<String, dynamic>?> {
  final List<Map<String, dynamic>> _mockResult;
  FakePostgrestMaybeSingleBuilder(this._mockResult);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(Map<String, dynamic>? value) onValue, {
    Function? onError,
  }) async {
    return onValue(_mockResult.isEmpty ? null : _mockResult.first);
  }
}

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

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    return FakePostgrestMaybeSingleBuilder(_mockResult);
  }
}

class FakePostgrestTransformBuilder extends Fake
    implements PostgrestTransformBuilder<List<Map<String, dynamic>>> {
  final List<Map<String, dynamic>> _mockResult;
  FakePostgrestTransformBuilder(this._mockResult);

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    return FakePostgrestMaybeSingleBuilder(_mockResult);
  }
}

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

void main() {
  group('SupabaseDataSeedingRepository', () {
    late MockSupabaseClient mockClient;
    late MockDateTimeProvider mockDateTimeProvider;
    late SupabaseDataSeedingRepository repository;

    setUp(() {
      mockClient = MockSupabaseClient();
      mockDateTimeProvider = MockDateTimeProvider();
      repository = SupabaseDataSeedingRepository(
        mockClient,
        mockDateTimeProvider,
      );
    });

    test(
      'seedDrivers should skip existing drivers and insert missing ones',
      () async {
        final mockQueryBuilder = MockSupabaseQueryBuilder();

        // We will pretend the first driver exists, and the others do not.
        var selectCallCount = 0;
        when(
          () => mockClient.from('drivers'),
        ).thenAnswer((_) => mockQueryBuilder);
        when(() => mockQueryBuilder.select()).thenAnswer((_) {
          selectCallCount++;
          if (selectCallCount == 1) {
            return FakePostgrestFilterBuilder([
              {'id': '1'},
            ]); // Exists
          }
          return FakePostgrestFilterBuilder([]); // Missing
        });

        // Mock insert builder for the missing drivers
        when(
          () => mockQueryBuilder.insert(any()),
        ).thenAnswer((_) => FakeInsertBuilder());

        await repository.seedDrivers('org-123');

        // 3 drivers in the list. First exists, so we should insert twice.
        verify(() => mockQueryBuilder.insert(any())).called(2);
      },
    );

    test(
      'seedRoutes should throw IntegrityException if Supabase throws',
      () async {
        final mockQueryBuilder = MockSupabaseQueryBuilder();

        when(
          () => mockClient.from('routes'),
        ).thenAnswer((_) => mockQueryBuilder);

        // Mock the select chain but we make it throw a PostgrestException
        when(() => mockQueryBuilder.select()).thenThrow(
          const PostgrestException(message: 'DB Error', code: '23505'),
        );

        expect(
          () => repository.seedRoutes('org-123'),
          throwsA(
            isA<IntegrityException>(),
          ), // Due to PostgresErrorInterceptor mapping
        );
      },
    );
  });
}
