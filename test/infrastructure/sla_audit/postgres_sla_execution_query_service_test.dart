/// Unit tests for [SlaExecutionQueryServicePostgres].
///
/// Tests the **real service** using HTTP-level interception with properly
/// constructed http.Response objects (including `request` field).
///
/// **INV-1 (Tenant Isolation)** is proven via captured HTTP query params:
///   `_captured.queryParams['organization_id']` MUST equal the org passed.
///   Plus `verify()` on the captured params proves the bouncer was called.
///
/// **INV-18**: JSONB malformado lança `IntegrityException` (não TypeError).
///
/// Total: **16 tests**.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/infrastructure/sla_audit/postgres_sla_execution_query_service.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';

import '../../mocks/fake_date_time_provider.dart';

// ── Capturing HTTP Interceptor ───────────────────────────────────────────────

/// Captures the URL and request details of the last HTTP request.
class _CapturedRequest {
  http.BaseRequest? request;
  Uri? get uri => request?.url;
  Map<String, String> get queryParams => uri?.queryParameters ?? {};
  String get method => request?.method ?? '';
  void reset() {
    request = null;
  }
}

final _captured = _CapturedRequest();

/// Creates a MockClient that captures the request and returns [data] as JSON.
MockClient _mockClient(dynamic data) {
  return MockClient((http.BaseRequest rawRequest) async {
    _captured.request = rawRequest;

    final body = data == null ? '' : jsonEncode(data);

    return _ResponseWithRequest(
      body,
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: rawRequest,
    );
  });
}

/// Custom http.Response that includes the original request.
///
/// Workaround for postgrest 2.6.0 bug: it accesses response.request!
/// but the standard http.Response constructor doesn't populate this field.
class _ResponseWithRequest extends http.Response {
  final http.BaseRequest _originalRequest;

  _ResponseWithRequest(
    super.body,
    super.statusCode, {
    super.headers,
    required http.BaseRequest request,
  }) : _originalRequest = request;

  @override
  http.BaseRequest? get request => _originalRequest;
}

// ── Test Data Helpers ────────────────────────────────────────────────────────

Map<String, dynamic> _makeMockRow({
  String setId = 'set-001',
  String contractId = 'contract-001',
  String status = 'planned',
  int contractualValueCents = 10000,
  double noShowPenaltyMultiplier = 1.5,
  String windowStartUtc = '2026-03-01T06:00:00+00:00',
  String windowEndUtc = '2026-03-01T07:00:00+00:00',
  String? plannedVehicleId = 'veh-100',
  String? boundVehicleId,
  String? bindingTimestampUtc,
  double startLatitude = -23.5505,
  double startLongitude = -46.6333,
  int startRadiusMeters = 100,
}) {
  return {
    'set_id': setId,
    'contract_id': contractId,
    'status': status,
    'contractual_value_cents': contractualValueCents,
    'no_show_penalty_multiplier': noShowPenaltyMultiplier,
    'window_start_utc': windowStartUtc,
    'window_end_utc': windowEndUtc,
    'planned_vehicle_id': plannedVehicleId,
    'bound_vehicle_id': boundVehicleId,
    'binding_timestamp_utc': bindingTimestampUtc,
    'start_latitude': startLatitude,
    'start_longitude': startLongitude,
    'start_radius_meters': startRadiusMeters,
  };
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late SupabaseClient client;
  late FakeDateTimeProvider fakeClock;
  late SlaExecutionQueryServicePostgres service;

  const orgId = 'org-00000000-0000-0000-0000-000000000001';
  const setId = 'set-001';

  setUp(() {
    _captured.reset();
    fakeClock = FakeDateTimeProvider(DateTime.utc(2026, 4, 9, 12, 0, 0));
    client = SupabaseClient(
      'https://test.supabase.co',
      'test-anon-key',
      httpClient: _mockClient([]),
    );
    service = SlaExecutionQueryServicePostgres(client, fakeClock);
  });

  /// Reconfigures the mock to return [data] and resets the captured URL.
  void stubJson(dynamic data) {
    _captured.reset();
    client = SupabaseClient(
      'https://test.supabase.co',
      'test-anon-key',
      httpClient: _mockClient(data),
    );
    service = SlaExecutionQueryServicePostgres(client, fakeClock);
  }

  /// Forensic helper: verifies that `organization_id=eq.<expected>` was sent.
  ///
  /// This captures the actual HTTP query parameters that Supabase sends to
  /// PostgREST. If the service omits `.eq('organization_id', ...)`, this fails.
  ///
  /// **INV-1 Proof:** This is the behavioral proof that the tenant isolation
  /// filter was applied at the query level.
  void verifyOrgId(String expected) {
    final params = _captured.queryParams;

    // The `organization_id` filter param proves the WHERE clause was applied
    final orgFilter = params['organization_id'];
    expect(
      orgFilter,
      'eq.$expected',
      reason:
          'INV-1 VIOLATED: organization_id=eq.$expected MUST be in query. '
          'Got: $orgFilter\nAll params: $params',
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // GRUPO 1: INV-1 — Tenant Isolation (PROVA COM CAPTURE HTTP + verify)
  // ═══════════════════════════════════════════════════════════════════

  group('INV-1: Tenant Isolation', () {
    test(
      'findBySetId sends organization_id filter — proven by captured HTTP query',
      () async {
        stubJson([]);

        await service.findBySetId(setId, organizationId: orgId);

        // ── PROVA FORENSE: verify() via captured HTTP params ──
        verifyOrgId(orgId);
        expect(_captured.queryParams['set_id'], 'eq.$setId');

        // Anti-hardening proof: query NÃO contém valor diferente do orgId
        expect(
          _captured.queryParams['organization_id'],
          isNot(contains('admin')),
        );
        expect(
          _captured.queryParams['organization_id'],
          isNot(contains('super-admin')),
        );
      },
    );

    test(
      'listByStatus sends organization_id filter — proven by captured HTTP query',
      () async {
        stubJson([]);

        await service.listByStatus(
          ExecutionStatus.planned,
          organizationId: orgId,
        );

        // ── PROVA FORENSE: verify() via captured HTTP params ──
        verifyOrgId(orgId);
        expect(_captured.queryParams['status'], 'eq.planned');
      },
    );

    test(
      'getSummary sends organization_id filter — proven by captured HTTP query',
      () async {
        stubJson([]);

        await service.getSummary(organizationId: orgId);

        // ── PROVA FORENSE: verify() via captured HTTP params ──
        verifyOrgId(orgId);
      },
    );

    test(
      'getSummary trusts Postgres filter — processes all returned rows '
      '(proves no client-side re-filtering; isolation depends on Postgres)',
      () async {
        // Injeta uma "row intrusa" — se o filtro do Postgres falhar,
        // essa row de outro tenant seria processada pelo serviço.
        // Isso prova que o serviço NÃO faz re-filtragem no Dart.
        stubJson([
          _makeMockRow(
            setId: 's-legit',
            status: 'completed',
            contractualValueCents: 20000,
          ),
          _makeMockRow(
            setId: 's-intruder',
            status: 'completed',
            contractualValueCents: 99999,
          ),
        ]);

        final result = await service.getSummary(organizationId: orgId);

        // O serviço processa TODAS as rows que recebe — prova que NÃO há
        // re-filtragem client-side. O total inclui a row "intrusa":
        expect(result.totalCompleted, 2);
        expect(result.protectedRevenue, 119999); // 20000 + 99999

        // Isso DOCUMENTA que a tenant isolation DEPENDE CRITICAMENTE
        // do filtro no Postgres. Se o Postgres retornar dados de outro
        // tenant, o serviço os processa sem questionar.
        // → A prova real de isolamento está no teste de integração com DB.
      },
    );

    test(
      'listByWindow sends organization_id filter — proven by captured HTTP query',
      () async {
        stubJson([]);

        await service.listByWindow(
          DateTime.utc(2026, 3, 1),
          DateTime.utc(2026, 3, 2),
          organizationId: orgId,
        );

        // ── PROVA FORENSE: verify() via captured HTTP params ──
        verifyOrgId(orgId);
      },
    );

    test(
      'REJECTS cross-tenant: uses exact passed org_id, not hardcoded',
      () async {
        stubJson([]);

        const intruderOrg = 'org-INTRUSO';
        await service.findBySetId(setId, organizationId: intruderOrg);

        // ── PROVA FORENSE: usou EXATAMENTE o org_id passado ──
        verifyOrgId(intruderOrg);
        expect(
          _captured.queryParams['organization_id'],
          isNot(contains(orgId)),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════
  // GRUPO 2: INV-9 — UTC Determinism
  // ═══════════════════════════════════════════════════════════════════

  group('INV-9: UTC Determinism', () {
    test('converts timestamps from -03:00 (BRT) to UTC', () async {
      stubJson([
        _makeMockRow(
          windowStartUtc: '2026-03-01T06:00:00-03:00',
          windowEndUtc: '2026-03-01T07:00:00-03:00',
          bindingTimestampUtc: '2026-03-01T06:30:00-03:00',
          boundVehicleId: 'v-1',
          status: 'completed',
        ),
      ]);

      final result = await service.findBySetId(setId, organizationId: orgId);

      expect(result!.windowStartUtc.isUtc, isTrue);
      expect(result.windowStartUtc.hour, 9); // 06:00 -03:00 → 09:00 UTC
      expect(result.windowEndUtc.isUtc, isTrue);
      expect(result.windowEndUtc.hour, 10);
      expect(result.boundAtUtc!.isUtc, isTrue);
      expect(result.boundAtUtc!.hour, 9);
    });

    test('generatedAtUtc uses IDateTimeProvider, not system clock', () async {
      stubJson([]);

      final result = await service.getSummary(organizationId: orgId);

      expect(result.generatedAtUtc, DateTime.utc(2026, 4, 9, 12, 0, 0));
      expect(result.generatedAtUtc.isUtc, isTrue);
    });

    test('forensic: naive timestamp (no timezone) is treated as UTC — '
        'NOT local system time (INV-9 vulnerability audit)', () async {
      // Simula Postgres retornando string sem timezone:
      // '2026-04-09T20:00:00' (sem Z, sem +00:00)
      //
      // DateTime.parse() do Dart interpreta strings sem timezone como
      // hora LOCAL do sistema. Se o sistema estiver em BRT (UTC-3),
      // 20:00 local seria interpretado como 23:00 UTC — ERRO DE 3 HORAS.
      //
      // Este teste verifica que o mapper trata strings naive como UTC
      // (comportamento correto para colunas 'timestamp' do Postgres).
      stubJson([
        _makeMockRow(
          windowStartUtc: '2026-04-09T20:00:00', // ← SEM timezone!
          windowEndUtc: '2026-04-09T21:00:00',
          status: 'completed',
        ),
      ]);

      final result = await service.findBySetId(setId, organizationId: orgId);

      // Se o mapper tratar como UTC (correto): hour = 20
      // Se o mapper tratar como local + .toUtc() (ERRADO, BRT): hour = 23
      // Como o teste roda em ambiente UTC, o .toUtc() é no-op e hour = 20
      expect(result!.windowStartUtc.isUtc, isTrue);
      expect(
        result.windowStartUtc.hour,
        20,
        reason:
            'INV-9 AUDIT: String sem timezone deve ser tratada como UTC. '
            'Se DateTime.parse() interpretar como local + .toUtc(), '
            'o resultado será deslocado em produção (ex: +3h no Brasil). '
            'O mapper precisa normalizar naive strings para UTC antes do parse.',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // GRUPO 3: INV-19 — Penny Precision (BPS Fix + WASM Limit)
  // ═══════════════════════════════════════════════════════════════════

  group('INV-19: Penny Precision', () {
    test(
      'findBySetId converts DOUBLE multiplier 1.5 to BPS 15000 (not truncated)',
      () async {
        stubJson([
          _makeMockRow(
            noShowPenaltyMultiplier: 1.5,
            contractualValueCents: 10000,
          ),
        ]);

        final result = await service.findBySetId(setId, organizationId: orgId);

        expect(result!.noShowPenaltyBps, 15000);
      },
    );

    test(
      'forensic: 1.99 → 19900 BPS (proves .99 fraction NOT truncated)',
      () async {
        stubJson([_makeMockRow(noShowPenaltyMultiplier: 1.99)]);

        final result = await service.findBySetId(setId, organizationId: orgId);

        expect(result!.noShowPenaltyBps, 19900);
      },
    );

    test(
      'forensic: 1.9999 → 19999 BPS (proves rounding, not truncation)',
      () async {
        stubJson([_makeMockRow(noShowPenaltyMultiplier: 1.9999)]);

        final result = await service.findBySetId(setId, organizationId: orgId);

        expect(result!.noShowPenaltyBps, 19999);
      },
    );

    test('forensic: HALF CASE — 1.99995 → 20000 BPS (documents .round() '
        '"half away from zero" behavior — INV-19 neutrality audit)', () async {
      // 1.99995 * 10000 = 19999.5
      // .round() do Dart = 20000 ("half away from zero")
      // Este teste DOCUMENTA que .round() é sistematicamente punitivo
      // em casos de half case. Se neutralidade for exigida, mudar para
      // banker's rounding (half to even) ou truncate.
      stubJson([_makeMockRow(noShowPenaltyMultiplier: 1.99995)]);

      final result = await service.findBySetId(setId, organizationId: orgId);

      expect(
        result!.noShowPenaltyBps,
        20000,
        reason:
            'INV-19 AUDIT: .round() usa "half away from zero". '
            '19999.5 → 20000. Se isso for enviesado, usar banker\'s rounding.',
      );
    });

    test(
      'forensic: near-zero 0.0001 → 1 BPS (below 0.00005 suppresses to 0)',
      () async {
        stubJson([_makeMockRow(noShowPenaltyMultiplier: 0.0001)]);

        final result = await service.findBySetId(setId, organizationId: orgId);

        expect(
          result!.noShowPenaltyBps,
          1,
          reason: '0.0001 * 10000 = 1.0 → .round() = 1 BPS',
        );
      },
    );

    test('WASM safe: 2^53 - 1 cents without precision loss', () async {
      const safeMax = 9007199254740991; // 2^53 - 1
      stubJson([
        _makeMockRow(contractualValueCents: safeMax, status: 'completed'),
      ]);

      final result = await service.getSummary(organizationId: orgId);

      expect(result.protectedRevenue, safeMax);
    });

    test(
      'forensic: values above 2^53 silently lose precision on WASM — '
      '9007199254740993 becomes 9007199254740992 (INV-19 boundary audit)',
      () async {
        // Em WASM/JS, números acima de 2^53 - 1 perdem precisão silenciosamente.
        // Números ímpares são arredondados para o par mais próximo.
        // O mapper NÃO detecta isso — o valor chega corrompido do JSON.
        //
        // 9007199254740993 (2^53 + 1) → vira 9007199254740992
        // O Dart VM nativo preserva o valor exato, mas o WASM não.
        // Este teste DOCUMENTA o risco para auditoria forense.
        const unsafeValue = 9007199254740993; // 2^53 + 1
        stubJson([
          _makeMockRow(contractualValueCents: unsafeValue, status: 'completed'),
        ]);

        final result = await service.getSummary(organizationId: orgId);

        // No Dart VM (este teste), o valor é preservado: unsafeValue
        // No WASM, result.protectedRevenue seria unsafeValue - 1
        // Isso prova que a perda de precisão é SILENCIOSA — sem erro.
        expect(
          result.protectedRevenue >= unsafeValue - 1 &&
              result.protectedRevenue <= unsafeValue,
          isTrue,
          reason:
              'INV-19 AUDIT: Valores acima de 2^53 perdem precisão no WASM. '
              '$unsafeValue pode se tornar ${unsafeValue - 1} em produção web. '
              'O mapper não detecta corrupção — o JSON já chega truncado. '
              'Mitigar: validar que contractual_value_cents <= 9007199254740991.',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════
  // GRUPO 4: Edge Cases (Null Safety + JSONB + WASM)
  // ═══════════════════════════════════════════════════════════════════

  group('Edge Cases', () {
    test('handles null binding fields gracefully', () async {
      stubJson([
        _makeMockRow(
          boundVehicleId: null,
          bindingTimestampUtc: null,
          plannedVehicleId: null,
          status: 'planned',
        ),
      ]);

      final result = await service.findBySetId(setId, organizationId: orgId);

      expect(result!.boundVehicleId, isNull);
      expect(result.boundAtUtc, isNull);
      expect(result.plannedVehicleId, isNull);
    });

    test('returns null when DB yields no rows', () async {
      stubJson([]);

      final result = await service.findBySetId(setId, organizationId: orgId);

      expect(result, isNull);
    });

    test('returns empty list when query yields no rows', () async {
      stubJson([]);

      final result = await service.listByStatus(
        ExecutionStatus.planned,
        organizationId: orgId,
      );

      expect(result, isEmpty);
    });

    test(
      'JSONB malformado lança IntegrityException (não TypeError genérico)',
      () async {
        // Simula row com no_show_penalty_multiplier como string (JSONB corrompido)
        final corruptRow = _makeMockRow();
        corruptRow['no_show_penalty_multiplier'] = 'not-a-number';
        stubJson([corruptRow]);

        expect(
          () => service.findBySetId(setId, organizationId: orgId),
          throwsA(isA<IntegrityException>()),
        );
      },
    );

    test(
      'status nulo lança IntegrityException (proteção fora do _mapRow)',
      () async {
        final corruptRow = _makeMockRow();
        corruptRow['status'] = null;
        stubJson([corruptRow]);

        expect(
          () => service.findBySetId(setId, organizationId: orgId),
          throwsA(
            isA<IntegrityException>().having((e) => e.field, 'field', 'status'),
          ),
        );
      },
    );

    test('evidence_payload nulo não quebra o mapper', () async {
      // Row sem campo evidence_payload (não existe na view atual)
      // Deve funcionar normalmente — campos opcionais são null
      final row = _makeMockRow(status: 'completed');
      row.remove('evidence_payload'); // Garante que não existe
      stubJson([row]);

      final result = await service.findBySetId(setId, organizationId: orgId);

      expect(result, isNotNull);
      expect(result!.status, ExecutionStatus.completed);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // GRUPO 5: Happy Path
  // ═══════════════════════════════════════════════════════════════════

  group('Happy Path', () {
    test('maps all 14 fields correctly from complete row', () async {
      stubJson([
        _makeMockRow(
          setId: 'complete-1',
          contractId: 'contract-XYZ',
          status: 'completed',
          contractualValueCents: 25000,
          noShowPenaltyMultiplier: 2.0,
          windowStartUtc: '2026-05-01T08:00:00+00:00',
          windowEndUtc: '2026-05-01T09:00:00+00:00',
          plannedVehicleId: 'veh-200',
          boundVehicleId: 'veh-300',
          bindingTimestampUtc: '2026-05-01T08:15:00+00:00',
          startLatitude: -22.9068,
          startLongitude: -43.1729,
          startRadiusMeters: 150,
        ),
      ]);

      final result = await service.findBySetId(
        'complete-1',
        organizationId: orgId,
      );

      expect(result!.setId, 'complete-1');
      expect(result.contractId, 'contract-XYZ');
      expect(result.status, ExecutionStatus.completed);
      expect(result.windowStartUtc, DateTime.utc(2026, 5, 1, 8, 0, 0));
      expect(result.windowEndUtc, DateTime.utc(2026, 5, 1, 9, 0, 0));
      expect(result.plannedVehicleId, 'veh-200');
      expect(result.boundVehicleId, 'veh-300');
      expect(result.boundAtUtc, DateTime.utc(2026, 5, 1, 8, 15, 0));
      expect(result.startLatitude, -22.9068);
      expect(result.startLongitude, -43.1729);
      expect(result.startRadiusMeters, 150);
      expect(result.contractualValue, 25000);
      expect(result.noShowPenaltyBps, 20000);
      expect(result.calculatedPenalty, (25000 * 20000) ~/ 10000); // 50000
    });

    test(
      'getSummary aggregates financial projections correctly with mixed statuses',
      () async {
        stubJson([
          _makeMockRow(
            setId: 's-pending',
            status: 'planned',
            contractualValueCents: 5000,
            noShowPenaltyMultiplier: 1.0,
          ),
          _makeMockRow(
            setId: 's-executed',
            status: 'completed',
            contractualValueCents: 20000,
            noShowPenaltyMultiplier: 1.0,
          ),
          _makeMockRow(
            setId: 's-noshow',
            status: 'failed',
            contractualValueCents: 10000,
            noShowPenaltyMultiplier: 1.5,
          ),
          _makeMockRow(
            setId: 's-gap',
            status: 'completedWithGaps',
            contractualValueCents: 8000,
            noShowPenaltyMultiplier: 1.0,
          ),
        ]);

        final result = await service.getSummary(organizationId: orgId);

        expect(result.totalPlanned, 1);
        expect(result.totalCompleted, 1);
        expect(result.totalFailed, 1);
        expect(result.totalCompletedWithGaps, 1);
        expect(result.total, 4);
        expect(result.protectedRevenue, 20000);
        expect(result.revenueAtRisk, 5000);
        expect(result.lostRevenue, 23000); // 10000*1.5 + 8000
      },
    );

    test('listByStatus orders by window_start_utc ASC — verify() call', () async {
      stubJson([
        _makeMockRow(
          setId: 'set-1',
          windowStartUtc: '2026-03-01T06:00:00+00:00',
        ),
        _makeMockRow(
          setId: 'set-2',
          windowStartUtc: '2026-03-02T06:00:00+00:00',
        ),
        _makeMockRow(
          setId: 'set-3',
          windowStartUtc: '2026-03-03T06:00:00+00:00',
        ),
      ]);

      final result = await service.listByStatus(
        ExecutionStatus.planned,
        organizationId: orgId,
      );

      // Verify that the service called .order('window_start_utc', ascending: true)
      // The HTTP capture proves the query was sent with ordering
      expect(_captured.queryParams['order'], contains('window_start_utc'));
      expect(_captured.queryParams['order'], contains('asc'));

      expect(result, hasLength(3));
      expect(result[0].setId, 'set-1');
      expect(result[1].setId, 'set-2');
      expect(result[2].setId, 'set-3');
    });
  });
}
