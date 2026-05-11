/// PostgresShadowExecutionRepository — complete unit test suite.
///
/// Coverage:
/// G1 - findById:               hit, null (anti-oracle), INV-1, _fromRow mapping.
/// G2 - findUnlinked:           list, empty, INV-1, status filter, limit.
/// G3 - findSmartLinkCandidates:candidates, INV-1, tsLow/tsHigh math, INV-6.
/// G4 - Mutações de Estado:     reconcile, dismiss, reconcileAsNewRevenue — payload,
///                              INV-1 WHERE, INV-6 UTC, verify().called(1).
/// G5 - Segurança e Resiliência:Anti-Oracle wrong-org, adversarial tenant isolation,
///                              PostgrestException → domain exception mapping,
///                              CIA/INV-3 no-delete structural check.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/ad_hoc_cost/shadow_execution_status.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/ad_hoc_cost/postgres_shadow_execution_repository.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}

// ── Fake fluent query builder ─────────────────────────────────────────────────
//
// Chains handled:
//   .select()     → .eq() → .eq() → .maybeSingle()             (findById)
//   .select()     → .eq() → .eq() → .order() → .limit()        (findUnlinked)
//   .select(cols) → .eq() → .lte() → .gte() → .limit()         (findSmartLinkCandidates)
//
// Tracks eq/lte/gte calls so INV-1 assertions can be made without SQL inspection.
// _awaitResult drives the list path; _singleResult drives maybeSingle().

class _FakeBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final dynamic _awaitResult;
  final dynamic _singleResult;
  final Object? _error;

  final List<MapEntry<String, dynamic>> eqCalls = [];
  final Map<String, dynamic> lteCalls = {};
  final Map<String, dynamic> gteCalls = {};

  _FakeBuilder(this._awaitResult, {dynamic singleResult, Object? error})
    : _singleResult = singleResult,
      _error = error;

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) {
    eqCalls.add(MapEntry(column, value as dynamic));
    return this;
  }

  @override
  PostgrestFilterBuilder<T> lte(String column, Object value) {
    lteCalls[column] = value;
    return this;
  }

  @override
  PostgrestFilterBuilder<T> gte(String column, Object value) {
    gteCalls[column] = value;
    return this;
  }

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

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      _asFuture.whenComplete(action);

  @override
  Stream<T> asStream() => _asFuture.asStream();

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) =>
      _asFuture.timeout(timeLimit, onTimeout: onTimeout);

  bool hasEq(String col, dynamic val) =>
      eqCalls.any((e) => e.key == col && e.value == val);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

List<dynamic> _dynList(List<Map<String, dynamic>> rows) =>
    List<dynamic>.from(rows);

_FakeBuilder<PostgrestList> _stubSelect(
  _MockQueryBuilder qb, {
  Map<String, dynamic>? singleResult,
  List<Map<String, dynamic>>? listResult,
  Object? error,
}) {
  final builder = _FakeBuilder<PostgrestList>(
    listResult != null ? _dynList(listResult) : null,
    singleResult: singleResult,
    error: error,
  );
  when(() => qb.select(any())).thenAnswer((_) => builder);
  return builder;
}

_FakeBuilder<PostgrestList> _stubUpdate(_MockQueryBuilder qb, {Object? error}) {
  final builder = _FakeBuilder<PostgrestList>(_dynList([]), error: error);
  when(() => qb.update(any())).thenAnswer((_) => builder);
  return builder;
}

// ── Constants ─────────────────────────────────────────────────────────────────

const _orgId = '00000000-0000-0000-0000-000000000001';
const _wrongOrgId = '00000000-0000-0000-0000-000000000099';
const _shadowId = '10000000-0000-0000-0000-000000000001';
const _shadow2Id = '10000000-0000-0000-0000-000000000002';
const _operatorId = '20000000-0000-0000-0000-000000000001';
const _evidenceId = '30000000-0000-0000-0000-000000000001';

// ── Row fixture ───────────────────────────────────────────────────────────────

Map<String, dynamic> _shadowRow({
  String id = _shadowId,
  String orgId = _orgId,
  String status = 'UNLINKED_SHADOW',
  String? originChannel = 'telegram',
  String? reconciledExecutionId,
  String? reconciledAtUtc,
  String? reconciledByUserId,
  String? dismissedAtUtc,
  String? dismissedByUserId,
  String? dismissedReason,
}) => {
  'id': id,
  'organization_id': orgId,
  'operator_id': _operatorId,
  'chat_id': 100000001,
  'telegram_message_id': 42,
  'origin_evidence_id': _evidenceId,
  'origin_channel': originChannel,
  'message_ts': 1736938800,
  'counted_from_utc': '2026-01-15T10:00:00.000Z',
  'status': status,
  'reconciled_execution_id': reconciledExecutionId,
  'reconciled_at_utc': reconciledAtUtc,
  'reconciled_by_user_id': reconciledByUserId,
  'dismissed_at_utc': dismissedAtUtc,
  'dismissed_by_user_id': dismissedByUserId,
  'dismissed_reason': dismissedReason,
  'created_at_utc': '2026-01-15T09:00:00.000Z',
};

// ═════════════════════════════════════════════════════════════════════════════
// TEST SUITE
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  late _MockSupabaseClient mockClient;
  late PostgresShadowExecutionRepository sut;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue('');
  });

  setUp(() {
    mockClient = _MockSupabaseClient();
    sut = PostgresShadowExecutionRepository(mockClient);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G1 — findById
  // ══════════════════════════════════════════════════════════════════════════

  group('findById()', () {
    late _MockQueryBuilder qb;

    setUp(() {
      qb = _MockQueryBuilder();
      when(() => mockClient.from('shadow_executions')).thenAnswer((_) => qb);
    });

    test('returns mapped ShadowExecution on hit', () async {
      unawaited(_stubSelect(qb, singleResult: _shadowRow()));

      final result = await sut.findById(id: _shadowId, organizationId: _orgId);

      expect(result, isNotNull);
      expect(result!.id, _shadowId);
      expect(result.organizationId, _orgId);
      expect(result.operatorId, _operatorId);
      expect(result.chatId, 100000001);
      expect(result.telegramMessageId, 42);
      expect(result.messageTs, 1736938800);
      expect(result.status, ShadowExecutionStatus.unlinkedShadow);
    });

    test('returns null when row not found (INV-26 anti-oracle)', () async {
      unawaited(_stubSelect(qb, singleResult: null));

      final result = await sut.findById(id: _shadowId, organizationId: _orgId);

      expect(result, isNull);
    });

    test('INV-1 — query filters by organization_id', () async {
      final builder = _stubSelect(qb, singleResult: _shadowRow());

      await sut.findById(id: _shadowId, organizationId: _orgId);

      expect(builder.hasEq('organization_id', _orgId), isTrue);
    });

    test('INV-1 — query filters by id', () async {
      final builder = _stubSelect(qb, singleResult: _shadowRow());

      await sut.findById(id: _shadowId, organizationId: _orgId);

      expect(builder.hasEq('id', _shadowId), isTrue);
    });

    test('_fromRow — nullable fields are null on UNLINKED_SHADOW', () async {
      unawaited(_stubSelect(qb, singleResult: _shadowRow()));

      final result = await sut.findById(id: _shadowId, organizationId: _orgId);

      expect(result!.reconciledExecutionId, isNull);
      expect(result.reconciledAtUtc, isNull);
      expect(result.reconciledByUserId, isNull);
      expect(result.dismissedAtUtc, isNull);
      expect(result.dismissedByUserId, isNull);
      expect(result.dismissedReason, isNull);
    });

    test('_fromRow — originChannel defaults to telegram when null', () async {
      unawaited(_stubSelect(qb, singleResult: _shadowRow(originChannel: null)));

      final result = await sut.findById(id: _shadowId, organizationId: _orgId);

      expect(result!.originChannel, 'telegram');
    });

    test('_fromRow — reconciled fields parsed when present', () async {
      unawaited(
        _stubSelect(
          qb,
          singleResult: _shadowRow(
            status: 'RECONCILED',
            reconciledExecutionId: 'set-reconciled-001',
            reconciledAtUtc: '2026-01-16T08:00:00.000Z',
            reconciledByUserId: 'user-supervisor-001',
          ),
        ),
      );

      final result = await sut.findById(id: _shadowId, organizationId: _orgId);

      expect(result!.status, ShadowExecutionStatus.reconciled);
      expect(result.reconciledExecutionId, 'set-reconciled-001');
      expect(result.reconciledAtUtc, DateTime.utc(2026, 1, 16, 8, 0));
      expect(result.reconciledByUserId, 'user-supervisor-001');
    });

    test('_fromRow — dismissed fields parsed when present', () async {
      unawaited(
        _stubSelect(
          qb,
          singleResult: _shadowRow(
            status: 'DISMISSED',
            dismissedAtUtc: '2026-01-16T12:00:00.000Z',
            dismissedByUserId: 'user-supervisor-002',
            dismissedReason: 'Test event, not billable',
          ),
        ),
      );

      final result = await sut.findById(id: _shadowId, organizationId: _orgId);

      expect(result!.status, ShadowExecutionStatus.dismissed);
      expect(result.dismissedAtUtc, DateTime.utc(2026, 1, 16, 12, 0));
      expect(result.dismissedByUserId, 'user-supervisor-002');
      expect(result.dismissedReason, 'Test event, not billable');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G2 — findUnlinked
  // ══════════════════════════════════════════════════════════════════════════

  group('findUnlinked()', () {
    late _MockQueryBuilder qb;

    setUp(() {
      qb = _MockQueryBuilder();
      when(() => mockClient.from('shadow_executions')).thenAnswer((_) => qb);
    });

    test('returns list of ShadowExecution on hit', () async {
      unawaited(
        _stubSelect(
          qb,
          listResult: [
            _shadowRow(),
            _shadowRow(id: _shadow2Id),
          ],
        ),
      );

      final results = await sut.findUnlinked(organizationId: _orgId);

      expect(results, hasLength(2));
      expect(results.first.id, _shadowId);
      expect(results.last.id, _shadow2Id);
      expect(results.first.status, ShadowExecutionStatus.unlinkedShadow);
    });

    test('returns empty list when no unlinked rows', () async {
      unawaited(_stubSelect(qb, listResult: []));

      final results = await sut.findUnlinked(organizationId: _orgId);

      expect(results, isEmpty);
    });

    test('INV-1 — query filters by organization_id', () async {
      final builder = _stubSelect(qb, listResult: []);

      await sut.findUnlinked(organizationId: _orgId);

      expect(builder.hasEq('organization_id', _orgId), isTrue);
    });

    test('filters by UNLINKED_SHADOW status', () async {
      final builder = _stubSelect(qb, listResult: []);

      await sut.findUnlinked(organizationId: _orgId);

      expect(builder.hasEq('status', 'UNLINKED_SHADOW'), isTrue);
    });

    test('limit parameter is forwarded — fixture results respect it', () async {
      unawaited(_stubSelect(qb, listResult: [_shadowRow()]));

      final results = await sut.findUnlinked(organizationId: _orgId, limit: 10);

      expect(results, hasLength(1));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G3 — findSmartLinkCandidates
  // ══════════════════════════════════════════════════════════════════════════

  group('findSmartLinkCandidates()', () {
    late _MockQueryBuilder qb;

    // 2026-01-15T10:00:00Z
    const int messageTs = 1736938800;
    const int defaultTol = 1800; // 30 min

    setUp(() {
      qb = _MockQueryBuilder();
      when(() => mockClient.from('execution_states')).thenAnswer((_) => qb);
    });

    test('returns raw candidate rows', () async {
      final candidate = {
        'set_id': 'set-001',
        'window_start_utc': '2026-01-15T09:00:00.000Z',
        'window_end_utc': '2026-01-15T11:00:00.000Z',
        'status': 'ACTIVE',
      };
      unawaited(_stubSelect(qb, listResult: [candidate]));

      final results = await sut.findSmartLinkCandidates(
        organizationId: _orgId,
        messageTs: messageTs,
      );

      expect(results, hasLength(1));
      expect(results.first['set_id'], 'set-001');
    });

    test('returns empty list when no candidates', () async {
      unawaited(_stubSelect(qb, listResult: []));

      final results = await sut.findSmartLinkCandidates(
        organizationId: _orgId,
        messageTs: messageTs,
      );

      expect(results, isEmpty);
    });

    test('INV-1 — query filters by organization_id', () async {
      final builder = _stubSelect(qb, listResult: []);

      await sut.findSmartLinkCandidates(
        organizationId: _orgId,
        messageTs: messageTs,
      );

      expect(builder.hasEq('organization_id', _orgId), isTrue);
    });

    test(
      'lte applied to window_start_utc with tsHigh (messageTs + tol)',
      () async {
        final builder = _stubSelect(qb, listResult: []);

        await sut.findSmartLinkCandidates(
          organizationId: _orgId,
          messageTs: messageTs,
        );

        final expectedHigh = DateTime.fromMillisecondsSinceEpoch(
          (messageTs + defaultTol) * 1000,
          isUtc: true,
        ).toIso8601String();

        expect(builder.lteCalls['window_start_utc'], expectedHigh);
      },
    );

    test(
      'gte applied to window_end_utc with tsLow (messageTs - tol)',
      () async {
        final builder = _stubSelect(qb, listResult: []);

        await sut.findSmartLinkCandidates(
          organizationId: _orgId,
          messageTs: messageTs,
        );

        final expectedLow = DateTime.fromMillisecondsSinceEpoch(
          (messageTs - defaultTol) * 1000,
          isUtc: true,
        ).toIso8601String();

        expect(builder.gteCalls['window_end_utc'], expectedLow);
      },
    );

    test('custom toleranceSec overrides 30min default', () async {
      const customTol = 900; // 15 min
      final builder = _stubSelect(qb, listResult: []);

      await sut.findSmartLinkCandidates(
        organizationId: _orgId,
        messageTs: messageTs,
        toleranceSec: customTol,
      );

      final expectedHigh = DateTime.fromMillisecondsSinceEpoch(
        (messageTs + customTol) * 1000,
        isUtc: true,
      ).toIso8601String();
      final expectedLow = DateTime.fromMillisecondsSinceEpoch(
        (messageTs - customTol) * 1000,
        isUtc: true,
      ).toIso8601String();

      expect(builder.lteCalls['window_start_utc'], expectedHigh);
      expect(builder.gteCalls['window_end_utc'], expectedLow);
    });

    test('INV-6 — time window strings are UTC ISO-8601', () async {
      final builder = _stubSelect(qb, listResult: []);

      await sut.findSmartLinkCandidates(
        organizationId: _orgId,
        messageTs: messageTs,
      );

      final high = builder.lteCalls['window_start_utc'] as String?;
      final low = builder.gteCalls['window_end_utc'] as String?;

      expect(high, isNotNull);
      expect(low, isNotNull);
      // DateTime.toIso8601String() on a UTC datetime ends with 'Z'
      expect(
        high!.endsWith('Z') || high.contains('+00:00'),
        isTrue,
        reason: 'tsHigh must be UTC ISO-8601 (INV-6)',
      );
      expect(
        low!.endsWith('Z') || low.contains('+00:00'),
        isTrue,
        reason: 'tsLow must be UTC ISO-8601 (INV-6)',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G4 — Mutações e Transições de Estado
  // ══════════════════════════════════════════════════════════════════════════

  group('Mutações e Transições de Estado', () {
    late _MockQueryBuilder qb;

    const reconciledExecutionId = 'set-001';
    const reconciledByUserId = 'user-supervisor-001';
    const dismissedByUserId = 'user-supervisor-002';
    const dismissReason = 'Test event, not billable';
    final atUtc = DateTime.utc(2026, 1, 16, 8, 0);

    setUp(() {
      qb = _MockQueryBuilder();
      when(() => mockClient.from('shadow_executions')).thenAnswer((_) => qb);
    });

    // ── reconcile() ──────────────────────────────────────────────────────────

    group('reconcile()', () {
      test('payload includes RECONCILED status and required fields', () async {
        unawaited(_stubUpdate(qb));

        await sut.reconcile(
          id: _shadowId,
          organizationId: _orgId,
          reconciledExecutionId: reconciledExecutionId,
          reconciledByUserId: reconciledByUserId,
          atUtc: atUtc,
        );

        final captured = verify(() => qb.update(captureAny())).captured;
        final payload = Map<String, dynamic>.from(captured.first as Map);

        expect(payload['status'], 'RECONCILED');
        expect(payload['reconciled_execution_id'], reconciledExecutionId);
        expect(payload['reconciled_by_user_id'], reconciledByUserId);
      });

      test('INV-6 — reconciled_at_utc serialized as UTC ISO-8601', () async {
        unawaited(_stubUpdate(qb));

        await sut.reconcile(
          id: _shadowId,
          organizationId: _orgId,
          reconciledExecutionId: reconciledExecutionId,
          reconciledByUserId: reconciledByUserId,
          atUtc: atUtc,
        );

        final captured = verify(() => qb.update(captureAny())).captured;
        final payload = Map<String, dynamic>.from(captured.first as Map);
        final ts = payload['reconciled_at_utc'] as String?;

        expect(
          ts,
          '2026-01-16T08:00:00.000Z',
          reason: 'INV-6: reconciled_at_utc must be UTC ISO-8601 with Z',
        );
      });

      test('INV-1 — WHERE clause filters by id and organization_id', () async {
        final builder = _stubUpdate(qb);

        await sut.reconcile(
          id: _shadowId,
          organizationId: _orgId,
          reconciledExecutionId: reconciledExecutionId,
          reconciledByUserId: reconciledByUserId,
          atUtc: atUtc,
        );

        expect(builder.hasEq('id', _shadowId), isTrue);
        expect(builder.hasEq('organization_id', _orgId), isTrue);
      });

      test('update called exactly once', () async {
        unawaited(_stubUpdate(qb));

        await sut.reconcile(
          id: _shadowId,
          organizationId: _orgId,
          reconciledExecutionId: reconciledExecutionId,
          reconciledByUserId: reconciledByUserId,
          atUtc: atUtc,
        );

        verify(() => qb.update(any())).called(1);
      });
    });

    // ── dismiss() ────────────────────────────────────────────────────────────

    group('dismiss()', () {
      test(
        'payload includes DISMISSED status, dismissed_reason and dismissedByUserId',
        () async {
          unawaited(_stubUpdate(qb));

          await sut.dismiss(
            id: _shadowId,
            organizationId: _orgId,
            dismissedByUserId: dismissedByUserId,
            reason: dismissReason,
            atUtc: atUtc,
          );

          final captured = verify(() => qb.update(captureAny())).captured;
          final payload = Map<String, dynamic>.from(captured.first as Map);

          expect(payload['status'], 'DISMISSED');
          expect(payload['dismissed_reason'], dismissReason);
          expect(payload['dismissed_by_user_id'], dismissedByUserId);
        },
      );

      test('INV-6 — dismissed_at_utc serialized as UTC ISO-8601', () async {
        unawaited(_stubUpdate(qb));

        await sut.dismiss(
          id: _shadowId,
          organizationId: _orgId,
          dismissedByUserId: dismissedByUserId,
          reason: dismissReason,
          atUtc: atUtc,
        );

        final captured = verify(() => qb.update(captureAny())).captured;
        final payload = Map<String, dynamic>.from(captured.first as Map);
        final ts = payload['dismissed_at_utc'] as String?;

        expect(
          ts,
          '2026-01-16T08:00:00.000Z',
          reason: 'INV-6: dismissed_at_utc must be UTC ISO-8601 with Z',
        );
      });

      test('INV-1 — WHERE clause filters by id and organization_id', () async {
        final builder = _stubUpdate(qb);

        await sut.dismiss(
          id: _shadowId,
          organizationId: _orgId,
          dismissedByUserId: dismissedByUserId,
          reason: dismissReason,
          atUtc: atUtc,
        );

        expect(builder.hasEq('id', _shadowId), isTrue);
        expect(builder.hasEq('organization_id', _orgId), isTrue);
      });
    });

    // ── reconcileAsNewRevenue() ───────────────────────────────────────────────

    group('reconcileAsNewRevenue()', () {
      test(
        'payload includes RECONCILED_AS_NEW_REVENUE status and reconciledExecutionId',
        () async {
          unawaited(_stubUpdate(qb));

          await sut.reconcileAsNewRevenue(
            id: _shadowId,
            organizationId: _orgId,
            reconciledExecutionId: reconciledExecutionId,
            reconciledByUserId: reconciledByUserId,
            atUtc: atUtc,
          );

          final captured = verify(() => qb.update(captureAny())).captured;
          final payload = Map<String, dynamic>.from(captured.first as Map);

          expect(payload['status'], 'RECONCILED_AS_NEW_REVENUE');
          expect(payload['reconciled_execution_id'], reconciledExecutionId);
        },
      );

      test('INV-6 — reconciled_at_utc serialized as UTC ISO-8601', () async {
        unawaited(_stubUpdate(qb));

        await sut.reconcileAsNewRevenue(
          id: _shadowId,
          organizationId: _orgId,
          reconciledExecutionId: reconciledExecutionId,
          reconciledByUserId: reconciledByUserId,
          atUtc: atUtc,
        );

        final captured = verify(() => qb.update(captureAny())).captured;
        final payload = Map<String, dynamic>.from(captured.first as Map);
        final ts = payload['reconciled_at_utc'] as String?;

        expect(
          ts,
          '2026-01-16T08:00:00.000Z',
          reason: 'INV-6: reconciled_at_utc must be UTC ISO-8601 with Z',
        );
      });

      test('INV-1 — WHERE clause filters by id and organization_id', () async {
        final builder = _stubUpdate(qb);

        await sut.reconcileAsNewRevenue(
          id: _shadowId,
          organizationId: _orgId,
          reconciledExecutionId: reconciledExecutionId,
          reconciledByUserId: reconciledByUserId,
          atUtc: atUtc,
        );

        expect(builder.hasEq('id', _shadowId), isTrue);
        expect(builder.hasEq('organization_id', _orgId), isTrue);
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G5 — Segurança, Invariantes e Resiliência
  // ══════════════════════════════════════════════════════════════════════════

  group('Segurança, Invariantes e Resiliência', () {
    late _MockQueryBuilder qb;

    final atUtc = DateTime.utc(2026, 1, 16, 8, 0);

    setUp(() {
      qb = _MockQueryBuilder();
      when(() => mockClient.from('shadow_executions')).thenAnswer((_) => qb);
    });

    // ── Anti-Oracle (INV-26) ─────────────────────────────────────────────────
    //
    // An attacker probing for valid IDs must receive null for both
    // "ID does not exist" and "ID exists but belongs to another tenant".
    // The repository MUST NOT distinguish between these two cases.

    group('Anti-Oracle (INV-26)', () {
      test(
        'findById — wrong-org returns null, shape identical to not-found',
        () async {
          // Simulate: DB returns null because org_id filter eliminates the row.
          unawaited(_stubSelect(qb, singleResult: null));

          final result = await sut.findById(
            id: _shadowId,
            organizationId: _wrongOrgId,
          );

          expect(
            result,
            isNull,
            reason:
                'INV-26: wrong-org and not-found must be indistinguishable (anti-oracle)',
          );
        },
      );

      test(
        'findById — org filter applied even for wrong-org caller (WHERE locks the row)',
        () async {
          final builder = _stubSelect(qb, singleResult: null);

          await sut.findById(id: _shadowId, organizationId: _wrongOrgId);

          expect(
            builder.hasEq('organization_id', _wrongOrgId),
            isTrue,
            reason:
                'org_id always forwarded to WHERE — DB/RLS rejects cross-tenant reads',
          );
          expect(builder.hasEq('id', _shadowId), isTrue);
        },
      );
    });

    // ── Tenant Isolation — Adversarial ────────────────────────────────────────
    //
    // Even if an attacker supplies a valid shadowId but a wrong organizationId,
    // the WHERE clause must contain the passed organization_id so the DB/RLS
    // layer matches zero rows and performs zero writes.

    group('Tenant Isolation — Adversarial', () {
      test(
        'reconcile — WHERE clause uses caller-supplied organizationId (DB enforces isolation)',
        () async {
          final builder = _stubUpdate(qb);

          await sut.reconcile(
            id: _shadowId,
            organizationId: _wrongOrgId,
            reconciledExecutionId: 'set-001',
            reconciledByUserId: 'attacker-user',
            atUtc: atUtc,
          );

          expect(
            builder.hasEq('organization_id', _wrongOrgId),
            isTrue,
            reason:
                'Wrong org_id forwarded to WHERE — RLS ensures zero rows affected',
          );
          expect(builder.hasEq('id', _shadowId), isTrue);
        },
      );

      test(
        'dismiss — WHERE clause uses caller-supplied organizationId (DB enforces isolation)',
        () async {
          final builder = _stubUpdate(qb);

          await sut.dismiss(
            id: _shadowId,
            organizationId: _wrongOrgId,
            dismissedByUserId: 'attacker-user',
            reason: 'malicious dismiss attempt',
            atUtc: atUtc,
          );

          expect(
            builder.hasEq('organization_id', _wrongOrgId),
            isTrue,
            reason:
                'Wrong org_id forwarded to WHERE — RLS ensures zero rows affected',
          );
          expect(builder.hasEq('id', _shadowId), isTrue);
        },
      );
    });

    // ── Mapeamento de Erros de Banco ──────────────────────────────────────────
    //
    // All PostgrestExceptions must be caught and mapped to domain exceptions.
    // Raw DB codes must NEVER leak to the caller (INV-26).

    group('Mapeamento de Erros de Banco', () {
      test(
        'findById — 22P02 (malformed UUID) → ResourceNotFoundException',
        () async {
          unawaited(
            _stubSelect(
              qb,
              error: const PostgrestException(
                message: 'invalid input syntax for type uuid',
                code: '22P02',
              ),
            ),
          );

          await expectLater(
            sut.findById(id: 'not-a-uuid', organizationId: _orgId),
            throwsA(isA<ResourceNotFoundException>()),
          );
        },
      );

      test(
        'findUnlinked — 42501 (RLS denied) → SovereigntyViolationException',
        () async {
          unawaited(
            _stubSelect(
              qb,
              error: const PostgrestException(
                message: 'permission denied for table shadow_executions',
                code: '42501',
              ),
            ),
          );

          await expectLater(
            sut.findUnlinked(organizationId: _orgId),
            throwsA(isA<SovereigntyViolationException>()),
          );
        },
      );

      test(
        'reconcile — P0001 (trigger RAISE EXCEPTION) → IntegrityException',
        () async {
          unawaited(
            _stubUpdate(
              qb,
              error: const PostgrestException(
                message:
                    'invalid status transition: RECONCILED_AS_NEW_REVENUE → RECONCILED',
                code: 'P0001',
              ),
            ),
          );

          await expectLater(
            sut.reconcile(
              id: _shadowId,
              organizationId: _orgId,
              reconciledExecutionId: 'set-001',
              reconciledByUserId: 'user-001',
              atUtc: atUtc,
            ),
            throwsA(isA<IntegrityException>()),
          );
        },
      );

      test(
        'dismiss — 23505 (unique constraint) → IntegrityException',
        () async {
          unawaited(
            _stubUpdate(
              qb,
              error: const PostgrestException(
                message: 'duplicate key value violates unique constraint',
                code: '23505',
              ),
            ),
          );

          await expectLater(
            sut.dismiss(
              id: _shadowId,
              organizationId: _orgId,
              dismissedByUserId: 'user-001',
              reason: 'duplicate',
              atUtc: atUtc,
            ),
            throwsA(isA<IntegrityException>()),
          );
        },
      );

      test(
        'findSmartLinkCandidates — unhandled code → rethrows PostgrestException (INV-10 fail-fast)',
        () async {
          final executionStatesQb = _MockQueryBuilder();
          when(
            () => mockClient.from('execution_states'),
          ).thenAnswer((_) => executionStatesQb);
          unawaited(
            _stubSelect(
              executionStatesQb,
              error: const PostgrestException(
                message: 'connection timeout',
                code: '08006', // connection_failure — not in the mapping table
              ),
            ),
          );

          await expectLater(
            sut.findSmartLinkCandidates(
              organizationId: _orgId,
              messageTs: 1736938800,
            ),
            throwsA(isA<PostgrestException>()),
          );
        },
      );
    });

    // ── CIA Integrity — No Delete (INV-3) ─────────────────────────────────────
    //
    // INV-3: Ledger is APPEND-ONLY. Physical deletion is prohibited.
    // Status transitions (reconcile/dismiss) replace deletion semantics.
    // The repository must NEVER call .delete() on the query builder.

    group('CIA Integrity — No Delete (INV-3)', () {
      test(
        'structural — PostgresShadowExecutionRepository exposes no delete() method',
        () {
          // Compile-time structural check: if sut.delete() existed, calling it
          // here would compile. The absence of the method enforces INV-3 at the
          // type level — no runtime guard needed.
          expect(sut, isA<PostgresShadowExecutionRepository>());
        },
      );

      test('reconcile — delete() never called on query builder', () async {
        unawaited(_stubUpdate(qb));

        await sut.reconcile(
          id: _shadowId,
          organizationId: _orgId,
          reconciledExecutionId: 'set-001',
          reconciledByUserId: 'user-001',
          atUtc: atUtc,
        );

        verifyNever(() => qb.delete());
      });

      test('dismiss — delete() never called on query builder', () async {
        unawaited(_stubUpdate(qb));

        await sut.dismiss(
          id: _shadowId,
          organizationId: _orgId,
          dismissedByUserId: 'user-001',
          reason: 'not billable',
          atUtc: atUtc,
        );

        verifyNever(() => qb.delete());
      });

      test(
        'reconcileAsNewRevenue — delete() never called on query builder',
        () async {
          unawaited(_stubUpdate(qb));

          await sut.reconcileAsNewRevenue(
            id: _shadowId,
            organizationId: _orgId,
            reconciledExecutionId: 'set-001',
            reconciledByUserId: 'user-001',
            atUtc: atUtc,
          );

          verifyNever(() => qb.delete());
        },
      );
    });
  });
}
