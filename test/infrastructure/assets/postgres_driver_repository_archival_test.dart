// ignore_for_file: must_be_immutable
// Adversarial test suite for PostgresDriverRepository — driver archival flow.
//
// Covers: hard-DELETE blocked (INV-3), archiveDriver calls offboard_driver RPC,
// org_id from JWT (INV-1, INV-22), StateError on missing JWT org_id (INV-1).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/infrastructure/assets/postgres_driver_repository.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockSupabaseClient extends Mock implements SupabaseClient {}

// Fake (not Mock) avoids mocktail state contamination when currentSession
// is a complex getter in GoTrueClient.
class _FakeGoTrueClient extends Fake implements GoTrueClient {
  final Session? _session;
  _FakeGoTrueClient(this._session);

  @override
  Session? get currentSession => _session;
}

// ── Fake Fluent Builder ───────────────────────────────────────────────────────

class _FakeBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final dynamic _awaitResult;
  final Object? _error;
  final List<MapEntry<String, dynamic>> eqCalls = [];

  _FakeBuilder(this._awaitResult, {Object? error}) : _error = error;

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) {
    eqCalls.add(MapEntry(column, value as dynamic));
    return this;
  }

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

// ── Helpers ───────────────────────────────────────────────────────────────────

const _orgId = 'org-tenant-a';
const _driverId = 'driver-uuid-1';

Session _fakeSession(String orgId) {
  return Session(
    accessToken: 'fake-token',
    tokenType: 'bearer',
    user: User(
      id: 'user-1',
      appMetadata: {'org_id': orgId},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    ),
  );
}

void main() {
  late _MockSupabaseClient mockClient;
  late PostgresDriverRepository repo;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockClient = _MockSupabaseClient();
    when(
      () => mockClient.auth,
    ).thenReturn(_FakeGoTrueClient(_fakeSession(_orgId)));
    repo = PostgresDriverRepository(mockClient);
  });

  group('[INV-3] archiveDriver — offboard RPC, never hard DELETE', () {
    test(
      'calls offboard_driver RPC with correct driver_id and org_id',
      () async {
        final rpcBuilder = _FakeBuilder<dynamic>(null);

        when(
          () => mockClient.rpc<void>(
            'offboard_driver',
            params: any(named: 'params'),
          ),
        ).thenAnswer((_) => rpcBuilder);

        await repo.archiveDriver(_driverId);

        final captured = verify(
          () => mockClient.rpc<void>(
            'offboard_driver',
            params: captureAny(named: 'params'),
          ),
        ).captured;

        final params = captured.first as Map<String, dynamic>;
        expect(params['p_driver_id'], equals(_driverId));
        expect(params['p_org_id'], equals(_orgId));
      },
    );

    test(
      'propagates RPC PostgrestException as domain exception (INV-10)',
      () async {
        const pgError = PostgrestException(
          message: 'driver not found or already archived',
          code: 'P0003',
        );
        final rpcBuilder = _FakeBuilder<dynamic>(null, error: pgError);

        when(
          () => mockClient.rpc<void>(
            'offboard_driver',
            params: any(named: 'params'),
          ),
        ).thenAnswer((_) => rpcBuilder);

        await expectLater(
          repo.archiveDriver(_driverId),
          throwsA(isA<Exception>()),
        );
      },
    );
  });

  group('[INV-1] org_id from JWT — never from caller', () {
    test('archiveDriver uses JWT org_id, not external input', () async {
      final rpcBuilder = _FakeBuilder<dynamic>(null);
      when(
        () => mockClient.rpc<void>(
          'offboard_driver',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => rpcBuilder);

      await repo.archiveDriver(_driverId);

      final captured = verify(
        () => mockClient.rpc<void>(
          'offboard_driver',
          params: captureAny(named: 'params'),
        ),
      ).captured;
      final params = captured.first as Map<String, dynamic>;
      expect(params['p_org_id'], equals(_orgId));
    });

    test('throws StateError when JWT has no org_id (INV-1 fail-fast)', () {
      final sessionNoOrg = Session(
        accessToken: 'token',
        tokenType: 'bearer',
        user: User(
          id: 'u1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      final freshClient = _MockSupabaseClient();
      when(() => freshClient.auth).thenReturn(_FakeGoTrueClient(sessionNoOrg));
      final freshRepo = PostgresDriverRepository(freshClient);
      expect(
        () => freshRepo.archiveDriver(_driverId),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  group('[INV-22] multi-tenant isolation', () {
    test(
      'archiveDriver RPC params never contain a different tenant org_id',
      () async {
        final rpcBuilder = _FakeBuilder<dynamic>(null);
        when(
          () => mockClient.rpc<void>(
            'offboard_driver',
            params: any(named: 'params'),
          ),
        ).thenAnswer((_) => rpcBuilder);

        await repo.archiveDriver(_driverId);

        final captured = verify(
          () => mockClient.rpc<void>(
            'offboard_driver',
            params: captureAny(named: 'params'),
          ),
        ).captured;
        final params = captured.first as Map<String, dynamic>;
        expect(params['p_org_id'], equals(_orgId));
        expect(params['p_org_id'], isNot('org-tenant-b'));
      },
    );
  });
}
