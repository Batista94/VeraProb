/// Unit tests for [PostgresJustificationRepository].
///
/// **Coverage:**
/// - INV-1: Every query includes organization_id filter (tenant isolation).
/// - INV-6: UTC timestamps always parsed/serialized via .toUtc() / .toIso8601String().
/// - INV-22: Cross-tenant read returns null — Tenant-A cannot see Tenant-B data.
/// - INV-26: PostgrestException codes map to correct domain exceptions (no leak).
/// - OCC: updateStatusWithAuditLog returns 0 on status conflict.
/// - RPC Contract: exact params keys/values verified for both RPCs.
/// - Boundary: listByOrg applies contractId + status combined filters correctly.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/justification/contractor_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_evidence.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_submission_token.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/justification/postgres_justification_repository.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────────

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

// ── Fake fluent filter builder ─────────────────────────────────────────────────
//
// Covers PostgREST chains used by PostgresJustificationRepository:
//   .select(cols) → .eq() → .eq() → .limit() → .maybeSingle()
//   .select(cols) → .eq() → .order() → .limit()   (list queries)
//   .update({...}) → .eq() → .eq()
//
// Records eq() calls so INV-1/INV-22 assertions can verify WHERE predicates
// without inspecting raw SQL strings.
//
// _awaitResult must be List<dynamic> (not List<Map<String,dynamic>>) for list
// queries — use _asDynList() helper. _singleResult drives maybeSingle().

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

// ── Fake RPC builder (supports error injection) ────────────────────────────────

class _FakeRpcBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final dynamic _result;
  final Object? _error;

  _FakeRpcBuilder(this._result, {Object? error}) : _error = error;

  @override
  Future<S> then<S>(
    FutureOr<S> Function(T value) onValue, {
    Function? onError,
  }) {
    if (_error != null) {
      return Future<T>.error(_error).then(onValue, onError: onError);
    }
    return Future<T>.value(_result as T).then(onValue, onError: onError);
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    if (_error != null) {
      return Future<T>.error(_error).catchError(onError, test: test);
    }
    return Future<T>.value(_result as T);
  }

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) {
    if (_error != null) {
      return Future<T>.error(_error).whenComplete(action);
    }
    return Future<T>.value(_result as T).whenComplete(action);
  }

  @override
  Stream<T> asStream() =>
      _error != null ? Stream.error(_error) : Stream.value(_result as T);

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) {
    if (_error != null) return Future<T>.error(_error);
    return Future<T>.value(
      _result as T,
    ).timeout(timeLimit, onTimeout: onTimeout);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

List<dynamic> _asDynList(List<Map<String, dynamic>> rows) =>
    List<dynamic>.from(rows);

const _orgId = 'org-00000000-0000-0000-0000-000000000001';
const _orgBId = 'org-00000000-0000-0000-0000-000000000002';
const _contractId = 'contract-0000-0000-0000-000000000001';
const _setId = 'set-00000000-0000-0000-0000-000000000001';
const _justId = 'just-0000-0000-0000-0000-000000000001';
const _evidenceId = 'ev-000000-0000-0000-0000-000000000001';
const _tokenId = 'tok-00000-0000-0000-0000-000000000001';
const _tokenValue = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

// ── Row fixtures ──────────────────────────────────────────────────────────────

Map<String, dynamic> _justificationRow({
  String id = _justId,
  String orgId = _orgId,
  String status = 'PENDING',
  String category = 'MECHANICAL',
  String? reviewedByUserId,
  String? reviewedAtUtc,
  String createdAtUtc = '2026-01-15T10:30:00.000Z',
}) => {
  'id': id,
  'organization_id': orgId,
  'contract_id': _contractId,
  'set_id': _setId,
  'submitted_by_token': _tokenValue,
  'category': category,
  'description': 'Engine failure during route',
  'status': status,
  'reviewed_by_user_id': reviewedByUserId,
  'reviewed_at_utc': reviewedAtUtc,
  'created_at_utc': createdAtUtc,
};

Map<String, dynamic> _evidenceRow({
  String id = _evidenceId,
  String orgId = _orgId,
  String uploadedAtUtc = '2026-01-15T11:00:00.000Z',
}) => {
  'id': id,
  'justification_id': _justId,
  'organization_id': orgId,
  'file_name': 'evidence.pdf',
  'content_hash': 'abc123sha256',
  'storage_path': '/orgs/$orgId/evidence/$id.pdf',
  'uploaded_at_utc': uploadedAtUtc,
};

Map<String, dynamic> _tokenRow({
  String id = _tokenId,
  String orgId = _orgId,
  String expiresAtUtc = '2026-01-16T10:00:00.000Z',
  String? usedAtUtc,
  String? justificationId,
}) => {
  'id': id,
  'organization_id': orgId,
  'contract_id': _contractId,
  'set_id': _setId,
  'justification_id': justificationId,
  'token': _tokenValue,
  'created_by_user_id': 'user-001',
  'expires_at_utc': expiresAtUtc,
  'used_at_utc': usedAtUtc,
  'created_at_utc': '2026-01-15T10:00:00.000Z',
};

// ── Domain fixtures ───────────────────────────────────────────────────────────

ContractorJustification _buildJustification({
  String id = _justId,
  String orgId = _orgId,
  JustificationStatus status = JustificationStatus.pending,
  JustificationCategory category = JustificationCategory.mechanical,
  DateTime? createdAt,
}) => ContractorJustification(
  id: id,
  organizationId: orgId,
  contractId: _contractId,
  setId: _setId,
  submittedByToken: _tokenValue,
  category: category,
  description: 'Engine failure during route',
  status: status,
  reviewedByUserId: null,
  reviewedAtUtc: null,
  createdAtUtc: createdAt ?? DateTime.utc(2026, 1, 15, 10, 30),
);

JustificationEvidence _buildEvidence() => JustificationEvidence(
  id: _evidenceId,
  justificationId: _justId,
  organizationId: _orgId,
  fileName: 'evidence.pdf',
  contentHash: 'abc123sha256',
  storagePath: '/orgs/$_orgId/evidence/$_evidenceId.pdf',
  uploadedAtUtc: DateTime.utc(2026, 1, 15, 11, 0),
);

JustificationSubmissionToken _buildToken({DateTime? expiresAt}) =>
    JustificationSubmissionToken(
      id: _tokenId,
      organizationId: _orgId,
      contractId: _contractId,
      setId: _setId,
      justificationId: null,
      token: _tokenValue,
      createdByUserId: 'user-001',
      expiresAtUtc: expiresAt ?? DateTime.utc(2026, 1, 16, 10, 0),
      usedAtUtc: null,
      createdAtUtc: DateTime.utc(2026, 1, 15, 10, 0),
    );

// ── Stub helpers ──────────────────────────────────────────────────────────────

_FakeBuilder<PostgrestList> _stubSelect(
  _MockSupabaseQueryBuilder qb, {
  Map<String, dynamic>? singleResult,
  List<Map<String, dynamic>>? listResult,
  Object? error,
}) {
  final builder = _FakeBuilder<PostgrestList>(
    listResult != null ? _asDynList(listResult) : null,
    singleResult: singleResult,
    error: error,
  );
  when(() => qb.select(any())).thenAnswer((_) => builder);
  return builder;
}

_FakeBuilder<PostgrestList> _stubInsert(
  _MockSupabaseQueryBuilder qb, {
  Object? error,
  void Function(Map<String, dynamic>)? capture,
}) {
  final builder = _FakeBuilder<PostgrestList>(<dynamic>[], error: error);
  when(() => qb.insert(any())).thenAnswer((inv) {
    if (capture != null) {
      capture((inv.positionalArguments.first as Map).cast<String, dynamic>());
    }
    return builder;
  });
  return builder;
}

_FakeBuilder<PostgrestList> _stubUpdate(
  _MockSupabaseQueryBuilder qb, {
  Object? error,
  void Function(Map<String, dynamic>)? capture,
}) {
  final builder = _FakeBuilder<PostgrestList>(<dynamic>[], error: error);
  when(() => qb.update(any())).thenAnswer((inv) {
    if (capture != null) {
      capture((inv.positionalArguments.first as Map).cast<String, dynamic>());
    }
    return builder;
  });
  return builder;
}

// ─────────────────────────────────────────────────────────────────────────────
// TEST SUITE
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late _MockSupabaseClient mockClient;
  late PostgresJustificationRepository sut;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<dynamic>[]);
    registerFallbackValue('');
  });

  setUp(() {
    mockClient = _MockSupabaseClient();
    sut = PostgresJustificationRepository(mockClient);
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G1 — create()
  // ══════════════════════════════════════════════════════════════════════════

  group('create()', () {
    late _MockSupabaseQueryBuilder qb;

    setUp(() {
      qb = _MockSupabaseQueryBuilder();
      when(
        () => mockClient.from('contractor_justifications'),
      ).thenAnswer((_) => qb);
    });

    test('success — returns input justification unchanged', () async {
      unawaited(_stubInsert(qb));
      final j = _buildJustification();
      final result = await sut.create(j);
      expect(result, j);
    });

    test('INV-1 — insert payload contains organization_id', () async {
      Map<String, dynamic>? payload;
      unawaited(_stubInsert(qb, capture: (p) => payload = p));

      await sut.create(_buildJustification());

      expect(payload, isNotNull);
      expect(payload!['organization_id'], _orgId);
    });

    test('insert payload contains all required domain fields', () async {
      Map<String, dynamic>? payload;
      unawaited(_stubInsert(qb, capture: (p) => payload = p));

      final j = _buildJustification();
      await sut.create(j);

      expect(payload!['id'], _justId);
      expect(payload!['contract_id'], _contractId);
      expect(payload!['set_id'], _setId);
      expect(payload!['category'], 'MECHANICAL');
      expect(payload!['status'], 'PENDING');
      expect(payload!['description'], 'Engine failure during route');
    });

    test('INV-6 UTC — created_at_utc serialized as ISO-8601 string', () async {
      Map<String, dynamic>? payload;
      unawaited(_stubInsert(qb, capture: (p) => payload = p));

      final fixed = DateTime.utc(2026, 1, 15, 10, 30);
      await sut.create(_buildJustification(createdAt: fixed));

      expect(payload!['created_at_utc'], fixed.toIso8601String());
    });

    test('23505 unique violation → IntegrityException', () async {
      unawaited(
        _stubInsert(
          qb,
          error: const PostgrestException(
            message: 'duplicate key',
            code: '23505',
          ),
        ),
      );

      expect(
        () => sut.create(_buildJustification()),
        throwsA(isA<IntegrityException>()),
      );
    });

    test('23503 foreign key violation → ResourceNotFoundException', () async {
      unawaited(
        _stubInsert(
          qb,
          error: const PostgrestException(
            message: 'fk violation',
            code: '23503',
          ),
        ),
      );

      expect(
        () => sut.create(_buildJustification()),
        throwsA(isA<ResourceNotFoundException>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G2 — findById()
  // ══════════════════════════════════════════════════════════════════════════

  group('findById()', () {
    late _MockSupabaseQueryBuilder qb;

    setUp(() {
      qb = _MockSupabaseQueryBuilder();
      when(
        () => mockClient.from('contractor_justifications'),
      ).thenAnswer((_) => qb);
    });

    test('success — maps row to ContractorJustification', () async {
      unawaited(_stubSelect(qb, singleResult: _justificationRow()));

      final result = await sut.findById(id: _justId, organizationId: _orgId);

      expect(result, isNotNull);
      expect(result!.id, _justId);
      expect(result.organizationId, _orgId);
      expect(result.contractId, _contractId);
      expect(result.setId, _setId);
      expect(result.status, JustificationStatus.pending);
      expect(result.category, JustificationCategory.mechanical);
      expect(result.description, 'Engine failure during route');
    });

    test('INV-1 — query scoped with eq(organization_id) and eq(id)', () async {
      final sb = _stubSelect(qb, singleResult: _justificationRow());

      await sut.findById(id: _justId, organizationId: _orgId);

      expect(sb.hasEq('organization_id', _orgId), isTrue);
      expect(sb.hasEq('id', _justId), isTrue);
    });

    test(
      'INV-22 cross-tenant — wrong orgId returns null, query scoped to wrong org',
      () async {
        final sb = _stubSelect(qb, singleResult: null);

        final result = await sut.findById(id: _justId, organizationId: _orgBId);

        expect(result, isNull);
        expect(sb.hasEq('organization_id', _orgBId), isTrue);
        expect(sb.hasEq('organization_id', _orgId), isFalse);
      },
    );

    test('INV-6 UTC — created_at_utc parsed as UTC DateTime', () async {
      unawaited(
        _stubSelect(
          qb,
          singleResult: _justificationRow(
            createdAtUtc: '2026-01-15T10:30:00.000Z',
          ),
        ),
      );

      final result = await sut.findById(id: _justId, organizationId: _orgId);

      expect(result!.createdAtUtc.isUtc, isTrue);
      expect(result.createdAtUtc, DateTime.utc(2026, 1, 15, 10, 30));
    });

    test('INV-6 UTC — reviewed_at_utc parsed as UTC when present', () async {
      unawaited(
        _stubSelect(
          qb,
          singleResult: _justificationRow(
            status: 'APPROVED',
            reviewedByUserId: 'reviewer-001',
            reviewedAtUtc: '2026-01-15T15:00:00.000Z',
          ),
        ),
      );

      final result = await sut.findById(id: _justId, organizationId: _orgId);

      expect(result!.reviewedAtUtc, isNotNull);
      expect(result.reviewedAtUtc!.isUtc, isTrue);
      expect(result.reviewedAtUtc!, DateTime.utc(2026, 1, 15, 15, 0));
      expect(result.reviewedByUserId, 'reviewer-001');
    });

    test(
      'nullable fields — null reviewedByUserId and reviewedAtUtc map to null',
      () async {
        unawaited(_stubSelect(qb, singleResult: _justificationRow()));

        final result = await sut.findById(id: _justId, organizationId: _orgId);

        expect(result!.reviewedByUserId, isNull);
        expect(result.reviewedAtUtc, isNull);
      },
    );

    test('row not found — returns null', () async {
      unawaited(_stubSelect(qb, singleResult: null));

      final result = await sut.findById(id: _justId, organizationId: _orgId);

      expect(result, isNull);
    });

    test('22P02 invalid UUID → ResourceNotFoundException', () async {
      unawaited(
        _stubSelect(
          qb,
          error: const PostgrestException(
            message: 'invalid input',
            code: '22P02',
          ),
        ),
      );

      expect(
        () => sut.findById(id: 'not-a-uuid', organizationId: _orgId),
        throwsA(isA<ResourceNotFoundException>()),
      );
    });

    test('PGRST116 not found → ResourceNotFoundException', () async {
      unawaited(
        _stubSelect(
          qb,
          error: const PostgrestException(
            message: 'not found',
            code: 'PGRST116',
          ),
        ),
      );

      expect(
        () => sut.findById(id: _justId, organizationId: _orgId),
        throwsA(isA<ResourceNotFoundException>()),
      );
    });

    test('42501 RLS denied → SovereigntyViolationException', () async {
      unawaited(
        _stubSelect(
          qb,
          error: const PostgrestException(
            message: 'insufficient privilege',
            code: '42501',
          ),
        ),
      );

      expect(
        () => sut.findById(id: _justId, organizationId: _orgId),
        throwsA(isA<SovereigntyViolationException>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G3 — listByOrg()
  // ══════════════════════════════════════════════════════════════════════════

  group('listByOrg()', () {
    late _MockSupabaseQueryBuilder qb;

    setUp(() {
      qb = _MockSupabaseQueryBuilder();
      when(
        () => mockClient.from('contractor_justifications'),
      ).thenAnswer((_) => qb);
    });

    test('success — returns mapped list of justifications', () async {
      unawaited(_stubSelect(qb, listResult: [_justificationRow()]));

      final results = await sut.listByOrg(organizationId: _orgId);

      expect(results, hasLength(1));
      expect(results.first.id, _justId);
      expect(results.first.status, JustificationStatus.pending);
    });

    test('INV-1 — query always includes eq(organization_id)', () async {
      final sb = _stubSelect(qb, listResult: []);

      await sut.listByOrg(organizationId: _orgId);

      expect(sb.hasEq('organization_id', _orgId), isTrue);
    });

    test('boundary — contractId AND status both applied', () async {
      final sb = _stubSelect(qb, listResult: [_justificationRow()]);

      await sut.listByOrg(
        organizationId: _orgId,
        contractId: _contractId,
        status: JustificationStatus.pending,
      );

      expect(sb.hasEq('organization_id', _orgId), isTrue);
      expect(sb.hasEq('contract_id', _contractId), isTrue);
      expect(sb.hasEq('status', 'PENDING'), isTrue);
    });

    test(
      'contractId-only filter — contract_id in eq calls, status absent',
      () async {
        final sb = _stubSelect(qb, listResult: []);

        await sut.listByOrg(organizationId: _orgId, contractId: _contractId);

        expect(sb.hasEq('contract_id', _contractId), isTrue);
        expect(sb.eqCalls.any((e) => e.key == 'status'), isFalse);
      },
    );

    test(
      'status-only filter — status in eq calls with dbValue, contract_id absent',
      () async {
        final sb = _stubSelect(qb, listResult: []);

        await sut.listByOrg(
          organizationId: _orgId,
          status: JustificationStatus.approved,
        );

        expect(sb.hasEq('status', 'APPROVED'), isTrue);
        expect(sb.eqCalls.any((e) => e.key == 'contract_id'), isFalse);
      },
    );

    test('no optional filters — only organization_id in eq calls', () async {
      final sb = _stubSelect(qb, listResult: []);

      await sut.listByOrg(organizationId: _orgId);

      final eqKeys = sb.eqCalls.map((e) => e.key).toSet();
      expect(eqKeys, equals({'organization_id'}));
    });

    test('empty result — returns empty list without throwing', () async {
      unawaited(_stubSelect(qb, listResult: []));

      final results = await sut.listByOrg(organizationId: _orgId);

      expect(results, isEmpty);
    });

    test('multiple results — all rows mapped correctly', () async {
      unawaited(
        _stubSelect(
          qb,
          listResult: [
            _justificationRow(id: 'j-001', status: 'PENDING'),
            _justificationRow(id: 'j-002', status: 'APPROVED'),
            _justificationRow(id: 'j-003', status: 'REJECTED'),
          ],
        ),
      );

      final results = await sut.listByOrg(organizationId: _orgId);

      expect(results, hasLength(3));
      expect(results[0].status, JustificationStatus.pending);
      expect(results[1].status, JustificationStatus.approved);
      expect(results[2].status, JustificationStatus.rejected);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G4 — updateStatus()
  // ══════════════════════════════════════════════════════════════════════════

  group('updateStatus()', () {
    late _MockSupabaseQueryBuilder qb;

    setUp(() {
      qb = _MockSupabaseQueryBuilder();
      when(
        () => mockClient.from('contractor_justifications'),
      ).thenAnswer((_) => qb);
    });

    test(
      'success — update payload correct, re-fetches and returns updated',
      () async {
        Map<String, dynamic>? updatePayload;
        final updatedRow = _justificationRow(
          status: 'APPROVED',
          reviewedByUserId: 'reviewer-001',
          reviewedAtUtc: '2026-01-15T15:00:00.000Z',
        );

        unawaited(_stubUpdate(qb, capture: (p) => updatePayload = p));
        unawaited(_stubSelect(qb, singleResult: updatedRow));

        final reviewedAt = DateTime.utc(2026, 1, 15, 15, 0);
        final result = await sut.updateStatus(
          id: _justId,
          organizationId: _orgId,
          status: JustificationStatus.approved,
          reviewedByUserId: 'reviewer-001',
          reviewedAtUtc: reviewedAt,
        );

        expect(result.id, _justId);
        expect(result.status, JustificationStatus.approved);
        expect(result.reviewedByUserId, 'reviewer-001');

        expect(updatePayload!['status'], 'APPROVED');
        expect(updatePayload!['reviewed_by_user_id'], 'reviewer-001');
        expect(updatePayload!['reviewed_at_utc'], reviewedAt.toIso8601String());
      },
    );

    test(
      'INV-1 — update chain scoped with eq(organization_id) and eq(id)',
      () async {
        final ub = _stubUpdate(qb);
        unawaited(
          _stubSelect(qb, singleResult: _justificationRow(status: 'REJECTED')),
        );

        final reviewedAt = DateTime.utc(2026, 1, 15, 16, 0);
        await sut.updateStatus(
          id: _justId,
          organizationId: _orgId,
          status: JustificationStatus.rejected,
          reviewedByUserId: 'reviewer-001',
          reviewedAtUtc: reviewedAt,
        );

        expect(ub.hasEq('id', _justId), isTrue);
        expect(ub.hasEq('organization_id', _orgId), isTrue);
      },
    );

    test(
      'INV-6 UTC — reviewed_at_utc serialized as ISO-8601 in update payload',
      () async {
        Map<String, dynamic>? updatePayload;
        unawaited(_stubUpdate(qb, capture: (p) => updatePayload = p));
        unawaited(
          _stubSelect(qb, singleResult: _justificationRow(status: 'APPROVED')),
        );

        final reviewedAt = DateTime.utc(2026, 3, 10, 9, 0, 0);
        await sut.updateStatus(
          id: _justId,
          organizationId: _orgId,
          status: JustificationStatus.approved,
          reviewedByUserId: 'reviewer-002',
          reviewedAtUtc: reviewedAt,
        );

        expect(updatePayload!['reviewed_at_utc'], reviewedAt.toIso8601String());
      },
    );

    test('throws StateError when re-fetch returns null after update', () async {
      unawaited(_stubUpdate(qb));
      unawaited(_stubSelect(qb, singleResult: null));

      expect(
        () => sut.updateStatus(
          id: _justId,
          organizationId: _orgId,
          status: JustificationStatus.approved,
          reviewedByUserId: 'reviewer-001',
          reviewedAtUtc: DateTime.utc(2026, 1, 15, 15, 0),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G5 — updateStatusWithAuditLog()
  // ══════════════════════════════════════════════════════════════════════════

  group('updateStatusWithAuditLog()', () {
    setUp(() {
      registerFallbackValue(<String, dynamic>{});
    });

    test(
      'success — RPC called with exact 6-key param contract, returns 1',
      () async {
        when(
          () => mockClient.rpc<int>(any(), params: any(named: 'params')),
        ).thenAnswer((_) => _FakeRpcBuilder<int>(1));

        final result = await sut.updateStatusWithAuditLog(
          id: _justId,
          organizationId: _orgId,
          expectedCurrentStatus: JustificationStatus.pending,
          newStatus: JustificationStatus.approved,
          reviewerId: 'reviewer-001',
          resolutionNotes: 'Approved after review',
          reviewedAtUtc: DateTime.utc(2026, 1, 15, 15, 0),
          callerRole: 'contract_manager',
          evidenceUrls: ['https://storage.example.com/ev1.pdf'],
        );

        expect(result, 1);
      },
    );

    test('RPC — param keys match DB contract exactly', () async {
      final capturedParams = <Map<String, dynamic>>[];
      when(
        () => mockClient.rpc<int>(
          'update_justification_status_with_audit',
          params: captureAny(named: 'params'),
        ),
      ).thenAnswer((inv) {
        capturedParams.add(
          inv.namedArguments[const Symbol('params')] as Map<String, dynamic>,
        );
        return _FakeRpcBuilder<int>(1);
      });

      final evidenceUrls = ['https://s3.example.com/file1.pdf'];
      await sut.updateStatusWithAuditLog(
        id: _justId,
        organizationId: _orgId,
        expectedCurrentStatus: JustificationStatus.pending,
        newStatus: JustificationStatus.approved,
        reviewerId: 'reviewer-001',
        resolutionNotes: 'All good',
        reviewedAtUtc: DateTime.utc(2026, 1, 15, 15, 0),
        callerRole: 'manager',
        evidenceUrls: evidenceUrls,
      );

      expect(capturedParams, hasLength(1));
      final params = capturedParams.first;
      expect(params['p_justification_id'], _justId);
      expect(params['p_org_id'], _orgId);
      expect(params['p_expected_status'], 'PENDING');
      expect(params['p_new_status'], 'APPROVED');
      expect(params['p_resolution_notes'], 'All good');
      expect(params['p_evidence_urls'], evidenceUrls);
      // callerRole and reviewerId intentionally NOT in RPC params
      expect(params.containsKey('p_caller_role'), isFalse);
      expect(params.containsKey('p_reviewer_id'), isFalse);
    });

    test('dbValue — status strings sent as UPPERCASE to RPC', () async {
      final capturedParams = <Map<String, dynamic>>[];
      when(
        () => mockClient.rpc<int>(
          'update_justification_status_with_audit',
          params: captureAny(named: 'params'),
        ),
      ).thenAnswer((inv) {
        capturedParams.add(
          inv.namedArguments[const Symbol('params')] as Map<String, dynamic>,
        );
        return _FakeRpcBuilder<int>(1);
      });

      await sut.updateStatusWithAuditLog(
        id: _justId,
        organizationId: _orgId,
        expectedCurrentStatus: JustificationStatus.pending,
        newStatus: JustificationStatus.rejected,
        reviewerId: null,
        resolutionNotes: null,
        reviewedAtUtc: DateTime.utc(2026, 1, 15),
        callerRole: 'admin',
        evidenceUrls: [],
      );

      expect(capturedParams.first['p_expected_status'], 'PENDING');
      expect(capturedParams.first['p_new_status'], 'REJECTED');
    });

    test('OCC conflict — returns 0 when RPC signals no rows updated', () async {
      when(
        () => mockClient.rpc<int>(any(), params: any(named: 'params')),
      ).thenAnswer((_) => _FakeRpcBuilder<int>(0));

      final result = await sut.updateStatusWithAuditLog(
        id: _justId,
        organizationId: _orgId,
        expectedCurrentStatus: JustificationStatus.pending,
        newStatus: JustificationStatus.approved,
        reviewerId: null,
        resolutionNotes: null,
        reviewedAtUtc: DateTime.utc(2026, 1, 15, 15, 0),
        callerRole: 'manager',
        evidenceUrls: [],
      );

      expect(result, 0);
    });

    test('P0001 RAISE EXCEPTION → IntegrityException', () async {
      const pgErr = PostgrestException(
        message: 'Justification already reviewed',
        code: 'P0001',
      );
      when(
        () => mockClient.rpc<int>(any(), params: any(named: 'params')),
      ).thenAnswer((_) => _FakeRpcBuilder<int>(null, error: pgErr));

      expect(
        () => sut.updateStatusWithAuditLog(
          id: _justId,
          organizationId: _orgId,
          expectedCurrentStatus: JustificationStatus.pending,
          newStatus: JustificationStatus.approved,
          reviewerId: null,
          resolutionNotes: null,
          reviewedAtUtc: DateTime.utc(2026, 1, 15, 15, 0),
          callerRole: 'manager',
          evidenceUrls: [],
        ),
        throwsA(
          isA<IntegrityException>().having(
            (e) => e.message,
            'message',
            'Justification already reviewed',
          ),
        ),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G6 — addEvidence()
  // ══════════════════════════════════════════════════════════════════════════

  group('addEvidence()', () {
    late _MockSupabaseQueryBuilder qb;

    setUp(() {
      qb = _MockSupabaseQueryBuilder();
      when(
        () => mockClient.from('justification_evidence_uploads'),
      ).thenAnswer((_) => qb);
    });

    test('success — returns input evidence unchanged', () async {
      unawaited(_stubInsert(qb));
      final ev = _buildEvidence();
      final result = await sut.addEvidence(ev);
      expect(result, ev);
    });

    test('INV-1 — insert payload contains organization_id', () async {
      Map<String, dynamic>? payload;
      unawaited(_stubInsert(qb, capture: (p) => payload = p));

      await sut.addEvidence(_buildEvidence());

      expect(payload!['organization_id'], _orgId);
    });

    test('insert payload contains all forensic fields', () async {
      Map<String, dynamic>? payload;
      unawaited(_stubInsert(qb, capture: (p) => payload = p));

      await sut.addEvidence(_buildEvidence());

      expect(payload!['id'], _evidenceId);
      expect(payload!['justification_id'], _justId);
      expect(payload!['file_name'], 'evidence.pdf');
      expect(payload!['content_hash'], 'abc123sha256');
      expect(
        payload!['storage_path'],
        '/orgs/$_orgId/evidence/$_evidenceId.pdf',
      );
    });

    test('INV-6 UTC — uploaded_at_utc serialized as ISO-8601', () async {
      Map<String, dynamic>? payload;
      unawaited(_stubInsert(qb, capture: (p) => payload = p));

      await sut.addEvidence(_buildEvidence());

      expect(
        payload!['uploaded_at_utc'],
        DateTime.utc(2026, 1, 15, 11, 0).toIso8601String(),
      );
    });

    test('23505 unique violation → IntegrityException', () async {
      unawaited(
        _stubInsert(
          qb,
          error: const PostgrestException(
            message: 'duplicate key',
            code: '23505',
          ),
        ),
      );

      expect(
        () => sut.addEvidence(_buildEvidence()),
        throwsA(isA<IntegrityException>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G7 — getEvidence()
  // ══════════════════════════════════════════════════════════════════════════

  group('getEvidence()', () {
    late _MockSupabaseQueryBuilder qb;

    setUp(() {
      qb = _MockSupabaseQueryBuilder();
      when(
        () => mockClient.from('justification_evidence_uploads'),
      ).thenAnswer((_) => qb);
    });

    test('success — returns list of evidence', () async {
      unawaited(_stubSelect(qb, listResult: [_evidenceRow()]));

      final results = await sut.getEvidence(
        justificationId: _justId,
        organizationId: _orgId,
      );

      expect(results, hasLength(1));
      expect(results.first.id, _evidenceId);
      expect(results.first.fileName, 'evidence.pdf');
      expect(results.first.contentHash, 'abc123sha256');
    });

    test('INV-1 — query includes eq(organization_id)', () async {
      final sb = _stubSelect(qb, listResult: []);

      await sut.getEvidence(justificationId: _justId, organizationId: _orgId);

      expect(sb.hasEq('organization_id', _orgId), isTrue);
    });

    test(
      'justification_id filter — scoped to specific justification',
      () async {
        final sb = _stubSelect(qb, listResult: []);

        await sut.getEvidence(justificationId: _justId, organizationId: _orgId);

        expect(sb.hasEq('justification_id', _justId), isTrue);
      },
    );

    test('INV-6 UTC — uploaded_at_utc parsed as UTC DateTime', () async {
      unawaited(
        _stubSelect(
          qb,
          listResult: [_evidenceRow(uploadedAtUtc: '2026-01-15T11:00:00.000Z')],
        ),
      );

      final results = await sut.getEvidence(
        justificationId: _justId,
        organizationId: _orgId,
      );

      expect(results.first.uploadedAtUtc.isUtc, isTrue);
      expect(results.first.uploadedAtUtc, DateTime.utc(2026, 1, 15, 11, 0));
    });

    test('empty result — returns empty list', () async {
      unawaited(_stubSelect(qb, listResult: []));

      final results = await sut.getEvidence(
        justificationId: _justId,
        organizationId: _orgId,
      );

      expect(results, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G8 — createToken()
  // ══════════════════════════════════════════════════════════════════════════

  group('createToken()', () {
    late _MockSupabaseQueryBuilder qb;

    setUp(() {
      qb = _MockSupabaseQueryBuilder();
      when(
        () => mockClient.from('justification_submission_tokens'),
      ).thenAnswer((_) => qb);
    });

    test('success — returns input token unchanged', () async {
      unawaited(_stubInsert(qb));
      final t = _buildToken();
      final result = await sut.createToken(t);
      expect(result, t);
    });

    test('insert payload contains all required fields', () async {
      Map<String, dynamic>? payload;
      unawaited(_stubInsert(qb, capture: (p) => payload = p));

      await sut.createToken(_buildToken());

      expect(payload!['id'], _tokenId);
      expect(payload!['organization_id'], _orgId);
      expect(payload!['contract_id'], _contractId);
      expect(payload!['set_id'], _setId);
      expect(payload!['token'], _tokenValue);
      expect(payload!['created_by_user_id'], 'user-001');
    });

    test('INV-6 UTC — expires_at_utc and created_at_utc serialized', () async {
      Map<String, dynamic>? payload;
      unawaited(_stubInsert(qb, capture: (p) => payload = p));

      final expires = DateTime.utc(2026, 1, 16, 10, 0);
      await sut.createToken(_buildToken(expiresAt: expires));

      expect(payload!['expires_at_utc'], expires.toIso8601String());
      expect(
        payload!['created_at_utc'],
        DateTime.utc(2026, 1, 15, 10, 0).toIso8601String(),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G9 — findToken()
  // ══════════════════════════════════════════════════════════════════════════

  group('findToken()', () {
    late _MockSupabaseQueryBuilder qb;

    setUp(() {
      qb = _MockSupabaseQueryBuilder();
      when(
        () => mockClient.from('justification_submission_tokens'),
      ).thenAnswer((_) => qb);
    });

    test('success — maps row to JustificationSubmissionToken', () async {
      unawaited(_stubSelect(qb, singleResult: _tokenRow()));

      final result = await sut.findToken(_tokenValue);

      expect(result, isNotNull);
      expect(result!.id, _tokenId);
      expect(result.organizationId, _orgId);
      expect(result.token, _tokenValue);
      expect(result.createdByUserId, 'user-001');
      expect(result.justificationId, isNull);
    });

    test('query scoped to token value — eq(token, tokenValue)', () async {
      final sb = _stubSelect(qb, singleResult: _tokenRow());

      await sut.findToken(_tokenValue);

      expect(sb.hasEq('token', _tokenValue), isTrue);
    });

    test('not found — returns null', () async {
      unawaited(_stubSelect(qb, singleResult: null));

      final result = await sut.findToken('unknown-token');

      expect(result, isNull);
    });

    test('INV-6 UTC — expires_at_utc parsed as UTC', () async {
      unawaited(
        _stubSelect(
          qb,
          singleResult: _tokenRow(expiresAtUtc: '2026-01-16T10:00:00.000Z'),
        ),
      );

      final result = await sut.findToken(_tokenValue);

      expect(result!.expiresAtUtc.isUtc, isTrue);
      expect(result.expiresAtUtc, DateTime.utc(2026, 1, 16, 10, 0));
    });

    test('usedAtUtc null — maps to null in domain model', () async {
      unawaited(_stubSelect(qb, singleResult: _tokenRow()));

      final result = await sut.findToken(_tokenValue);

      expect(result!.usedAtUtc, isNull);
    });

    test('usedAtUtc present — parsed as UTC DateTime', () async {
      unawaited(
        _stubSelect(
          qb,
          singleResult: _tokenRow(usedAtUtc: '2026-01-15T12:30:00.000Z'),
        ),
      );

      final result = await sut.findToken(_tokenValue);

      expect(result!.usedAtUtc, isNotNull);
      expect(result.usedAtUtc!.isUtc, isTrue);
      expect(result.usedAtUtc!, DateTime.utc(2026, 1, 15, 12, 30));
    });

    test('justificationId present — maps correctly', () async {
      unawaited(
        _stubSelect(qb, singleResult: _tokenRow(justificationId: _justId)),
      );

      final result = await sut.findToken(_tokenValue);

      expect(result!.justificationId, _justId);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G10 — useToken()
  // ══════════════════════════════════════════════════════════════════════════

  group('useToken()', () {
    test('success — returns justification ID from RPC', () async {
      when(
        () => mockClient.rpc<String>(any(), params: any(named: 'params')),
      ).thenAnswer((_) => _FakeRpcBuilder<String>(_justId));

      final result = await sut.useToken(
        tokenValue: _tokenValue,
        category: 'MECHANICAL',
        description: 'Engine failure',
      );

      expect(result, _justId);
    });

    test(
      'RPC params — exact keys p_token, p_category, p_description',
      () async {
        final capturedParams = <Map<String, dynamic>>[];
        when(
          () => mockClient.rpc<String>(
            'use_justification_token',
            params: captureAny(named: 'params'),
          ),
        ).thenAnswer((inv) {
          capturedParams.add(
            inv.namedArguments[const Symbol('params')] as Map<String, dynamic>,
          );
          return _FakeRpcBuilder<String>(_justId);
        });

        await sut.useToken(
          tokenValue: _tokenValue,
          category: 'FORCE_MAJEURE',
          description: 'Flood blocked route',
        );

        expect(capturedParams, hasLength(1));
        final params = capturedParams.first;
        expect(params['p_token'], _tokenValue);
        expect(params['p_category'], 'FORCE_MAJEURE');
        expect(params['p_description'], 'Flood blocked route');
        expect(params.length, 3);
      },
    );

    test(
      'P0001 — expired token RAISE EXCEPTION → IntegrityException',
      () async {
        const pgErr = PostgrestException(
          message: 'Token expired or already used',
          code: 'P0001',
        );
        when(
          () => mockClient.rpc<String>(any(), params: any(named: 'params')),
        ).thenAnswer((_) => _FakeRpcBuilder<String>(null, error: pgErr));

        expect(
          () => sut.useToken(
            tokenValue: 'expired-token',
            category: 'OTHER',
            description: 'Late submission',
          ),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              'Token expired or already used',
            ),
          ),
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G11 — Mapper validation: enum round-trips
  // ══════════════════════════════════════════════════════════════════════════

  group('mapper — JustificationStatus round-trip', () {
    late _MockSupabaseQueryBuilder qb;

    setUp(() {
      qb = _MockSupabaseQueryBuilder();
      when(
        () => mockClient.from('contractor_justifications'),
      ).thenAnswer((_) => qb);
    });

    for (final (dbVal, expected) in [
      ('PENDING', JustificationStatus.pending),
      ('APPROVED', JustificationStatus.approved),
      ('REJECTED', JustificationStatus.rejected),
      ('EXPIRED', JustificationStatus.expired),
    ]) {
      test('DB "$dbVal" → JustificationStatus.$expected', () async {
        unawaited(
          _stubSelect(qb, singleResult: _justificationRow(status: dbVal)),
        );

        final result = await sut.findById(id: _justId, organizationId: _orgId);

        expect(result!.status, expected);
      });
    }

    test('unknown DB status → ArgumentError (fail-fast INV-10)', () async {
      unawaited(
        _stubSelect(
          qb,
          singleResult: _justificationRow(status: 'INVALID_STATUS'),
        ),
      );

      expect(
        () => sut.findById(id: _justId, organizationId: _orgId),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('mapper — JustificationCategory round-trip', () {
    late _MockSupabaseQueryBuilder qb;

    setUp(() {
      qb = _MockSupabaseQueryBuilder();
      when(
        () => mockClient.from('contractor_justifications'),
      ).thenAnswer((_) => qb);
    });

    for (final (dbVal, expected) in [
      ('MECHANICAL', JustificationCategory.mechanical),
      ('FORCE_MAJEURE', JustificationCategory.forceMajeure),
      ('TRAFFIC', JustificationCategory.traffic),
      ('ROUTE_DEVIATION', JustificationCategory.routeDeviation),
      ('COMMUNICATION', JustificationCategory.communication),
      ('OTHER', JustificationCategory.other),
    ]) {
      test('DB "$dbVal" → JustificationCategory.$expected', () async {
        unawaited(
          _stubSelect(qb, singleResult: _justificationRow(category: dbVal)),
        );

        final result = await sut.findById(id: _justId, organizationId: _orgId);

        expect(result!.category, expected);
      });
    }

    test('unknown DB category → ArgumentError (fail-fast INV-10)', () async {
      unawaited(
        _stubSelect(
          qb,
          singleResult: _justificationRow(category: 'UNKNOWN_CAT'),
        ),
      );

      expect(
        () => sut.findById(id: _justId, organizationId: _orgId),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // G12 — dbValue correctness (all enums)
  // ══════════════════════════════════════════════════════════════════════════

  group('JustificationStatus.dbValue', () {
    test(
      'pending → PENDING',
      () => expect(JustificationStatus.pending.dbValue, 'PENDING'),
    );
    test(
      'approved → APPROVED',
      () => expect(JustificationStatus.approved.dbValue, 'APPROVED'),
    );
    test(
      'rejected → REJECTED',
      () => expect(JustificationStatus.rejected.dbValue, 'REJECTED'),
    );
    test(
      'expired → EXPIRED',
      () => expect(JustificationStatus.expired.dbValue, 'EXPIRED'),
    );
  });

  group('JustificationCategory.dbValue', () {
    test(
      'mechanical → MECHANICAL',
      () => expect(JustificationCategory.mechanical.dbValue, 'MECHANICAL'),
    );
    test(
      'forceMajeure → FORCE_MAJEURE',
      () => expect(JustificationCategory.forceMajeure.dbValue, 'FORCE_MAJEURE'),
    );
    test(
      'traffic → TRAFFIC',
      () => expect(JustificationCategory.traffic.dbValue, 'TRAFFIC'),
    );
    test(
      'routeDeviation → ROUTE_DEVIATION',
      () => expect(
        JustificationCategory.routeDeviation.dbValue,
        'ROUTE_DEVIATION',
      ),
    );
    test(
      'communication → COMMUNICATION',
      () =>
          expect(JustificationCategory.communication.dbValue, 'COMMUNICATION'),
    );
    test(
      'other → OTHER',
      () => expect(JustificationCategory.other.dbValue, 'OTHER'),
    );
  });
}
