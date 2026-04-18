/// Unit tests for [SupabaseForensicThrottleGateway] (CX-05-v3.0).
///
/// Verifies the adapter correctly marshals the three PL/pgSQL RPCs from
/// migration `20260418000002_forensic_throttle_state.sql` and surfaces the
/// server-computed `wait_seconds` verdict as a [ThrottleBlockedException].
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/justification/forensic_throttle_gateway.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/supabase_forensic_throttle_gateway.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockSupabaseClient extends Mock implements SupabaseClient {}

/// Resolves to [_result] when awaited — mimics `PostgrestFilterBuilder` which
/// is what `SupabaseClient.rpc()` returns and which itself is a [Future].
class FakePostgrestFilterBuilder extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  final dynamic _result;

  FakePostgrestFilterBuilder(this._result);

  @override
  Future<S> then<S>(
    FutureOr<S> Function(dynamic value) onValue, {
    Function? onError,
  }) {
    return Future<dynamic>.value(_result).then(onValue, onError: onError);
  }

  @override
  Future<dynamic> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) {
    return Future<dynamic>.value(_result);
  }

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) {
    return Future<dynamic>.value(_result).whenComplete(action);
  }

  @override
  Stream<dynamic> asStream() => Stream.value(_result);

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) {
    return Future<dynamic>.value(_result);
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockSupabaseClient mockClient;
  late SupabaseForensicThrottleGateway gateway;

  const orgId = 'org-001';

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockClient = MockSupabaseClient();
    gateway = SupabaseForensicThrottleGateway(mockClient);
  });

  group('SupabaseForensicThrottleGateway — assertAllowed', () {
    test('returns without throw when RPC replies allowed=true', () async {
      when(
        () => mockClient.rpc(
          'check_forensic_throttle',
          params: any(named: 'params'),
        ),
      ).thenAnswer(
        (_) => FakePostgrestFilterBuilder([
          {'allowed': true, 'wait_seconds': 0},
        ]),
      );

      await gateway.assertAllowed(organizationId: orgId);

      verify(
        () => mockClient.rpc(
          'check_forensic_throttle',
          params: {'p_org_id': orgId},
        ),
      ).called(1);
    });

    test(
      'throws ThrottleBlockedException(wait_seconds) when allowed=false',
      () async {
        when(
          () => mockClient.rpc(
            'check_forensic_throttle',
            params: any(named: 'params'),
          ),
        ).thenAnswer(
          (_) => FakePostgrestFilterBuilder([
            {'allowed': false, 'wait_seconds': 4},
          ]),
        );

        await expectLater(
          gateway.assertAllowed(organizationId: orgId),
          throwsA(
            isA<ThrottleBlockedException>().having(
              (e) => e.waitSeconds,
              'waitSeconds',
              4,
            ),
          ),
        );
      },
    );

    test('handles empty RPC response as allowed (no state row yet)', () async {
      when(
        () => mockClient.rpc(
          'check_forensic_throttle',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(<dynamic>[]));

      await gateway.assertAllowed(organizationId: orgId);
    });
  });

  group('SupabaseForensicThrottleGateway — recordFailure', () {
    test('invokes record_forensic_failure with p_org_id', () async {
      when(
        () => mockClient.rpc(
          'record_forensic_failure',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(null));

      await gateway.recordFailure(organizationId: orgId);

      verify(
        () => mockClient.rpc(
          'record_forensic_failure',
          params: {'p_org_id': orgId},
        ),
      ).called(1);
    });
  });

  group('SupabaseForensicThrottleGateway — recordSuccess', () {
    test('invokes reset_forensic_throttle with p_org_id', () async {
      when(
        () => mockClient.rpc(
          'reset_forensic_throttle',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(null));

      await gateway.recordSuccess(organizationId: orgId);

      verify(
        () => mockClient.rpc(
          'reset_forensic_throttle',
          params: {'p_org_id': orgId},
        ),
      ).called(1);
    });
  });
}
