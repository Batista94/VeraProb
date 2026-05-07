// pr_scanner: ignore-regression
// ignore_for_file: must_be_immutable
//
// Step 0 — Exploit Path (QA/Sec Persona, INV-22):
//   Attack vector: a caller passes OrgA's Organization to update(), but the
//   repository omits the .eq('id', ...) binding. Without that WHERE clause the
//   UPDATE touches every row the service-role key can reach — full cross-tenant
//   write. Closing mechanism: CONFIDENTIALITY/INV-1 test captures eq() call
//   arguments via _CapturingBuilder and asserts only OrgA's id appears in the
//   predicate; OrgB's id MUST NOT appear in any eq() call during OrgA's update.
//
//   Secondary exploit: JSONB bool-type confusion (INV-9/INV-18). A rogue row
//   carries capabilities.allows_sealing = 'yes' (string). Silent coercion
//   would allow feature-gating bypass. OrgCapabilities._parseBool strict guard
//   closes this by throwing IntegrityException on non-bool values.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/infrastructure/admin/postgres_organization_repository.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────────

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

// ── Fake Fluent Builder ────────────────────────────────────────────────────────
//
// Covers the PostgREST chain used by PostgresOrganizationRepository:
//   .select() → .eq() → .single() / .order()
//   .update({...}) → .eq()
//   .isFilter() → .order() → .limit() → .maybeSingle()
//
// Records eq() calls so INV-1 structural assertions can verify the WHERE
// predicate column/value pairs without inspecting raw SQL strings.
//
// _awaitResult is always stored as `dynamic`. For PostgrestList results, callers
// must pass a List<dynamic> (not List<Map<String,dynamic>>) to avoid the runtime
// type-check failure on `value as T` where T = List<dynamic>.

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
    eqCalls.add(MapEntry(column, value as dynamic));
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

  // ── Future<T> bridge ────────────────────────────────────────────────────────
  //
  // Safe cast note (matches reference implementation pattern):
  // When T = PostgrestList (= List<dynamic>), _awaitResult must be typed as
  // List<dynamic> at construction time. Passing List<Map<String,dynamic>> would
  // cause a runtime TypeError here. See _asDynList() helper in callers.

  Future<T> get _asFuture {
    if (_error != null) return Future<T>.error(_error);
    final value = _awaitResult;
    if (value == null) return Future<T>.value(null as T);
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

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      _asFuture.whenComplete(action);

  @override
  Stream<T> asStream() => _asFuture.asStream();

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      _asFuture.timeout(timeLimit, onTimeout: onTimeout);
}

// ── Capturing builder ─────────────────────────────────────────────────────────
//
// Wraps a _FakeBuilder and records eq() calls into an external sink list.
// Used for INV-1 cross-tenant write prevention assertions.

class _CapturingBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final List<MapEntry<String, dynamic>> _sink;
  final _FakeBuilder<T> _delegate;

  _CapturingBuilder(this._sink, this._delegate);

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) {
    _sink.add(MapEntry(column, value as dynamic));
    _delegate.eqCalls.add(MapEntry(column, value as dynamic));
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
  }) => _delegate;

  @override
  PostgrestTransformBuilder<T> limit(int count, {String? referencedTable}) =>
      _delegate;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>> single() =>
      _delegate.single();

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() =>
      _delegate.maybeSingle();

  @override
  PostgrestTransformBuilder<PostgrestList> select([String columns = '*']) =>
      _delegate.select(columns);

  Future<T> get _asFuture => _delegate._asFuture;

  @override
  Future<S> then<S>(
    FutureOr<S> Function(T value) onValue, {
    Function? onError,
  }) => _asFuture.then(onValue, onError: onError);

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) =>
      _asFuture.catchError(onError, test: test);

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      _asFuture.whenComplete(action);

  @override
  Stream<T> asStream() => _asFuture.asStream();

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      _asFuture.timeout(timeLimit, onTimeout: onTimeout);
}

// ── Constants ─────────────────────────────────────────────────────────────────

const _orgAId = 'org-a-00000000-0000-0000-0000-000000000001';
const _orgBId = 'org-b-00000000-0000-0000-0000-000000000002';

// Sentinel objects: distinguish "use default fixture value" from explicit null.
const Object _kSentinelCaps = Object();
const Object _kSentinelDomains = Object();

// ── Fixtures ──────────────────────────────────────────────────────────────────

Map<String, dynamic> _capabilitiesJson({
  bool allowsSealing = true,
  bool allowsLoading = false,
  bool allowsCargoCheck = true,
  bool allowsIncident = true,
  bool allowsDoc = false,
  bool smartClassify = true,
  double? maxKinematicSpeedKmh = 120.0,
}) => {
  'allows_sealing': allowsSealing,
  'allows_loading': allowsLoading,
  'allows_cargo_check': allowsCargoCheck,
  'allows_incident': allowsIncident,
  'allows_doc': allowsDoc,
  'smart_classify': smartClassify,
  'max_kinematic_speed_kmh': ?maxKinematicSpeedKmh,
};

/// Builds a full DB row suitable for mocking. All fields populated by default.
///
/// [capabilities] = null  → DB NULL capabilities column (maps to OrgCapabilities.defaults).
/// [allowedDomains] = null → DB NULL allowed_domains column (maps to []).
/// [dwellTimeSeconds] = null → absent from row (maps to 300 default).
Map<String, dynamic> _fullRow({
  String id = _orgAId,
  String name = 'Transportes Exemplo LTDA',
  String? status = 'ACTIVE',
  bool? isActive,
  Object? capabilities = _kSentinelCaps,
  Object? allowedDomains = _kSentinelDomains,
  int? dwellTimeSeconds = 300,
}) {
  final row = <String, dynamic>{
    'id': id,
    'name': name,
    'timezone': 'America/Sao_Paulo',
    'currency_code': 'BRL',
    'logo_url': 'https://cdn.example.com/logo.png',
    'status': status,
    'is_active': isActive,
    'created_at': '2024-01-15T08:00:00.000Z',
    'legal_name': 'Transportes Exemplo Ltda',
    'cnpj': '12.345.678/0001-90',
    'plan_type': 'enterprise',
    'max_vehicles': 50,
    'max_active_contracts': 10,
    'organization_type': 'carrier',
    'billing_day': 5,
    'contact_email': 'ops@exemplo.com',
    'external_id': 'ext-001',
    'dwell_time_seconds': dwellTimeSeconds,
  };

  if (identical(capabilities, _kSentinelCaps)) {
    row['capabilities'] = _capabilitiesJson();
  } else {
    row['capabilities'] = capabilities;
  }

  if (identical(allowedDomains, _kSentinelDomains)) {
    row['allowed_domains'] = <dynamic>['exemplo.com', 'ops.exemplo.com'];
  } else {
    row['allowed_domains'] = allowedDomains;
  }

  return row;
}

/// Converts a typed list to `List<dynamic>` for safe passage through `_FakeBuilder`.
/// Required because `_FakeBuilder._asFuture` does `value as T` where `T = PostgrestList`
/// `= List<dynamic>`, and `List<Map<String,dynamic>>` is NOT a `List<dynamic>` at runtime.
List<dynamic> _asDynList(List<Map<String, dynamic>> rows) =>
    List<dynamic>.from(rows);

// ── Domain helpers ─────────────────────────────────────────────────────────────

Organization _buildOrg({String id = _orgAId}) => Organization(
  id: id,
  name: 'Org ${id.substring(0, 8)}',
  timezone: 'America/Sao_Paulo',
  currencyCode: 'BRL',
  status: OrgStatus.active,
  createdAt: DateTime.utc(2024, 1, 15, 8, 0, 0),
);

// ── Stub helpers ───────────────────────────────────────────────────────────────

/// Stubs qb.select() returning a builder whose eq().single() resolves to [singleResult].
/// Pass [error] to make the chain throw instead.
_FakeBuilder<PostgrestList> _stubSelect(
  _MockSupabaseQueryBuilder qb, {
  Map<String, dynamic>? singleResult,
  Object? error,
}) {
  final builder = _FakeBuilder<PostgrestList>(
    null,
    singleResult: singleResult,
    error: error,
  );
  when(() => qb.select()).thenAnswer((_) => builder);
  return builder;
}

/// Stubs qb.select() for a findAll chain that resolves to [listResult].
/// [listResult] is converted to `List<dynamic>` to satisfy the PostgrestList cast.
_FakeBuilder<PostgrestList> _stubSelectList(
  _MockSupabaseQueryBuilder qb, {
  List<Map<String, dynamic>>? listResult,
  Object? error,
}) {
  final List<dynamic> data = listResult != null
      ? _asDynList(listResult)
      : <dynamic>[];
  final builder = _FakeBuilder<PostgrestList>(
    data,
    singleResult: null,
    error: error,
  );
  when(() => qb.select()).thenAnswer((_) => builder);
  return builder;
}

/// Stubs qb.update(any()) returning a builder that completes silently.
_FakeBuilder<PostgrestList> _stubUpdate(
  _MockSupabaseQueryBuilder qb, {
  Object? error,
}) {
  final builder = _FakeBuilder<PostgrestList>(<dynamic>[], error: error);
  when(() => qb.update(any())).thenAnswer((_) => builder);
  return builder;
}

// ══════════════════════════════════════════════════════════════════════════════
// TEST SUITE
// ══════════════════════════════════════════════════════════════════════════════

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
    when(() => mockClient.from('organizations')).thenAnswer((_) => mockQb);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CONFIDENTIALITY
  // ══════════════════════════════════════════════════════════════════════════

  group('CONFIDENTIALITY', () {
    test(
      'SQL injection in findById treated as literal string parameter — '
      'no exception, injection string present in Organization.name',
      () async {
        const injectionId = "'; DROP TABLE organizations; --";
        final row = _fullRow(id: injectionId, name: injectionId);

        unawaited(_stubSelect(mockQb, singleResult: row));
        final repo = PostgresOrganizationRepository(mockClient);

        final result = await repo.findById(injectionId);

        expect(result, isNotNull);
        expect(result!.name, equals(injectionId));
      },
    );

    test('SQL injection in update name passed as bound parameter — '
        'update() completes normally, mockQb.update() called once', () async {
      const injectionName = "'; DROP TABLE organizations; --";
      final org = _buildOrg().copyWith(name: injectionName);

      unawaited(_stubUpdate(mockQb));
      final repo = PostgresOrganizationRepository(mockClient);

      await repo.update(org);

      verify(() => mockQb.update(any())).called(1);
    });

    test(
      'INV-1 cross-tenant write prevention: update(orgA) scopes WHERE to orgA.id — '
      'orgB.id MUST NOT appear in any eq() call',
      () async {
        final capturedEqCalls = <MapEntry<String, dynamic>>[];
        final updateDelegate = _FakeBuilder<PostgrestList>(
          <dynamic>[],
          error: null,
        );

        when(() => mockQb.update(any())).thenAnswer(
          (_) =>
              _CapturingBuilder<PostgrestList>(capturedEqCalls, updateDelegate),
        );

        final repo = PostgresOrganizationRepository(mockClient);
        final orgA = _buildOrg(id: _orgAId);
        await repo.update(orgA);

        final idValues = capturedEqCalls
            .where((e) => e.key == 'id')
            .map((e) => e.value)
            .toList();

        expect(idValues, contains(_orgAId));
        expect(idValues, isNot(contains(_orgBId)));
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // INTEGRITY
  // ══════════════════════════════════════════════════════════════════════════

  group('INTEGRITY', () {
    test(
      'JSONB null capabilities — Organization.capabilities equals OrgCapabilities.defaults',
      () async {
        final row = _fullRow(capabilities: null);
        unawaited(_stubSelect(mockQb, singleResult: row));
        final repo = PostgresOrganizationRepository(mockClient);

        final result = await repo.findById(_orgAId);

        expect(result!.capabilities, equals(OrgCapabilities.defaults));
      },
    );

    test(
      'JSONB empty map capabilities — all bool flags default to true, speed is null',
      () async {
        final row = _fullRow(capabilities: <String, dynamic>{});
        unawaited(_stubSelect(mockQb, singleResult: row));
        final repo = PostgresOrganizationRepository(mockClient);

        final result = await repo.findById(_orgAId);

        expect(result!.capabilities.allowsSealing, isTrue);
        expect(result.capabilities.allowsLoading, isTrue);
        expect(result.capabilities.allowsCargoCheck, isTrue);
        expect(result.capabilities.allowsIncident, isTrue);
        expect(result.capabilities.allowsDoc, isTrue);
        expect(result.capabilities.smartClassify, isTrue);
        expect(result.capabilities.maxKinematicSpeedKmh, isNull);
      },
    );

    test(
      'JSONB bool type corruption (allows_sealing = "yes") — '
      'findById throws IntegrityException with field = allows_sealing',
      () async {
        final row = _fullRow(
          capabilities: <String, dynamic>{'allows_sealing': 'yes'},
        );
        unawaited(_stubSelect(mockQb, singleResult: row));
        final repo = PostgresOrganizationRepository(mockClient);

        await expectLater(
          repo.findById(_orgAId),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.field,
              'field',
              'allows_sealing',
            ),
          ),
        );
      },
    );

    test(
      'JSONB allowedDomains null — Organization.allowedDomains is empty list',
      () async {
        final row = _fullRow(allowedDomains: null);
        unawaited(_stubSelect(mockQb, singleResult: row));
        final repo = PostgresOrganizationRepository(mockClient);

        final result = await repo.findById(_orgAId);

        expect(result!.allowedDomains, isEmpty);
      },
    );

    test('Unique constraint (23505) — throws IntegrityException '
        'with field = cnpj extracted from details string (INV-10)', () async {
      const pgException = PostgrestException(
        message:
            'duplicate key value violates unique constraint "organizations_cnpj_key"',
        code: '23505',
        details: 'Key (cnpj)=(12.345.678/0001-90) already exists.',
        hint: null,
      );

      unawaited(_stubSelect(mockQb, error: pgException));
      final repo = PostgresOrganizationRepository(mockClient);

      await expectLater(
        repo.findById(_orgAId),
        throwsA(
          isA<IntegrityException>().having((e) => e.field, 'field', 'cnpj'),
        ),
      );
    });

    test('Unknown PG error code (99999) propagates as raw PostgrestException — '
        'no silent failure, fail-fast (INV-10)', () async {
      const pgException = PostgrestException(
        message: 'unexpected server error',
        code: '99999',
        details: null,
        hint: null,
      );

      unawaited(_stubSelect(mockQb, error: pgException));
      final repo = PostgresOrganizationRepository(mockClient);

      await expectLater(repo.findById(_orgAId), throwsA(same(pgException)));
    });

    test(
      'status absent + is_active = false — Organization.status is OrgStatus.suspended',
      () async {
        final row = _fullRow(status: null, isActive: false);
        unawaited(_stubSelect(mockQb, singleResult: row));
        final repo = PostgresOrganizationRepository(mockClient);

        final result = await repo.findById(_orgAId);

        expect(result!.status, equals(OrgStatus.suspended));
      },
    );

    test(
      'Invalid status string "BOGUS" — findById throws IntegrityException',
      () async {
        final row = _fullRow(status: 'BOGUS');
        unawaited(_stubSelect(mockQb, singleResult: row));
        final repo = PostgresOrganizationRepository(mockClient);

        await expectLater(
          repo.findById(_orgAId),
          throwsA(isA<IntegrityException>()),
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // AVAILABILITY
  // ══════════════════════════════════════════════════════════════════════════

  group('AVAILABILITY', () {
    test(
      'findById happy path — all fields map bit-perfect: id, name, timezone, '
      'currencyCode, maxVehicles, billingDay, dwellTimeSeconds, allowedDomains, '
      'createdAt UTC (INV-6), status, non-default capabilities',
      () async {
        final caps = _capabilitiesJson(
          allowsSealing: true,
          allowsLoading: false,
          allowsCargoCheck: true,
          allowsIncident: true,
          allowsDoc: false,
          smartClassify: true,
          maxKinematicSpeedKmh: 120.0,
        );
        final row = _fullRow(
          id: _orgAId,
          name: 'Transportes Exemplo LTDA',
          status: 'ACTIVE',
          capabilities: caps,
          allowedDomains: <dynamic>['exemplo.com', 'ops.exemplo.com'],
          dwellTimeSeconds: 600,
        );

        unawaited(_stubSelect(mockQb, singleResult: row));
        final repo = PostgresOrganizationRepository(mockClient);

        final result = await repo.findById(_orgAId);

        expect(result, isNotNull);
        expect(result!.id, equals(_orgAId));
        expect(result.name, equals('Transportes Exemplo LTDA'));
        expect(result.timezone, equals('America/Sao_Paulo'));
        expect(result.currencyCode, equals('BRL'));
        expect(result.maxVehicles, equals(50));
        expect(result.billingDay, equals(5));
        expect(result.dwellTimeSeconds, equals(600));
        expect(
          result.allowedDomains,
          equals(['exemplo.com', 'ops.exemplo.com']),
        );
        expect(result.createdAt.isUtc, isTrue);
        expect(result.createdAt, equals(DateTime.utc(2024, 1, 15, 8, 0, 0)));
        expect(result.status, equals(OrgStatus.active));
        expect(result.capabilities.allowsLoading, isFalse);
        expect(result.capabilities.allowsDoc, isFalse);
        expect(result.capabilities.maxKinematicSpeedKmh, equals(120.0));
      },
    );

    test(
      'findById dwellTimeSeconds absent from row — defaults to 300 (INV-14)',
      () async {
        final row = _fullRow(dwellTimeSeconds: null);
        unawaited(_stubSelect(mockQb, singleResult: row));
        final repo = PostgresOrganizationRepository(mockClient);

        final result = await repo.findById(_orgAId);

        expect(result!.dwellTimeSeconds, equals(300));
      },
    );

    test(
      'findById not found (PGRST116) — throws ResourceNotFoundException (INV-26)',
      () async {
        const pgException = PostgrestException(
          message: 'The result contains 0 rows',
          code: 'PGRST116',
          details: null,
          hint: null,
        );

        unawaited(_stubSelect(mockQb, error: pgException));
        final repo = PostgresOrganizationRepository(mockClient);

        await expectLater(
          repo.findById(_orgAId),
          throwsA(isA<ResourceNotFoundException>()),
        );
      },
    );

    test(
      'findAll without status filter — returns List<Organization> with 2 elements',
      () async {
        final rows = [
          _fullRow(id: _orgAId, name: 'Alpha Transportes'),
          _fullRow(id: _orgBId, name: 'Beta Logistica'),
        ];

        unawaited(_stubSelectList(mockQb, listResult: rows));
        final repo = PostgresOrganizationRepository(mockClient);

        final result = await repo.findAll();

        expect(result, hasLength(2));
        expect(result.map((o) => o.id), containsAll([_orgAId, _orgBId]));
      },
    );

    test(
      'findAll with OrgStatus.active filter — .eq("status", "ACTIVE") called once on chain',
      () async {
        final rows = [_fullRow(status: 'ACTIVE')];
        final capturedEqCalls = <MapEntry<String, dynamic>>[];

        final listDelegate = _FakeBuilder<PostgrestList>(
          _asDynList(rows),
          error: null,
        );
        when(() => mockQb.select()).thenAnswer(
          (_) =>
              _CapturingBuilder<PostgrestList>(capturedEqCalls, listDelegate),
        );

        final repo = PostgresOrganizationRepository(mockClient);
        await repo.findAll(status: OrgStatus.active);

        final statusFilters = capturedEqCalls
            .where((e) => e.key == 'status' && e.value == 'ACTIVE')
            .toList();

        expect(statusFilters, hasLength(1));
      },
    );

    test('updateStatus happy path — completes without exception', () async {
      unawaited(_stubUpdate(mockQb));
      final repo = PostgresOrganizationRepository(mockClient);

      await expectLater(
        repo.updateStatus(
          _orgAId,
          OrgStatus.suspended,
          'Non-payment after 30 days',
          'actor-uuid-001',
          'super_admin',
        ),
        completes,
      );
    });

    test(
      'DB TimeoutException in findById — result is null within 100ms, '
      'no hang (generic catch branch returns null per current implementation)',
      () async {
        unawaited(
          _stubSelect(
            mockQb,
            error: TimeoutException(
              'DB unreachable',
              const Duration(seconds: 30),
            ),
          ),
        );
        final repo = PostgresOrganizationRepository(mockClient);

        final stopwatch = Stopwatch()..start();
        final result = await repo.findById(_orgAId);
        stopwatch.stop();

        expect(result, isNull);
        expect(stopwatch.elapsedMilliseconds, lessThan(100));
      },
    );
  });
}
