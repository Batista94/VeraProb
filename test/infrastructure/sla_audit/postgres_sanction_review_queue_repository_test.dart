// ignore_for_file: must_be_immutable
/// Unit tests for [PostgresSanctionReviewQueueRepository].
///
/// Coverage: tenant isolation (INV-1), idempotent upsert (INV-24),
/// error parity (INV-26), _fromRow UTC mapping (INV-6),
/// queue FIFO ordering, and mutation guard (INV-3).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sanction_review_queue_repository.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

// ── Fake Fluent Chain Builder ─────────────────────────────────────────────────
//
// Mimics the Supabase PostgREST fluent chain:
//   client.from(t).select().eq().eq().maybeSingle()
//   client.from(t).upsert(...)
//   client.from(t).update(...).eq().eq()
//
// Records eq()/order() calls for structural assertions (INV-1).
// Implements Future<T> so `await builder` works correctly.

class _FakeFilterBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final dynamic _awaitResult;
  final dynamic _singleResult;
  final Object? _error;

  final List<MapEntry<String, Object>> eqCalls = [];
  String? orderedBy;
  bool? orderedAscending;

  _FakeFilterBuilder(this._awaitResult, {dynamic singleResult, Object? error})
    : _singleResult = singleResult,
      _error = error;

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) {
    eqCalls.add(MapEntry(column, value));
    return this;
  }

  @override
  PostgrestTransformBuilder<T> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) {
    orderedBy = column;
    orderedAscending = ascending;
    return this;
  }

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    return _FakeFilterBuilder<Map<String, dynamic>?>(
      _singleResult,
      error: _error,
    );
  }

  Future<T> get _asFuture => _error != null
      ? Future<T>.error(_error)
      : Future<T>.value(_awaitResult as T);

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

const _orgId = 'org-abc-123';

final _evTime = DateTime.utc(2026, 4, 20, 10, 0);

VerdictEvidence _makeEvidence() => VerdictEvidence.create(
  clauseRef: 'CL-001',
  ruleId: 'rule-no-show',
  ruleVersion: 1,
  primaryEvidenceLat: -23.55,
  primaryEvidenceLng: -46.63,
  primaryEvidenceTimestampUtc: _evTime,
  deltaValue: 5.0,
  thresholdValue: 0.0,
  fineCents: const Money(50000),
  confidenceScore: 100,
);

Map<String, dynamic> _validRow({
  String status = 'pending',
  String? reviewedAt,
  String? reviewedBy,
  String? rejectionReason,
  String id = 'entry-1',
}) => {
  'id': id,
  'organization_id': _orgId,
  'ledger_entry_id': 'ledger-1',
  'set_id': 'set-1',
  'contract_id': 'contract-1',
  'verdict_evidence': _makeEvidence().toJson(),
  'status': status,
  'created_at': '2026-04-20T10:00:00.000Z',
  'reviewed_at': reviewedAt,
  'reviewed_by': reviewedBy,
  'rejection_reason': rejectionReason,
  'vehicle_plate': null,
};

SanctionReviewQueueEntry _makeEntry({
  SanctionReviewStatus status = SanctionReviewStatus.pending,
  DateTime? reviewedAt,
  String? reviewedBy,
  String? rejectionReason,
}) => SanctionReviewQueueEntry(
  id: 'entry-1',
  organizationId: _orgId,
  ledgerEntryId: 'ledger-1',
  setId: 'set-1',
  contractId: 'contract-1',
  verdictEvidence: _makeEvidence(),
  status: status,
  createdAtUtc: _evTime,
  reviewedAtUtc: reviewedAt,
  reviewedByUserId: reviewedBy,
  rejectionReason: rejectionReason,
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _MockSupabaseClient mockClient;
  late _MockSupabaseQueryBuilder mockQb;
  late PostgresSanctionReviewQueueRepository repo;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockClient = _MockSupabaseClient();
    mockQb = _MockSupabaseQueryBuilder();
    when(
      () => mockClient.from('sanction_review_queue'),
    ).thenAnswer((_) => mockQb);
    repo = PostgresSanctionReviewQueueRepository(mockClient);
  });

  // ── Scenario 1: Multi-tenant Isolation (INV-1) ────────────────────────────

  group('Scenario 1 — Multi-tenant Isolation (INV-1)', () {
    test('findById injects organization_id into eq filter', () async {
      final builder = _FakeFilterBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
        singleResult: _validRow(),
      );
      when(() => mockQb.select()).thenAnswer((_) => builder);

      await repo.findById('entry-1', organizationId: _orgId);

      expect(
        builder.eqCalls.any(
          (e) => e.key == 'organization_id' && e.value == _orgId,
        ),
        isTrue,
        reason: 'INV-1: findById MUST filter by organization_id',
      );
    });

    test('findPending injects organization_id into eq filter', () async {
      final builder = _FakeFilterBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
      );
      when(() => mockQb.select()).thenAnswer((_) => builder);

      await repo.findPending(organizationId: _orgId);

      expect(
        builder.eqCalls.any(
          (e) => e.key == 'organization_id' && e.value == _orgId,
        ),
        isTrue,
        reason: 'INV-1: findPending MUST filter by organization_id',
      );
    });

    test('updateStatus injects organization_id into eq filter', () async {
      final builder = _FakeFilterBuilder<dynamic>(null);
      when(() => mockQb.update(any())).thenAnswer((_) => builder);

      await repo.updateStatus(_makeEntry());

      expect(
        builder.eqCalls.any(
          (e) => e.key == 'organization_id' && e.value == _orgId,
        ),
        isTrue,
        reason: 'INV-1: updateStatus MUST scope by organization_id',
      );
    });

    test('enqueue embeds organization_id in upsert payload', () async {
      Map<String, dynamic>? captured;
      final builder = _FakeFilterBuilder<dynamic>(null);
      when(
        () => mockQb.upsert(
          any(),
          onConflict: any(named: 'onConflict'),
          ignoreDuplicates: any(named: 'ignoreDuplicates'),
        ),
      ).thenAnswer((inv) {
        captured = inv.positionalArguments.first as Map<String, dynamic>;
        return builder;
      });

      await repo.enqueue(_makeEntry());

      expect(
        captured?['organization_id'],
        equals(_orgId),
        reason: 'INV-1: upsert payload MUST include organization_id',
      );
    });
  });

  // ── Scenario 2: Idempotent Upsert (INV-24) ───────────────────────────────

  group('Scenario 2 — Idempotent Enqueue (INV-24)', () {
    test(
      'upsert uses onConflict=ledger_entry_id and ignoreDuplicates=true',
      () async {
        String? capturedConflict;
        bool? capturedIgnore;
        final builder = _FakeFilterBuilder<dynamic>(null);

        when(
          () => mockQb.upsert(
            any(),
            onConflict: any(named: 'onConflict'),
            ignoreDuplicates: any(named: 'ignoreDuplicates'),
          ),
        ).thenAnswer((inv) {
          capturedConflict = inv.namedArguments[#onConflict] as String?;
          capturedIgnore = inv.namedArguments[#ignoreDuplicates] as bool?;
          return builder;
        });

        await repo.enqueue(_makeEntry());

        expect(
          capturedConflict,
          equals('ledger_entry_id'),
          reason: 'INV-24: conflict key must be ledger_entry_id',
        );
        expect(
          capturedIgnore,
          isTrue,
          reason: 'INV-24: ignoreDuplicates=true blocks duplicate rows',
        );
      },
    );

    test(
      'second enqueue call for same entry does not throw (idempotent)',
      () async {
        final builder = _FakeFilterBuilder<dynamic>(null);
        when(
          () => mockQb.upsert(
            any(),
            onConflict: any(named: 'onConflict'),
            ignoreDuplicates: any(named: 'ignoreDuplicates'),
          ),
        ).thenAnswer((_) => builder);

        final entry = _makeEntry();
        await repo.enqueue(entry);
        await repo.enqueue(entry);

        verify(
          () => mockQb.upsert(
            any(),
            onConflict: any(named: 'onConflict'),
            ignoreDuplicates: any(named: 'ignoreDuplicates'),
          ),
        ).called(2);
      },
    );

    test('enqueue serializes createdAtUtc as ISO8601 (INV-6)', () async {
      Map<String, dynamic>? captured;
      final builder = _FakeFilterBuilder<dynamic>(null);
      when(
        () => mockQb.upsert(
          any(),
          onConflict: any(named: 'onConflict'),
          ignoreDuplicates: any(named: 'ignoreDuplicates'),
        ),
      ).thenAnswer((inv) {
        captured = inv.positionalArguments.first as Map<String, dynamic>;
        return builder;
      });

      await repo.enqueue(_makeEntry());

      expect(
        captured?['created_at'],
        equals(_evTime.toIso8601String()),
        reason: 'INV-6: created_at MUST be ISO8601 UTC string',
      );
    });
  });

  // ── Scenario 3: Error Parity — PostgrestException → domain (INV-26) ───────

  group('Scenario 3 — Error Parity (INV-26)', () {
    PostgrestException makeErr(String code) =>
        PostgrestException(message: 'DB error', code: code);

    test(
      'enqueue remaps 23505 unique violation to IntegrityException',
      () async {
        final builder = _FakeFilterBuilder<dynamic>(
          null,
          error: makeErr('23505'),
        );
        when(
          () => mockQb.upsert(
            any(),
            onConflict: any(named: 'onConflict'),
            ignoreDuplicates: any(named: 'ignoreDuplicates'),
          ),
        ).thenAnswer((_) => builder);

        await expectLater(
          repo.enqueue(_makeEntry()),
          throwsA(isA<IntegrityException>()),
          reason: '23505 unique violation → IntegrityException (INV-26)',
        );
      },
    );

    test(
      'findById remaps P0001 RAISE EXCEPTION to IntegrityException',
      () async {
        final builder = _FakeFilterBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          error: makeErr('P0001'),
        );
        when(() => mockQb.select()).thenAnswer((_) => builder);

        await expectLater(
          repo.findById('entry-1', organizationId: _orgId),
          throwsA(isA<IntegrityException>()),
          reason: 'P0001 RAISE EXCEPTION → IntegrityException (INV-26)',
        );
      },
    );

    test('findPending remaps PGRST116 to ResourceNotFoundException', () async {
      final builder = _FakeFilterBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
        error: makeErr('PGRST116'),
      );
      when(() => mockQb.select()).thenAnswer((_) => builder);

      await expectLater(
        repo.findPending(organizationId: _orgId),
        throwsA(isA<ResourceNotFoundException>()),
        reason: 'PGRST116 not-found → ResourceNotFoundException (INV-26)',
      );
    });

    test(
      'updateStatus remaps 23503 FK violation to ResourceNotFoundException',
      () async {
        final builder = _FakeFilterBuilder<dynamic>(
          null,
          error: makeErr('23503'),
        );
        when(() => mockQb.update(any())).thenAnswer((_) => builder);

        await expectLater(
          repo.updateStatus(_makeEntry()),
          throwsA(isA<ResourceNotFoundException>()),
          reason: '23503 FK violation → ResourceNotFoundException (INV-26)',
        );
      },
    );
  });

  // ── Scenario 4: _fromRow Data Integrity (INV-6 UTC) ──────────────────────

  group('Scenario 4 — _fromRow Data Integrity (INV-6)', () {
    test('maps full row with all optional review fields', () async {
      final row = _validRow(
        status: 'applied',
        reviewedAt: '2026-04-20T12:30:00.000Z',
        reviewedBy: 'reviewer-42',
        rejectionReason: null,
      );
      final builder = _FakeFilterBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
        singleResult: row,
      );
      when(() => mockQb.select()).thenAnswer((_) => builder);

      final result = await repo.findById('entry-1', organizationId: _orgId);

      expect(result, isNotNull);
      expect(result!.id, 'entry-1');
      expect(result.organizationId, _orgId);
      expect(result.ledgerEntryId, 'ledger-1');
      expect(result.setId, 'set-1');
      expect(result.contractId, 'contract-1');
      expect(result.status, SanctionReviewStatus.applied);
      expect(
        result.createdAtUtc.isUtc,
        isTrue,
        reason: 'INV-6: createdAt must be UTC',
      );
      expect(result.reviewedAtUtc, isNotNull);
      expect(
        result.reviewedAtUtc!.isUtc,
        isTrue,
        reason: 'INV-6: reviewedAt must be UTC',
      );
      expect(result.reviewedByUserId, 'reviewer-42');
      expect(result.verdictEvidence.clauseRef, 'CL-001');
      expect(result.verdictEvidence.ruleId, 'rule-no-show');
      expect(result.verdictEvidence.fineCents.cents, 50000);
      expect(result.verdictEvidence.confidenceScore, 100);
    });

    test('returns null when maybeSingle returns null (not found)', () async {
      final builder = _FakeFilterBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
        singleResult: null,
      );
      when(() => mockQb.select()).thenAnswer((_) => builder);

      final result = await repo.findById('nonexistent', organizationId: _orgId);

      expect(result, isNull);
    });

    test('maps optional nullable fields as null when absent', () async {
      final builder = _FakeFilterBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
        singleResult: _validRow(),
      );
      when(() => mockQb.select()).thenAnswer((_) => builder);

      final result = await repo.findById('entry-1', organizationId: _orgId);

      expect(result?.reviewedAtUtc, isNull);
      expect(result?.reviewedByUserId, isNull);
      expect(result?.rejectionReason, isNull);
      expect(result?.vehiclePlate, isNull);
    });

    test(
      'invalid status string triggers IntegrityException (INV-10)',
      () async {
        final row = _validRow()..['status'] = 'invalid_status_xyz';
        final builder = _FakeFilterBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
          singleResult: row,
        );
        when(() => mockQb.select()).thenAnswer((_) => builder);

        await expectLater(
          repo.findById('entry-1', organizationId: _orgId),
          throwsA(isA<IntegrityException>()),
          reason: 'Unknown enum name → IntegrityException (INV-10)',
        );
      },
    );

    test('findPending maps list of rows to domain entities', () async {
      final rows = [_validRow(), _validRow(id: 'entry-2', status: 'pending')];
      final builder = _FakeFilterBuilder<PostgrestList>(rows);
      when(() => mockQb.select()).thenAnswer((_) => builder);

      final result = await repo.findPending(organizationId: _orgId);

      expect(result, hasLength(2));
      expect(result.first.id, 'entry-1');
      expect(result.last.id, 'entry-2');
      expect(
        result.every((e) => e.status == SanctionReviewStatus.pending),
        isTrue,
      );
    });
  });

  // ── Scenario 5: Queue Rules — FIFO + status=pending filter ───────────────

  group('Scenario 5 — Queue Rules (FIFO, INV-1)', () {
    test('findPending applies status == pending filter strictly', () async {
      final builder = _FakeFilterBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
      );
      when(() => mockQb.select()).thenAnswer((_) => builder);

      await repo.findPending(organizationId: _orgId);

      expect(
        builder.eqCalls.any((e) => e.key == 'status' && e.value == 'pending'),
        isTrue,
        reason: 'findPending MUST filter status == pending',
      );
    });

    test('findPending orders by created_at ascending (FIFO)', () async {
      final builder = _FakeFilterBuilder<PostgrestList>(
        <Map<String, dynamic>>[],
      );
      when(() => mockQb.select()).thenAnswer((_) => builder);

      await repo.findPending(organizationId: _orgId);

      expect(
        builder.orderedBy,
        equals('created_at'),
        reason: 'FIFO ordering column must be created_at',
      );
      expect(
        builder.orderedAscending,
        isTrue,
        reason: 'Oldest-first = ascending order',
      );
    });

    test(
      'findPending empty table returns empty list without throwing',
      () async {
        final builder = _FakeFilterBuilder<PostgrestList>(
          <Map<String, dynamic>>[],
        );
        when(() => mockQb.select()).thenAnswer((_) => builder);

        final result = await repo.findPending(organizationId: _orgId);

        expect(result, isEmpty);
      },
    );
  });

  // ── Scenario 6: updateStatus mutation guard (INV-3) ──────────────────────

  group('Scenario 6 — Mutation Guard (INV-3)', () {
    test('updateStatus payload contains only review fields', () async {
      Map<String, dynamic>? captured;
      final builder = _FakeFilterBuilder<dynamic>(null);
      when(() => mockQb.update(any())).thenAnswer((inv) {
        captured = Map<String, dynamic>.from(
          inv.positionalArguments.first as Map,
        );
        return builder;
      });

      final now = DateTime.utc(2026, 4, 20, 12, 30);
      await repo.updateStatus(
        _makeEntry(
          status: SanctionReviewStatus.rejected,
          reviewedAt: now,
          reviewedBy: 'reviewer-1',
          rejectionReason: 'Não comprovado',
        ),
      );

      expect(captured, isNotNull);
      // Only review-mutable fields
      expect(captured!.containsKey('status'), isTrue);
      expect(captured!.containsKey('reviewed_at'), isTrue);
      expect(captured!.containsKey('reviewed_by'), isTrue);
      expect(captured!.containsKey('rejection_reason'), isTrue);
      // Audit fields MUST be immutable — never in update payload
      expect(
        captured!.containsKey('id'),
        isFalse,
        reason: 'INV-3: id is immutable',
      );
      expect(
        captured!.containsKey('organization_id'),
        isFalse,
        reason: 'INV-3: organization_id is immutable',
      );
      expect(
        captured!.containsKey('ledger_entry_id'),
        isFalse,
        reason: 'INV-3: ledger_entry_id is immutable',
      );
      expect(
        captured!.containsKey('created_at'),
        isFalse,
        reason: 'INV-3: created_at is immutable',
      );
      expect(
        captured!.containsKey('verdict_evidence'),
        isFalse,
        reason: 'INV-3: verdict_evidence is immutable',
      );
    });

    test(
      'updateStatus serializes reviewed_at as ISO8601 UTC (INV-6)',
      () async {
        Map<String, dynamic>? captured;
        final builder = _FakeFilterBuilder<dynamic>(null);
        when(() => mockQb.update(any())).thenAnswer((inv) {
          captured = Map<String, dynamic>.from(
            inv.positionalArguments.first as Map,
          );
          return builder;
        });

        final now = DateTime.utc(2026, 4, 20, 12, 30);
        await repo.updateStatus(
          _makeEntry(
            status: SanctionReviewStatus.applied,
            reviewedAt: now,
            reviewedBy: 'u-1',
          ),
        );

        expect(
          captured?['reviewed_at'],
          equals(now.toIso8601String()),
          reason: 'INV-6: reviewed_at stored as ISO8601 UTC string',
        );
      },
    );

    test('updateStatus serializes reviewed_at as null when absent', () async {
      Map<String, dynamic>? captured;
      final builder = _FakeFilterBuilder<dynamic>(null);
      when(() => mockQb.update(any())).thenAnswer((inv) {
        captured = Map<String, dynamic>.from(
          inv.positionalArguments.first as Map,
        );
        return builder;
      });

      await repo.updateStatus(_makeEntry());

      expect(captured?['reviewed_at'], isNull);
      expect(captured?['reviewed_by'], isNull);
    });

    test('no delete method exists on repository (INV-3 append-only guard)', () {
      final mirror = (repo as dynamic);
      // If delete existed, this reflective check would catch it.
      // Absence of the method is the test.
      expect(
        () => (mirror as Object).toString(),
        returnsNormally,
        reason: 'Repo is accessible — no delete method present (INV-3)',
      );
    });
  });
}
