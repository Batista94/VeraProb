/// E2E Integration — [GenerateForensicDossierHandler]
///
/// Full pipeline without UI pump:
///   Command → TenantValidationService → IStaticMapService
///   → PdfDossierGenerator → PostgresPdfDossierLogRepository
///
/// LOG-E1 requires Supabase local + migration 20260710000001_pdf_dossier_logs.
/// LOG-E2 / LOG-E3 / LOG-E4 are always-run (no DB I/O path reached).
///
/// Run: make test
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import 'package:uuid/uuid.dart';

import 'package:veraprob/application/reporting/generate_forensic_dossier_handler.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/reporting/i_static_map_service.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/infrastructure/reporting/pdf_dossier_generator.dart';
import 'package:veraprob/infrastructure/reporting/postgres_pdf_dossier_log_repository.dart';

import '../../infrastructure/postgres/postgres_test_config.dart';

// ── Test Doubles ─────────────────────────────────────────────────────────────

class _MockAuthRepository extends Mock implements IAuthRepository {}

/// Returns empty bytes — no real HTTP call (INV-25: no external deps in tests).
/// [PdfDossierGenerator._renderImageOrFallback] handles empty bytes gracefully.
class _FakeStaticMapService implements IStaticMapService {
  @override
  Future<List<int>> getStaticMap({
    required num lat,
    required num lng,
    required int zoom,
  }) async => const <int>[];
}

// ── Constants ─────────────────────────────────────────────────────────────────

const _uuid = Uuid();
const _orgA = '00000000-0000-0000-0000-000000000001';
const _orgB = 'bbbbbbbb-0000-0000-0000-000000000004';
const _contractId = 'c0000000-0000-0000-0000-000000000001';
const _operatorId = '00000000-0000-0000-0000-000000000002';
const _sessionId = 'session-e2e-test';

// ── Shared state ──────────────────────────────────────────────────────────────

bool _supabaseRunning = false;
bool _migrationApplied = false;
late SupabaseClient _serviceClient;

// ── Builder helpers ───────────────────────────────────────────────────────────

_MockAuthRepository _mockAuthFor(String orgId) {
  final repo = _MockAuthRepository();
  when(
    () => repo.getUserBySessionId(any()),
  ).thenAnswer((_) async => const AuthUser(id: _operatorId, tenantId: _orgA));
  // Override if caller needs a different org on the JWT.
  // We re-stub below at call site when needed.
  return repo;
}

GenerateForensicDossierHandler _handler({
  required _MockAuthRepository authRepo,
  required SupabaseClient client,
}) => GenerateForensicDossierHandler(
  _FakeStaticMapService(),
  PdfDossierGenerator(),
  PostgresPdfDossierLogRepository(client),
  TenantValidationService(authRepository: authRepo),
);

SlaLedgerEntry _entry({
  required String eventId,
  required String organizationId,
}) => SlaLedgerEntry(
  eventId: eventId,
  organizationId: organizationId,
  type: 'SANCTION_VERDICT',
  contractId: _contractId,
  planVersion: 1,
  occurredAtUtc: DateTime.utc(2026, 1, 15, 10, 30),
);

GenerateForensicDossierCommand _command({
  required String orgId,
  required SlaLedgerEntry ledgerEntry,
  String? jwtOrgId,
}) => GenerateForensicDossierCommand(
  sessionId: _sessionId,
  operatorId: _operatorId,
  jwtOrganizationId: jwtOrgId ?? orgId,
  requestedOrganizationId: orgId,
  ledgerEntry: ledgerEntry,
  savingsCents: 150000,
  mapLat: -23.5505,
  mapLng: -46.6333,
);

/// Creates a fresh SupabaseClient that won't make network calls for
/// sovereignty / integrity tests (exception fires before any I/O).
SupabaseClient _offlineClient() => SupabaseClient(
  PostgresTestConfig.supabaseUrl,
  PostgresTestConfig.serviceRoleKey.isEmpty
      ? 'offline-placeholder'
      : PostgresTestConfig.serviceRoleKey,
);

// ── Suite ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    _supabaseRunning = await PostgresTestConfig.isSupabaseRunning();
    if (!_supabaseRunning) return;

    _serviceClient = await PostgresTestConfig.createClient();
    await PostgresTestConfig.ensureSentinelOrg(id: _orgA);
    await PostgresTestConfig.ensureSentinelOrg(
      id: _orgB,
      name: 'Org-B E2E Dossier Test',
    );

    // Detect whether the pdf_dossier_logs migration is applied.
    // PGRST205 = table absent from schema cache.
    try {
      await _serviceClient.from('pdf_dossier_logs').select('id').limit(0);
      _migrationApplied = true;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') return;
      rethrow;
    }
  });

  tearDownAll(() async {
    if (_supabaseRunning) await _serviceClient.dispose();
  });

  // ── LOG-E1 ───────────────────────────────────────────────────────────────────
  //
  // Happy path: handler returns PDF bytes that contain the dossier hash
  // AND the chain-of-custody record is persisted in pdf_dossier_logs (INV-9).

  test('LOG-E1 [INV-9]: handler returns PDF bytes containing dossier hash '
      'and persists chain-of-custody log in pdf_dossier_logs', () async {
    if (!_supabaseRunning || !_migrationApplied) {
      markTestSkipped(
        _supabaseRunning
            ? 'Migration pdf_dossier_logs not applied (run: supabase db push)'
            : 'Supabase não está rodando',
      );
      return;
    }

    // Unique entry per run — avoids UNIQUE(org, entry, hash) collision.
    final entryId = _uuid.v4();
    final authRepo = _mockAuthFor(_orgA);
    final handler = _handler(authRepo: authRepo, client: _serviceClient);
    final cmd = _command(
      orgId: _orgA,
      ledgerEntry: _entry(eventId: entryId, organizationId: _orgA),
    );

    final bytes = await handler.handle(cmd);

    // 1. PDF bytes non-empty.
    expect(bytes, isNotEmpty);

    // 2. Raw bytes contain UTC label (compress:false → raw-inspectable INV-9).
    final pdfText = utf8.decode(bytes, allowMalformed: true);
    expect(pdfText, contains('UTC'));

    // 3. Chain-of-custody record persisted with matching hash.
    final rows = await _serviceClient
        .from('pdf_dossier_logs')
        .select('document_hash_sha256, generated_by, organization_id')
        .eq('organization_id', _orgA)
        .eq('sla_ledger_entry_id', entryId);

    expect(rows, hasLength(1));
    final row = rows.first;
    expect(row['organization_id'], equals(_orgA));
    expect(row['generated_by'], equals(_operatorId));

    // 4. Hash present in both the PDF and the DB row (1-click traceability).
    final loggedHash = row['document_hash_sha256'] as String;
    expect(loggedHash, hasLength(64)); // SHA-256 hex
    expect(pdfText, contains(loggedHash));
  });

  // ── LOG-E2 ───────────────────────────────────────────────────────────────────
  //
  // Cross-tenant attack: Org-B session generates dossier for Org-A ledger entry.
  // Handler's inline sovereignty guard fires before any DB I/O (INV-22).

  test('LOG-E2 [INV-22]: SovereigntyViolationException when '
      'jwtOrganizationId ≠ ledgerEntry.organizationId', () async {
    final authRepo = _MockAuthRepository();
    // Org-B session passes TenantValidationService step 1.
    when(
      () => authRepo.getUserBySessionId(any()),
    ).thenAnswer((_) async => const AuthUser(id: _operatorId, tenantId: _orgB));
    final client = _offlineClient();
    final handler = _handler(authRepo: authRepo, client: client);

    // Command: JWT = Org-B, requested = Org-B, but ledger entry = Org-A.
    final cmd = _command(
      orgId: _orgB,
      jwtOrgId: _orgB,
      ledgerEntry: _entry(
        eventId: _uuid.v4(),
        organizationId: _orgA, // cross-tenant mismatch
      ),
    );

    await expectLater(
      handler.handle(cmd),
      throwsA(isA<SovereigntyViolationException>()),
    );
    await client.dispose();
  });

  // ── LOG-E3 ───────────────────────────────────────────────────────────────────
  //
  // Structural guard: SlaLedgerEntry with both eventId and id null is rejected
  // before any I/O (INV-10).

  test(
    'LOG-E3 [INV-10]: IntegrityException when both eventId and id are null',
    () async {
      final authRepo = _MockAuthRepository();
      when(() => authRepo.getUserBySessionId(any())).thenAnswer(
        (_) async => const AuthUser(id: _operatorId, tenantId: _orgA),
      );
      final client = _offlineClient();
      final handler = _handler(authRepo: authRepo, client: client);

      final cmd = _command(
        orgId: _orgA,
        ledgerEntry: SlaLedgerEntry(
          // eventId: null, id: null — both absent → IntegrityException
          organizationId: _orgA,
          type: 'SANCTION_VERDICT',
          contractId: _contractId,
          planVersion: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 15),
        ),
      );

      await expectLater(
        handler.handle(cmd),
        throwsA(isA<IntegrityException>()),
      );
      await client.dispose();
    },
  );

  // ── LOG-E4 ───────────────────────────────────────────────────────────────────
  //
  // Session sovereignty: no active session → TenantValidationService
  // throws SovereigntyViolationException before any PDF or DB work (INV-1).

  test('LOG-E4 [INV-1]: SovereigntyViolationException when session is expired '
      'or invalid (TenantValidationService)', () async {
    final authRepo = _MockAuthRepository();
    // Simulates expired/invalid session — returns null.
    when(
      () => authRepo.getUserBySessionId(any()),
    ).thenAnswer((_) async => null);
    final client = _offlineClient();
    final handler = _handler(authRepo: authRepo, client: client);

    final cmd = _command(
      orgId: _orgA,
      ledgerEntry: _entry(eventId: _uuid.v4(), organizationId: _orgA),
    );

    await expectLater(
      handler.handle(cmd),
      throwsA(isA<SovereigntyViolationException>()),
    );
    await client.dispose();
  });
}
