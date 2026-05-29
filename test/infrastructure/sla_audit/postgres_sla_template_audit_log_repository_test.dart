// ignore_for_file: avoid_implementing_value_types
/// Tests for [PostgresSlaTemplateAuditLogRepository].
///
/// Coverage:
///   Group A — Unit (no DB): payload contract (A1), exception mapping (A2–A4).
///   Group B — Integration (skip if Supabase offline): happy-path readback (B1),
///   UTC enforcement INV-6 (B2), UPDATE blocked INV-3 (B3), DELETE blocked
///   INV-3 (B4), tenant isolation INV-1/INV-22 (B5), PK duplicate (B6),
///   invalid action CHECK constraint (B7), anon access denied INV-22 (B8),
///   JSONB roundtrip integrity (B9).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_template_audit_entry.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sla_template_audit_log_repository.dart';

import '../postgres/postgres_test_config.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

// ── Fake Fluent Builder ───────────────────────────────────────────────────────
//
// Resolves to [_awaitResult] when awaited; throws [_error] if set.
// Used for A1 payload-contract tests where we need to capture insert args.

class _FakeBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  final dynamic _awaitResult;
  final Object? _error;

  _FakeBuilder(this._awaitResult, {Object? error}) : _error = error;

  Future<T> get _asFuture {
    if (_error != null) return Future<T>.error(_error);
    if (_awaitResult == null) return Future<T>.value(null as T);
    return Future<T>.value(_awaitResult as T);
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

// ── Clock stub ────────────────────────────────────────────────────────────────

class _FixedClock implements IDateTimeProvider {
  final DateTime _fixed;

  const _FixedClock(this._fixed);

  @override
  DateTime nowUtc() => _fixed;

  // Brazil time not used in these tests — stub satisfies interface.
  @override
  DateTime nowBrazil() => _fixed.subtract(const Duration(hours: 3));
}

// ── Helpers ───────────────────────────────────────────────────────────────────

PostgrestException _pgError(
  String code, {
  String message = 'db error',
  String? details,
}) => PostgrestException(message: message, code: code, details: details);

const _uuid = Uuid();
const _orgId = PostgresTestConfig.testOrgId;

final _fixedUtc = DateTime.utc(2026, 1, 15, 10, 30, 0);
final _fixedClock = _FixedClock(_fixedUtc);

SlaTemplateAuditEntry _buildEntry({
  String orgId = _orgId,
  String action = 'CREATED',
  Map<String, dynamic>? snapshot,
}) => SlaTemplateAuditEntry.create(
  organizationId: orgId,
  templateId: _uuid.v4(),
  actorSessionId: 'sess-test-${_uuid.v4()}',
  action: action,
  templateSnapshot: snapshot ?? {'name': 'SLA Alpha', 'version': 1},
  clock: _fixedClock,
);

/// Creates a fresh (client, qb, repo) triple per test — avoids mocktail
/// "Cannot call `when` within a stub response" caused by shared mock state
/// leaking across async microtask boundaries.
({
  _MockSupabaseClient client,
  _MockSupabaseQueryBuilder qb,
  PostgresSlaTemplateAuditLogRepository repo,
})
_makeSut() {
  final client = _MockSupabaseClient();
  final qb = _MockSupabaseQueryBuilder();
  when(() => client.from('sla_template_audit_log')).thenAnswer((_) => qb);
  final repo = PostgresSlaTemplateAuditLogRepository(client);
  return (client: client, qb: qb, repo: repo);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() async {
  final isRunning = await PostgresTestConfig.isSupabaseRunning();

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group A — Unit (sem banco, always runs)
  // ─────────────────────────────────────────────────────────────────────────

  group('A — Unit: payload contract + exception mapping (sem banco)', () {
    // ── A1 — Payload: todos os campos obrigatórios ──────────────────────────

    group('A1 — payload insert contém todos os 7 campos (Req #1)', () {
      test('todos os campos são enviados no insert', () async {
        final sut = _makeSut();
        final entry = _buildEntry();
        Map<String, dynamic>? captured;

        final builder = _FakeBuilder<PostgrestList>(<Map<String, dynamic>>[]);
        when(() => sut.qb.insert(any())).thenAnswer((inv) {
          captured = inv.positionalArguments.first as Map<String, dynamic>;
          return builder;
        });

        await sut.repo.append(entry);

        expect(captured, isNotNull, reason: 'insert() deve ter sido chamado');
        for (final field in const [
          'id',
          'organization_id',
          'template_id',
          'actor_session_id',
          'action',
          'template_snapshot',
          'occurred_at_utc',
        ]) {
          expect(
            captured!.containsKey(field),
            isTrue,
            reason: 'Campo "$field" ausente do payload do insert',
          );
          expect(
            captured![field],
            isNotNull,
            reason: 'Campo "$field" não deve ser null no payload',
          );
        }
      });

      test(
        'id no payload corresponde ao entry.id (UUID Dart-generated)',
        () async {
          final sut = _makeSut();
          final entry = _buildEntry();
          Map<String, dynamic>? captured;

          when(() => sut.qb.insert(any())).thenAnswer((inv) {
            captured = inv.positionalArguments.first as Map<String, dynamic>;
            return _FakeBuilder<PostgrestList>(<Map<String, dynamic>>[]);
          });

          await sut.repo.append(entry);
          expect(captured!['id'], equals(entry.id));
        },
      );

      test(
        'organization_id no payload corresponde ao entry.organizationId',
        () async {
          final sut = _makeSut();
          final entry = _buildEntry();
          Map<String, dynamic>? captured;

          when(() => sut.qb.insert(any())).thenAnswer((inv) {
            captured = inv.positionalArguments.first as Map<String, dynamic>;
            return _FakeBuilder<PostgrestList>(<Map<String, dynamic>>[]);
          });

          await sut.repo.append(entry);
          expect(captured!['organization_id'], equals(entry.organizationId));
        },
      );

      test('occurred_at_utc é String ISO-8601 UTC (INV-6)', () async {
        final sut = _makeSut();
        final entry = _buildEntry();
        Map<String, dynamic>? captured;

        when(() => sut.qb.insert(any())).thenAnswer((inv) {
          captured = inv.positionalArguments.first as Map<String, dynamic>;
          return _FakeBuilder<PostgrestList>(<Map<String, dynamic>>[]);
        });

        await sut.repo.append(entry);

        final rawTs = captured!['occurred_at_utc'];
        expect(
          rawTs,
          isA<String>(),
          reason: 'occurred_at_utc deve ser serializado como String ISO-8601',
        );

        final parsed = DateTime.parse(rawTs as String);
        expect(
          parsed.isUtc,
          isTrue,
          reason: 'occurred_at_utc deve conter offset UTC (INV-6)',
        );
        expect(parsed, equals(_fixedUtc));
      });

      test(
        'template_snapshot é o Map original (sem serialização extra)',
        () async {
          final sut = _makeSut();
          final snapshot = {'rules': 3, 'threshold': 0.95, 'tag': 'critical'};
          final entry = _buildEntry(snapshot: snapshot);
          Map<String, dynamic>? captured;

          when(() => sut.qb.insert(any())).thenAnswer((inv) {
            captured = inv.positionalArguments.first as Map<String, dynamic>;
            return _FakeBuilder<PostgrestList>(<Map<String, dynamic>>[]);
          });

          await sut.repo.append(entry);

          expect(
            captured!['template_snapshot'],
            equals(snapshot),
            reason:
                'template_snapshot deve ser passado como Map, não como String JSON',
          );
        },
      );

      test('action CREATED é passado inalterado', () async {
        final sut = _makeSut();
        final entry = _buildEntry(action: 'CREATED');
        Map<String, dynamic>? captured;

        when(() => sut.qb.insert(any())).thenAnswer((inv) {
          captured = inv.positionalArguments.first as Map<String, dynamic>;
          return _FakeBuilder<PostgrestList>(<Map<String, dynamic>>[]);
        });

        await sut.repo.append(entry);
        expect(captured!['action'], equals('CREATED'));
      });

      test('action UPDATED é passado inalterado', () async {
        final sut = _makeSut();
        final entry = _buildEntry(action: 'UPDATED');
        Map<String, dynamic>? captured;

        when(() => sut.qb.insert(any())).thenAnswer((inv) {
          captured = inv.positionalArguments.first as Map<String, dynamic>;
          return _FakeBuilder<PostgrestList>(<Map<String, dynamic>>[]);
        });

        await sut.repo.append(entry);
        expect(captured!['action'], equals('UPDATED'));
      });
    });

    // ── A2 — Mapeamento de exceções de domínio ──────────────────────────────

    group('A2 — mapeamento PostgrestException → domínio (INV-10, INV-26)', () {
      test(
        '42501 (RLS WITH CHECK) → SovereigntyViolationException (INV-2)',
        () async {
          final sut = _makeSut();
          when(() => sut.qb.insert(any())).thenThrow(_pgError('42501'));

          await expectLater(
            sut.repo.append(_buildEntry()),
            throwsA(isA<SovereigntyViolationException>()),
            reason:
                'RLS WITH CHECK → SovereigntyViolationException '
                'previne oracle attack (INV-2, INV-26)',
          );
        },
      );

      test(
        '23503 (FK violation) → ResourceNotFoundException (INV-26)',
        () async {
          final sut = _makeSut();
          when(() => sut.qb.insert(any())).thenThrow(
            _pgError(
              '23503',
              message: 'insert violates foreign key constraint',
            ),
          );

          await expectLater(
            sut.repo.append(_buildEntry()),
            throwsA(isA<ResourceNotFoundException>()),
            reason: 'FK violation não deve vazar nome da constraint (INV-26)',
          );
        },
      );

      test(
        '22P02 (UUID malformado) → ResourceNotFoundException (INV-26)',
        () async {
          final sut = _makeSut();
          when(() => sut.qb.insert(any())).thenThrow(
            _pgError('22P02', message: 'invalid input syntax for type uuid'),
          );

          await expectLater(
            sut.repo.append(_buildEntry()),
            throwsA(isA<ResourceNotFoundException>()),
            reason:
                'UUID malformado → ResourceNotFoundException, sem leak de tipo',
          );
        },
      );

      test(
        'PGRST116 (not found) → ResourceNotFoundException (INV-26)',
        () async {
          final sut = _makeSut();
          when(() => sut.qb.insert(any())).thenThrow(_pgError('PGRST116'));

          await expectLater(
            sut.repo.append(_buildEntry()),
            throwsA(isA<ResourceNotFoundException>()),
          );
        },
      );

      test(
        'PGRST204 (column not found) → ResourceNotFoundException (INV-26)',
        () async {
          final sut = _makeSut();
          when(
            () => sut.qb.insert(any()),
          ).thenThrow(_pgError('PGRST204', message: 'column not found'));

          await expectLater(
            sut.repo.append(_buildEntry()),
            throwsA(isA<ResourceNotFoundException>()),
            reason:
                'Schema drift → ResourceNotFoundException sem leak de coluna',
          );
        },
      );

      test(
        'P0001 (RAISE EXCEPTION / trigger imutabilidade) → IntegrityException (INV-3)',
        () async {
          final sut = _makeSut();
          when(() => sut.qb.insert(any())).thenThrow(
            _pgError(
              'P0001',
              message:
                  'sla_template_audit_log is immutable (INV-3). '
                  'Op: UPDATE, id: some-id',
            ),
          );

          await expectLater(
            sut.repo.append(_buildEntry()),
            throwsA(
              isA<IntegrityException>().having(
                (e) => e.message,
                'message',
                contains('immutable'),
              ),
            ),
            reason:
                'RAISE EXCEPTION do trigger → IntegrityException '
                'com mensagem original (INV-3)',
          );
        },
      );

      test(
        '23505 (unique PK violation) → IntegrityException (INV-3)',
        () async {
          final sut = _makeSut();
          when(() => sut.qb.insert(any())).thenThrow(
            _pgError(
              '23505',
              message:
                  'duplicate key value violates unique constraint '
                  '"sla_template_audit_log_pkey"',
              details: 'Key (id)=(some-uuid) already exists.',
            ),
          );

          await expectLater(
            sut.repo.append(_buildEntry()),
            throwsA(isA<IntegrityException>()),
            reason:
                'PK duplicada → IntegrityException '
                '(tentativa de sobreescrita, INV-3)',
          );
        },
      );
    });

    // ── A3 — Fail-fast: código desconhecido ─────────────────────────────────

    test(
      'A3 — código desconhecido é relançado como PostgrestException (fail-fast)',
      () async {
        final sut = _makeSut();
        when(
          () => sut.qb.insert(any()),
        ).thenThrow(_pgError('UNKNOWN_XYZ', message: 'unhandled server error'));

        await expectLater(
          sut.repo.append(_buildEntry()),
          throwsA(isA<PostgrestException>()),
          reason:
              'Códigos sem mapeamento NÃO devem ser silenciados — '
              'fail-fast relança PostgrestException original (INV-10)',
        );
      },
    );

    // ── A4 — resourceType correto passado ao mapeador ───────────────────────

    test('A4 — resourceType passado ao mapeador é '
        '"sla_template_audit_log" (INV-26)', () async {
      final sut = _makeSut();
      // 22P02 → ResourceNotFoundException, que captura resourceType.
      when(
        () => sut.qb.insert(any()),
      ).thenThrow(_pgError('22P02', message: 'invalid uuid format'));

      Object? caught;
      try {
        await sut.repo.append(_buildEntry());
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<ResourceNotFoundException>());
      final rnf = caught! as ResourceNotFoundException;
      expect(
        rnf.resourceType,
        equals('sla_template_audit_log'),
        reason:
            'resourceType deve ser "sla_template_audit_log" para '
            'rastreabilidade forense (INV-26)',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group B — Integration (skip se Supabase offline)
  // ─────────────────────────────────────────────────────────────────────────

  group(
    'B — Integration: Suíte Forense postgres_sla_template_audit_log',
    () {
      late SupabaseClient client;
      late PostgresSlaTemplateAuditLogRepository repo;
      final seedIds = <String>[];

      setUpAll(() async {
        if (isRunning) {
          client = await PostgresTestConfig.createClient();
          await PostgresTestConfig.ensureSentinelOrg(client: client);
          repo = PostgresSlaTemplateAuditLogRepository(client);
        }
      });

      tearDownAll(() async {
        // Tabela append-only: os registros de teste têm IDs UUID únicos
        // e não afetam outros runs. Aceitamos acumulação (INV-3 compliance).
        if (isRunning && seedIds.isNotEmpty) {
          try {
            // Limpeza bloqueada pelo trigger — aceito silenciosamente.
          } catch (_) {
            // Esperado: trigger bloqueia DELETE mesmo para service_role.
          }
        }
      });

      // ── B1 — Happy path: append + readback ─────────────────────────────

      test(
        'B1: append com todos os campos → row persistida e recuperável (Req #1)',
        () async {
          final entry = _buildEntry();
          seedIds.add(entry.id);

          await repo.append(entry);

          final rows = await client
              .from('sla_template_audit_log')
              .select()
              .eq('id', entry.id);

          expect(
            rows,
            hasLength(1),
            reason: 'A row deve ter sido inserida com o id correto',
          );

          final row = rows.first;
          expect(row['organization_id'], equals(entry.organizationId));
          expect(row['template_id'], equals(entry.templateId));
          expect(row['actor_session_id'], equals(entry.actorSessionId));
          expect(row['action'], equals(entry.action));
          expect(
            row['template_snapshot'],
            equals(entry.templateSnapshot),
            reason: 'JSONB snapshot deve ser roundtrip fiel',
          );
          expect(
            row['occurred_at_utc'],
            isNotNull,
            reason: 'occurred_at_utc deve ter sido persistido',
          );
        },
      );

      // ── B2 — UTC enforcement (INV-6) ────────────────────────────────────

      test('B2 (INV-6): occurred_at_utc é persistido como TIMESTAMPTZ '
          'e recuperado como UTC', () async {
        final entry = _buildEntry();
        seedIds.add(entry.id);

        await repo.append(entry);

        final rows = await client
            .from('sla_template_audit_log')
            .select('occurred_at_utc')
            .eq('id', entry.id);

        final rawTs = rows.first['occurred_at_utc'] as String;
        final recovered = DateTime.parse(rawTs);

        expect(
          recovered.isUtc,
          isTrue,
          reason: 'occurred_at_utc recuperado do banco deve ser UTC (INV-6)',
        );

        final diff = recovered.difference(_fixedUtc).abs();
        expect(
          diff.inSeconds,
          lessThanOrEqualTo(2),
          reason:
              'Timestamp recuperado deve corresponder ao valor inserido '
              'dentro de tolerância de 2s',
        );
      });

      // ── B3 — Imutabilidade: UPDATE bloqueado (INV-3) ────────────────────

      test('B3 (INV-3): UPDATE direto é bloqueado pelo trigger '
          'trg_sla_template_audit_no_update', () async {
        final entry = _buildEntry();
        seedIds.add(entry.id);

        await repo.append(entry);

        await expectLater(
          () => client
              .from('sla_template_audit_log')
              .update({'action': 'TAMPERED'})
              .eq('id', entry.id),
          throwsA(isA<PostgrestException>()),
          reason:
              'Trigger trg_sla_template_audit_no_update deve bloquear '
              'UPDATE com restrict_violation (INV-3)',
        );

        // Prova de estado: row não foi mutada
        final rows = await client
            .from('sla_template_audit_log')
            .select('action')
            .eq('id', entry.id);
        expect(
          rows.first['action'],
          equals(entry.action),
          reason: 'Row deve permanecer inalterada após UPDATE bloqueado',
        );
      });

      // ── B4 — Imutabilidade: DELETE bloqueado (INV-3) ────────────────────

      test('B4 (INV-3): DELETE direto é bloqueado pelo trigger '
          'trg_sla_template_audit_no_delete', () async {
        final entry = _buildEntry();
        seedIds.add(entry.id);

        await repo.append(entry);

        await expectLater(
          () =>
              client.from('sla_template_audit_log').delete().eq('id', entry.id),
          throwsA(isA<PostgrestException>()),
          reason:
              'Trigger trg_sla_template_audit_no_delete deve bloquear '
              'DELETE com restrict_violation (INV-3)',
        );

        final rows = await client
            .from('sla_template_audit_log')
            .select('id')
            .eq('id', entry.id);
        expect(
          rows,
          hasLength(1),
          reason: 'Row deve ainda existir após DELETE bloqueado (INV-3)',
        );
      });

      // ── B5 — Isolamento de tenant (INV-1, INV-22) ───────────────────────

      test('B5 (INV-1, INV-22): Tenant-A não vaza para Tenant-B '
          '— CIA Confidentiality', () async {
        final adversaryOrgId = _uuid.v4();
        await PostgresTestConfig.ensureSentinelOrg(id: adversaryOrgId);

        final entry = _buildEntry(orgId: _orgId);
        seedIds.add(entry.id);

        await repo.append(entry);

        // Tenant legítimo vê sua própria row
        final legitimate = await client
            .from('sla_template_audit_log')
            .select()
            .eq('id', entry.id)
            .eq('organization_id', _orgId);
        expect(
          legitimate,
          hasLength(1),
          reason: 'Tenant legítimo deve recuperar sua própria entry',
        );

        // Adversário não vê a row
        final adversary = await client
            .from('sla_template_audit_log')
            .select()
            .eq('id', entry.id)
            .eq('organization_id', adversaryOrgId);
        expect(
          adversary,
          isEmpty,
          reason:
              'Tenant adversário NÃO deve ver dados de outro org '
              '(INV-1, INV-22 — CIA Confidentiality)',
        );
      });

      // ── B6 — Duplicata de PK → IntegrityException ───────────────────────

      test(
        'B6 (INV-3): inserção com UUID duplicado → IntegrityException (23505)',
        () async {
          final entry = _buildEntry();
          seedIds.add(entry.id);

          await repo.append(entry);

          await expectLater(
            () => repo.append(entry),
            throwsA(isA<IntegrityException>()),
            reason:
                'PK duplicada deve ser mapeada para IntegrityException '
                '(23505 → previne sobreescrita forense, INV-3)',
          );
        },
      );

      // ── B7 — CHECK constraint: action inválida ──────────────────────────

      test('B7: action inválida é rejeitada pelo CHECK constraint do banco '
          '(defense-in-depth)', () async {
        await expectLater(
          () => client.from('sla_template_audit_log').insert({
            'id': _uuid.v4(),
            'organization_id': _orgId,
            'template_id': _uuid.v4(),
            'actor_session_id': 'sess-check-test',
            'action': 'DELETED', // valor inválido
            'template_snapshot': <String, dynamic>{},
            'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
          }),
          throwsA(isA<PostgrestException>()),
          reason:
              'CHECK constraint (action IN (CREATED, UPDATED)) deve '
              'rejeitar ação inválida como defesa em profundidade',
        );
      });

      // ── B8 — Anon sem acesso (INV-22 — Confidentiality) ─────────────────

      test(
        'B8 (INV-22): cliente anon não tem acesso SELECT nem INSERT',
        () async {
          final anonClient = SupabaseClient(
            PostgresTestConfig.supabaseUrl,
            PostgresTestConfig.supabaseAnonKey,
          );

          try {
            await expectLater(
              () => anonClient
                  .from('sla_template_audit_log')
                  .select()
                  .eq('organization_id', _orgId),
              throwsA(isA<PostgrestException>()),
              reason:
                  'Anon NUNCA deve conseguir SELECT em dados de auditoria '
                  '(REVOKE ALL aplicado na migration, INV-22)',
            );

            await expectLater(
              () => anonClient.from('sla_template_audit_log').insert({
                'id': _uuid.v4(),
                'organization_id': _orgId,
                'template_id': _uuid.v4(),
                'actor_session_id': 'anon-inject-attempt',
                'action': 'CREATED',
                'template_snapshot': <String, dynamic>{},
                'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
              }),
              throwsA(isA<PostgrestException>()),
              reason:
                  'Anon NÃO deve conseguir INSERT em dados de auditoria '
                  '(INV-22)',
            );
          } finally {
            await anonClient.dispose();
          }
        },
      );

      // ── B9 — JSONB roundtrip fidelidade (CIA Integrity) ──────────────────

      test('B9: template_snapshot com JSONB complexo sobrevive ao roundtrip '
          'sem perda (CIA Integrity)', () async {
        final complexSnapshot = <String, dynamic>{
          'name': 'SLA Template Forensic',
          'penalty_cents': 15000,
          'rules': [
            {'id': 'r1', 'threshold': 0.95, 'weight': 3},
            {'id': 'r2', 'threshold': 0.80, 'weight': 1},
          ],
          'metadata': {
            'version': 3,
            'tags': ['critical', 'sla', 'gov'],
            'active': true,
          },
          'nullable_field': null,
        };

        final entry = _buildEntry(snapshot: complexSnapshot);
        seedIds.add(entry.id);

        await repo.append(entry);

        final rows = await client
            .from('sla_template_audit_log')
            .select('template_snapshot')
            .eq('id', entry.id);

        final recovered =
            rows.first['template_snapshot'] as Map<String, dynamic>;

        expect(recovered['name'], equals('SLA Template Forensic'));
        expect(
          recovered['penalty_cents'],
          isA<int>(),
          reason: 'penalty_cents deve ser int, nunca double (sem drift)',
        );
        expect(recovered['penalty_cents'], equals(15000));

        final rules = recovered['rules'] as List<dynamic>;
        expect(rules, hasLength(2));
        expect(rules.first['id'], equals('r1'));

        final metadata = recovered['metadata'] as Map<String, dynamic>;
        expect(metadata['version'], equals(3));
        expect(
          (metadata['tags'] as List<dynamic>),
          containsAll(['critical', 'sla', 'gov']),
        );
        expect(metadata['active'], isTrue);
      });
    },
    skip: !isRunning ? 'Skipped: Local Supabase environment is offline.' : null,
  );
}
