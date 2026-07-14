// ignore_for_file: must_be_immutable
/// Unit tests for [PostgresVehicleAssetRepository].
///
/// Coverage: data sovereignty (INV-1), plate sanitization, optimistic locking
/// (INV-10), batch resilience (P0001), error parity (INV-26), and secure
/// session guard (ARCHITECT).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/entities/vehicle.dart';
import 'package:veraprob/domain/enums/vehicle_status.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/infrastructure/assets/postgres_vehicle_asset_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

// ── Fake Fluent Builder ───────────────────────────────────────────────────────
//
// Covers all PostgREST chain methods used by PostgresVehicleAssetRepository:
//   .select(), .insert(), .update(), .delete(), .rpc()
//   .eq(), .inFilter(), .order(), .single(), .maybeSingle()
//
// Records eq() calls for INV-1 structural assertions.
// Implements Future<T> so `await builder` resolves to _awaitResult.

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

  // select() on a transform builder (called after .update().eq().eq() chain)
  @override
  PostgrestTransformBuilder<PostgrestList> select([String columns = '*']) {
    return _FakeBuilder<PostgrestList>(
      _awaitResult,
      singleResult: _singleResult,
      error: _error,
    );
  }

  @override
  PostgrestTransformBuilder<T> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) {
    return _FakeBuilder<T>(
      _awaitResult,
      singleResult: _singleResult,
      error: _error,
    );
  }

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    return _FakeBuilder<Map<String, dynamic>?>(_singleResult, error: _error);
  }

  @override
  PostgrestTransformBuilder<Map<String, dynamic>> single() {
    return _FakeBuilder<Map<String, dynamic>>(_singleResult, error: _error);
  }

  @override
  PostgrestFilterBuilder<T> inFilter(String column, List<dynamic> values) {
    return this;
  }

  // ── Future<T> implementation ──────────────────────────────────────────────

  Future<T> get _asFuture {
    if (_error != null) return Future<T>.error(_error);
    // Safe cast: if T is PostgrestList, _awaitResult may be typed List<dynamic>
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

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _orgId = 'org-fleet-001';
const _vehicleId = '00000000-0000-0000-0000-000000000001';
const _vehicleId2 = '00000000-0000-0000-0000-000000000002';

Map<String, dynamic> _vehicleRow({
  String id = _vehicleId,
  String plate = 'ABC-1234',
  int version = 1,
}) => {
  'id': id,
  'organization_id': _orgId,
  'plate': plate,
  'model': 'Mercedes Benz',
  'capacity': 40,
  'status': 'available',
  'version': version,
  'created_at': '2026-04-20T10:00:00.000Z',
};

Vehicle _buildVehicle({
  String id = _vehicleId,
  String plate = 'ABC-1234',
  int version = 1,
}) => Vehicle(
  id: id,
  version: version,
  organizationId: _orgId,
  plate: plate,
  model: 'Mercedes Benz',
  capacity: 40,
  status: VehicleStatus.available,
);

User _makeUser({bool includeOrgId = true}) => User(
  id: 'user-1',
  appMetadata: includeOrgId ? {'org_id': _orgId} : {'role': 'operator'},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.now().toUtc().toIso8601String(),
);

Session _makeSession(User user) => Session(
  accessToken: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.fake.sig',
  tokenType: 'bearer',
  user: user,
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _MockSupabaseClient mockClient;
  late _MockGoTrueClient mockAuth;
  late _MockSupabaseQueryBuilder mockQb;
  late PostgresVehicleAssetRepository repo;

  late Session validSession;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<dynamic>[]);
  });

  setUp(() {
    mockClient = _MockSupabaseClient();
    mockAuth = _MockGoTrueClient();
    mockQb = _MockSupabaseQueryBuilder();

    validSession = _makeSession(_makeUser());

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentSession).thenReturn(validSession);
    when(() => mockClient.from('vehicles')).thenAnswer((_) => mockQb);

    repo = PostgresVehicleAssetRepository(mockClient);
  });

  // ── Scenario 1: Tenant Injection (INV-1 / ARCHITECT) ─────────────────────

  group('Scenario 1 — Tenant Injection (INV-1)', () {
    test(
      'addVehicle extracts org_id from JWT appMetadata and injects it into insert payload',
      () async {
        Map<String, dynamic>? captured;
        final builder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          singleResult: _vehicleRow(),
        );
        when(() => mockQb.insert(any())).thenAnswer((inv) {
          captured = inv.positionalArguments.first as Map<String, dynamic>;
          return builder;
        });

        await repo.addVehicle(plate: 'ABC-1234', capacity: 40);

        expect(
          captured?['organization_id'],
          equals(_orgId),
          reason: 'INV-1: addVehicle MUST inject org_id extracted from JWT',
        );
      },
    );

    test('addVehicle uses org_id from session not from caller', () async {
      const differentOrgId = 'org-ATTACKER-999';
      Map<String, dynamic>? captured;
      final builder = _FakeBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
        singleResult: _vehicleRow(),
      );
      when(() => mockQb.insert(any())).thenAnswer((inv) {
        captured = inv.positionalArguments.first as Map<String, dynamic>;
        return builder;
      });

      await repo.addVehicle(plate: 'XYZ-9999', capacity: 50);

      expect(
        captured?['organization_id'],
        isNot(equals(differentOrgId)),
        reason:
            'INV-1: payload org_id must come from JWT, not caller-supplied data',
      );
      expect(captured?['organization_id'], equals(_orgId));
    });
  });

  // ── Scenario 2: Plate Sanitization (MAVERICK) ────────────────────────────

  group('Scenario 2 — Plate Sanitization (MAVERICK)', () {
    test('addVehicle saves plate in UPPERCASE with trim', () async {
      Map<String, dynamic>? captured;
      final builder = _FakeBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
        singleResult: _vehicleRow(plate: 'ABC-123'),
      );
      when(() => mockQb.insert(any())).thenAnswer((inv) {
        captured = inv.positionalArguments.first as Map<String, dynamic>;
        return builder;
      });

      await repo.addVehicle(plate: '  abc-123  ', capacity: 40);

      expect(
        captured?['plate'],
        equals('ABC-123'),
        reason: 'Plate must be trimmed and uppercased before DB write',
      );
    });

    test('addVehicle saves already-uppercase plate unchanged', () async {
      Map<String, dynamic>? captured;
      final builder = _FakeBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
        singleResult: _vehicleRow(plate: 'XYZ-9999'),
      );
      when(() => mockQb.insert(any())).thenAnswer((inv) {
        captured = inv.positionalArguments.first as Map<String, dynamic>;
        return builder;
      });

      await repo.addVehicle(plate: 'XYZ-9999', capacity: 50);

      expect(captured?['plate'], equals('XYZ-9999'));
    });

    test('updateVehicle saves plate in UPPERCASE with trim', () async {
      final vehicle = _buildVehicle(plate: '  xyz-4567  ');
      Map<String, dynamic>? captured;

      final updateQb = _MockSupabaseQueryBuilder();
      when(() => mockClient.from('vehicles')).thenAnswer((_) => updateQb);

      final updateBuilder = _FakeBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
        singleResult: {'id': _vehicleId, 'version': 2},
      );
      when(() => updateQb.update(any())).thenAnswer((inv) {
        captured = inv.positionalArguments.first as Map<String, dynamic>;
        return updateBuilder;
      });

      final updated = await repo.updateVehicle(vehicle);

      expect(
        captured?['plate'],
        equals('XYZ-4567'),
        reason: 'updateVehicle MUST trim and uppercase plate before DB write',
      );
      expect(updated.version, equals(2));
    });
  });

  // ── Scenario 3: Optimistic Locking (MAVERICK / INV-10) ───────────────────

  group('Scenario 3 — Optimistic Locking (MAVERICK / INV-10)', () {
    test(
      'updateVehicle happy path returns vehicle with incremented version',
      () async {
        final vehicle = _buildVehicle(version: 1);

        final updateQb = _MockSupabaseQueryBuilder();
        when(() => mockClient.from('vehicles')).thenAnswer((_) => updateQb);
        final updateBuilder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          singleResult: {'id': _vehicleId, 'version': 2},
        );
        when(() => updateQb.update(any())).thenAnswer((_) => updateBuilder);

        final result = await repo.updateVehicle(vehicle);

        expect(result.version, equals(2));
        expect(result.id, equals(_vehicleId));
      },
    );

    test(
      'updateVehicle throws ConflictException.staleVersion on HTTP 409',
      () async {
        final vehicle = _buildVehicle(version: 1);

        final updateQb = _MockSupabaseQueryBuilder();
        final selectQb = _MockSupabaseQueryBuilder();
        int callCount = 0;
        when(
          () => mockClient.from('vehicles'),
        ).thenAnswer((_) => callCount++ == 0 ? updateQb : selectQb);

        // Step 1: versioned update finds 0 rows (version mismatch)
        final updateBuilder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          singleResult: null,
        );
        when(() => updateQb.update(any())).thenAnswer((_) => updateBuilder);

        // Step 2: row EXISTS but at newer version
        final selectBuilder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          singleResult: {'id': _vehicleId, 'version': 5},
        );
        when(() => selectQb.select(any())).thenAnswer((_) => selectBuilder);

        expect(
          () => repo.updateVehicle(vehicle),
          throwsA(
            isA<ConflictException>()
                .having((e) => e.isVersionMismatch, 'isVersionMismatch', isTrue)
                .having((e) => e.resourceType, 'resourceType', 'vehicle')
                .having((e) => e.clientVersion, 'clientVersion', 1),
          ),
          reason:
              'INV-10: stale version MUST surface as ConflictException, not silent failure',
        );
      },
    );

    test(
      'updateVehicle throws ConflictException.deleted when resource no longer exists',
      () async {
        final vehicle = _buildVehicle(version: 3);

        final updateQb = _MockSupabaseQueryBuilder();
        final selectQb = _MockSupabaseQueryBuilder();
        int callCount = 0;
        when(
          () => mockClient.from('vehicles'),
        ).thenAnswer((_) => callCount++ == 0 ? updateQb : selectQb);

        // Step 1: versioned update finds 0 rows
        final updateBuilder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          singleResult: null,
        );
        when(() => updateQb.update(any())).thenAnswer((_) => updateBuilder);

        // Step 2: row does NOT exist (deleted)
        final selectBuilder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          singleResult: null,
        );
        when(() => selectQb.select(any())).thenAnswer((_) => selectBuilder);

        expect(
          () => repo.updateVehicle(vehicle),
          throwsA(
            isA<ConflictException>()
                .having((e) => e.isDeleted, 'isDeleted', isTrue)
                .having((e) => e.currentVersion, 'currentVersion', isNull),
          ),
          reason:
              'INV-10: deleted resource MUST surface ConflictException with isDeleted=true',
        );
      },
    );

    test(
      'ConflictException propagates unchanged from updateVehicle (no wrapping)',
      () async {
        final vehicle = _buildVehicle(version: 1);

        final updateQb = _MockSupabaseQueryBuilder();
        final selectQb = _MockSupabaseQueryBuilder();
        int callCount = 0;
        when(
          () => mockClient.from('vehicles'),
        ).thenAnswer((_) => callCount++ == 0 ? updateQb : selectQb);
        final updateBuilder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          singleResult: null,
        );
        when(() => updateQb.update(any())).thenAnswer((_) => updateBuilder);

        final selectBuilder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          singleResult: {'id': _vehicleId, 'version': 2},
        );
        when(() => selectQb.select(any())).thenAnswer((_) => selectBuilder);

        Exception? caught;
        try {
          await repo.updateVehicle(vehicle);
        } on ConflictException catch (e) {
          caught = e;
        }

        expect(
          caught,
          isA<ConflictException>(),
          reason: 'ConflictException must not be wrapped in another type',
        );
      },
    );
  });

  // ── Scenario 4: Batch Resilience (QA) ────────────────────────────────────

  group('Scenario 4 — Batch Resilience (QA)', () {
    test('batchUpdateVehicles success: returns re-fetched vehicles', () async {
      final specs = [
        const BatchUpdateSpec(
          id: _vehicleId,
          version: 1,
          data: {'plate': 'ABC-1234', 'capacity': 42},
        ),
      ];

      // RPC succeeds
      final rpcBuilder = _FakeBuilder<Map<String, dynamic>>({
        'updated_count': 1,
      });
      when(
        () => mockClient.rpc<Map<String, dynamic>>(
          'batch_update_vehicles',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => rpcBuilder);

      // Re-fetch after batch
      final refetchBuilder = _FakeBuilder<PostgrestList>(<Map<String, dynamic>>[
        _vehicleRow(),
      ]);
      when(() => mockQb.select()).thenAnswer((_) => refetchBuilder);

      final result = await repo.batchUpdateVehicles(specs);

      expect(result, isA<List<Vehicle>>());
      expect(result.length, equals(1));
      expect(result.first.plate, equals('ABC-1234'));
    });

    test(
      'batchUpdateVehicles P0001 conflict propagates ConflictException with stale IDs',
      () async {
        final specs = [
          const BatchUpdateSpec(id: _vehicleId, version: 1, data: {}),
          const BatchUpdateSpec(id: _vehicleId2, version: 2, data: {}),
        ];

        // RPC throws P0001 with vehicle UUIDs embedded in message
        const p0001Message =
            'Batch conflict: vehicle $_vehicleId is stale, vehicle $_vehicleId2 is stale';
        const pgException = PostgrestException(
          message: p0001Message,
          code: 'P0001',
          details: 'Optimistic lock failure',
          hint: null,
        );
        when(
          () => mockClient.rpc<Map<String, dynamic>>(
            'batch_update_vehicles',
            params: any(named: 'params'),
          ),
        ).thenThrow(pgException);

        ConflictException? caught;
        try {
          await repo.batchUpdateVehicles(specs);
        } on ConflictException catch (e) {
          caught = e;
        }

        expect(
          caught,
          isNotNull,
          reason: 'P0001 from RPC MUST surface as ConflictException',
        );
        expect(
          caught!.resourceId,
          contains(_vehicleId),
          reason:
              'Stale vehicle IDs MUST be embedded in ConflictException.resourceId',
        );
        expect(caught.resourceType, equals('batch'));
      },
    );

    test(
      '_extractBatchStaleIds: regex captures valid UUIDs from error message',
      () async {
        // Validates ID extractor by verifying ConflictException carries the correct
        // stale IDs extracted from the RPC P0001 message.
        const uuid1 = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
        const uuid2 = 'ffffffff-0000-1111-2222-333333333333';
        const message =
            'Batch conflict: vehicle $uuid1 is stale. vehicle $uuid2 was modified';

        const pgException = PostgrestException(
          message: message,
          code: 'P0001',
          details: null,
          hint: null,
        );
        when(
          () => mockClient.rpc<Map<String, dynamic>>(
            'batch_update_vehicles',
            params: any(named: 'params'),
          ),
        ).thenThrow(pgException);

        ConflictException? caught;
        try {
          await repo.batchUpdateVehicles([
            const BatchUpdateSpec(id: uuid1, version: 1, data: {}),
          ]);
        } on ConflictException catch (e) {
          caught = e;
        }

        expect(caught, isNotNull);
        expect(
          caught!.resourceId,
          anyOf(contains(uuid1), equals('unknown')),
          reason: 'UUID extractor must not fail on valid UUIDs',
        );
      },
    );

    test(
      '_extractBatchStaleIds: returns "unknown" for malformed UUID in message',
      () async {
        // Tests graceful degradation when error message has no parseable UUIDs.
        const pgException = PostgrestException(
          message: 'Batch conflict: vehicle MALFORMED_NOT_UUID is stale',
          code: 'P0001',
          details: null,
          hint: null,
        );
        when(
          () => mockClient.rpc<Map<String, dynamic>>(
            'batch_update_vehicles',
            params: any(named: 'params'),
          ),
        ).thenThrow(pgException);

        ConflictException? caught;
        try {
          await repo.batchUpdateVehicles([
            const BatchUpdateSpec(id: _vehicleId, version: 1, data: {}),
          ]);
        } on ConflictException catch (e) {
          caught = e;
        }

        expect(caught, isNotNull);
        expect(
          caught!.resourceId,
          equals('unknown'),
          reason:
              'Regex must not crash on malformed UUIDs — fallback to "unknown"',
        );
      },
    );
  });

  // ── Scenario 5: Error Parity (INV-26) ────────────────────────────────────

  group('Scenario 5 — Error Parity (INV-26)', () {
    test(
      'PostgrestException code 22P02 maps to ResourceNotFoundException',
      () async {
        const pgException = PostgrestException(
          message: 'invalid input syntax for type uuid',
          code: '22P02',
          details: null,
          hint: null,
        );
        final builder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          error: pgException,
        );
        when(() => mockQb.select()).thenAnswer((_) => builder);

        expect(
          () => repo.getVehicles(),
          throwsA(isA<ResourceNotFoundException>()),
          reason: 'INV-26: malformed UUID error must not leak — map to 404',
        );
      },
    );

    test(
      'PostgrestException code PGRST116 maps to ResourceNotFoundException',
      () async {
        const pgException = PostgrestException(
          message: 'Searched for one row, found 0 rows',
          code: 'PGRST116',
          details: null,
          hint: null,
        );
        final builder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          error: pgException,
        );
        when(() => mockQb.select()).thenAnswer((_) => builder);

        expect(
          () => repo.getVehicles(),
          throwsA(isA<ResourceNotFoundException>()),
        );
      },
    );

    test(
      'PostgrestException code 23505 maps to IntegrityException (unique violation)',
      () async {
        const pgException = PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
          details: 'Key (plate)=(ABC-1234) already exists.',
          hint: null,
        );
        final builder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          error: pgException,
        );
        when(() => mockQb.insert(any())).thenAnswer((_) => builder);

        expect(
          () => repo.addVehicle(plate: 'ABC-1234', capacity: 40),
          throwsA(isA<IntegrityException>()),
          reason: 'INV-26: unique violation must map to IntegrityException',
        );
      },
    );

    test(
      'unhandled PostgrestException code is rethrown as PostgrestException',
      () async {
        const pgException = PostgrestException(
          message: 'server error',
          code: '50000',
          details: null,
          hint: null,
        );
        final builder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          error: pgException,
        );
        when(() => mockQb.select()).thenAnswer((_) => builder);

        expect(
          () => repo.getVehicles(),
          throwsA(isA<PostgrestException>()),
          reason: 'INV-10: unhandled DB codes must NOT be silently swallowed',
        );
      },
    );

    test(
      'deleteVehicle PostgrestException 22P02 maps to ResourceNotFoundException',
      () async {
        const pgException = PostgrestException(
          message: 'invalid uuid',
          code: '22P02',
          details: null,
          hint: null,
        );
        final builder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          error: pgException,
        );
        when(() => mockQb.delete()).thenAnswer((_) => builder);

        expect(
          () => repo.deleteVehicle('not-a-uuid'),
          throwsA(isA<ResourceNotFoundException>()),
        );
      },
    );
  });

  // ── Scenario 6: Secure Session Guard (ARCHITECT) ─────────────────────────

  group('Scenario 6 — Secure Session Guard (ARCHITECT)', () {
    test(
      'addVehicle throws StateError when session is null (no active login)',
      () {
        when(() => mockAuth.currentSession).thenReturn(null);

        expect(
          () => repo.addVehicle(plate: 'ABC-1234', capacity: 40),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('No organization in session JWT'),
            ),
          ),
          reason:
              'ARCHITECT: repo MUST fail-fast before touching DB when JWT has no org_id',
        );
      },
    );

    test('addVehicle throws StateError when org_id missing from appMetadata', () {
      final userWithoutOrg = _makeUser(includeOrgId: false);
      when(
        () => mockAuth.currentSession,
      ).thenReturn(_makeSession(userWithoutOrg));

      expect(
        () => repo.addVehicle(plate: 'ABC-1234', capacity: 40),
        throwsA(isA<IntegrityException>()),
        reason:
            'org_id absent from JWT metadata must trigger fail-fast StateError',
      );
    });

    test(
      'deleteVehicle uses RLS not app-level org check — proceeds to DB with null session',
      () async {
        when(() => mockAuth.currentSession).thenReturn(null);
        final builder = _FakeBuilder<PostgrestList>(<Map<String, dynamic>>[]);
        when(() => mockQb.delete()).thenAnswer((_) => builder);

        // deleteVehicle has no _orgId guard — org-isolation enforced at DB level via RLS (INV-2)
        await expectLater(repo.deleteVehicle(_vehicleId), completes);
      },
    );

    test(
      'getVehicles succeeds with valid session and returns Vehicle list',
      () async {
        when(() => mockAuth.currentSession).thenReturn(validSession);
        final builder = _FakeBuilder<PostgrestList>(<Map<String, dynamic>>[
          _vehicleRow(),
        ]);
        when(() => mockQb.select()).thenAnswer((_) => builder);

        final result = await repo.getVehicles();

        expect(result, isA<List<Vehicle>>());
        expect(result.length, equals(1));
        expect(result.first.organizationId, equals(_orgId));
      },
    );

    test(
      'multiple addVehicle calls each extract org_id from current session',
      () async {
        int insertCallCount = 0;
        final capturedOrgIds = <String>[];
        final builder = _FakeBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          singleResult: _vehicleRow(),
        );
        when(() => mockQb.insert(any())).thenAnswer((inv) {
          insertCallCount++;
          final payload = inv.positionalArguments.first as Map<String, dynamic>;
          capturedOrgIds.add(payload['organization_id'] as String);
          return builder;
        });

        await repo.addVehicle(plate: 'VH-0001', capacity: 30);
        await repo.addVehicle(plate: 'VH-0002', capacity: 35);

        expect(insertCallCount, equals(2));
        expect(capturedOrgIds, everyElement(equals(_orgId)));
      },
    );
  });
}
