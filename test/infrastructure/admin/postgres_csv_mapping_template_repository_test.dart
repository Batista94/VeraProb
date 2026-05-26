import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/infrastructure/admin/postgres_csv_mapping_template_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

class _FakeBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final dynamic _awaitResult;
  final dynamic _singleResult;
  final Object? _error;

  final List<MapEntry<String, dynamic>> eqCalls = [];

  _FakeBuilder(this._awaitResult, {dynamic singleResult, Object? error})
    : _singleResult = singleResult,
      _error = error;

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) {
    eqCalls.add(MapEntry(column, value));
    return this;
  }

  @override
  PostgrestFilterBuilder<T> isFilter(String column, Object? value) => this;

  @override
  PostgrestTransformBuilder<T> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) =>
      _FakeBuilder<T>(_awaitResult, singleResult: _singleResult, error: _error);

  @override
  PostgrestTransformBuilder<T> limit(int count, {String? referencedTable}) =>
      _FakeBuilder<T>(_awaitResult, singleResult: _singleResult, error: _error);

  @override
  PostgrestTransformBuilder<PostgrestList> select([String columns = '*']) =>
      _FakeBuilder<PostgrestList>(
        _awaitResult,
        singleResult: _singleResult,
        error: _error,
      );

  @override
  PostgrestTransformBuilder<Map<String, dynamic>> single() =>
      _FakeBuilder<Map<String, dynamic>>(_singleResult, error: _error);

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() =>
      _FakeBuilder<Map<String, dynamic>?>(_singleResult, error: _error);

  Future<T> get _asFuture {
    if (_error != null) return Future<T>.error(_error);
    final value = _awaitResult;
    if (value == null) return Future<T>.value(null as T);
    if (value is List<dynamic> && value is! T) {
      return Future<T>.value(value.cast<Map<String, dynamic>>() as T);
    }
    return Future<T>.value(value as T);
  }

  @override
  Future<S> then<S>(
    FutureOr<S> Function(T value) onValue, {
    Function? onError,
  }) => _asFuture.then(onValue, onError: onError);

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) =>
      _asFuture.catchError(onError, test: test);
}

class _CapturingBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final List<MapEntry<String, dynamic>> _sink;
  final _FakeBuilder<T> _delegate;

  _CapturingBuilder(this._sink, this._delegate);

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) {
    _sink.add(MapEntry(column, value));
    _delegate.eqCalls.add(MapEntry(column, value));
    return this;
  }

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() =>
      _delegate.maybeSingle();

  @override
  PostgrestTransformBuilder<PostgrestList> select([String columns = '*']) =>
      _delegate.select(columns);

  @override
  Future<S> then<S>(
    FutureOr<S> Function(T value) onValue, {
    Function? onError,
  }) => _delegate._asFuture.then(onValue, onError: onError);

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) =>
      _delegate._asFuture.catchError(onError, test: test);
}

const _orgId = 'org-11111111-1111-1111-1111-111111111111';

Map<String, dynamic> _templateRow({
  String id = 'tmpl-11111111-1111-1111-1111-111111111111',
  String name = 'Test Template',
  String targetEntity = 'asset',
  bool isDefault = false,
  int version = 1,
}) => {
  'id': id,
  'organization_id': _orgId,
  'name': name,
  'target_entity': targetEntity,
  'column_mappings': [
    {'csv_header': 'Plate', 'target_field': 'identifier', 'required': true},
  ],
  'is_default': isDefault,
  'version': version,
  'created_at': '2026-05-26T00:00:00.000Z',
  'updated_at': '2026-05-26T00:00:00.000Z',
  'created_by': 'user-11111111-1111-1111-1111-111111111111',
};

void main() {
  late _MockSupabaseClient mockClient;
  late _MockSupabaseQueryBuilder mockQb;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<dynamic>[]);
  });

  setUp(() {
    mockClient = _MockSupabaseClient();
    mockQb = _MockSupabaseQueryBuilder();
    when(
      () => mockClient.from('csv_mapping_templates'),
    ).thenAnswer((_) => mockQb);
  });

  group('PostgresCsvMappingTemplateRepository', () {
    test('getTemplates parses mappings correctly', () async {
      final row = _templateRow();
      final builder = _FakeBuilder<PostgrestList>([row]);
      when(() => mockQb.select()).thenAnswer((_) => builder);

      final repo = PostgresCsvMappingTemplateRepository(mockClient);
      final results = await repo.getTemplates();

      expect(results, hasLength(1));
      expect(results.first.name, equals('Test Template'));
      expect(results.first.columnMappings, hasLength(1));
      expect(results.first.columnMappings.first.csvHeader, equals('Plate'));
    });

    test('getDefaultTemplate returns correct template or null', () async {
      final row = _templateRow(isDefault: true);
      final builder = _FakeBuilder<PostgrestList>(null, singleResult: row);
      final capturedEqCalls = <MapEntry<String, dynamic>>[];

      when(() => mockQb.select()).thenAnswer(
        (_) => _CapturingBuilder<PostgrestList>(capturedEqCalls, builder),
      );

      final repo = PostgresCsvMappingTemplateRepository(mockClient);
      final result = await repo.getDefaultTemplate('asset');

      expect(result, isNotNull);
      expect(result!.isDefault, isTrue);
      final targetEntityCall = capturedEqCalls.any(
        (e) => e.key == 'target_entity' && e.value == 'asset',
      );
      final isDefaultCall = capturedEqCalls.any(
        (e) => e.key == 'is_default' && e.value == true,
      );
      expect(targetEntityCall, isTrue);
      expect(isDefaultCall, isTrue);
    });
  });
}
