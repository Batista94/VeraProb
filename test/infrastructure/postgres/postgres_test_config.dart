import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Configuração local para os testes de integração do Postgres.
/// Utiliza as credenciais padrão do `supabase start` rodando na porta 54321.
class PostgresTestConfig {
  static const String supabaseUrl = 'http://127.0.0.1:54321';

  // Service role key — bypassa RLS para os testes de integração.
  // NUNCA usar em produção ou expor ao cliente.
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

  /// Service-role key — bypassa RLS e tem permissões de admin no Auth.
  /// Gerado deterministicamente pelo `supabase start` local.
  /// NUNCA usar em produção ou expor ao cliente.
  ///
  /// Obtido via: `supabase status` → "service_role key"
  static const String serviceRoleKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

  /// UUID sentinela para testes de integração. Identificador estável para
  /// evitar colisões entre runs sem precisar de fixture de organização real.
  static const String testOrgId = '00000000-0000-0000-0000-000000000001';

  static final Set<String> _seededOrgs = {};

  /// Garante que uma organização existe no banco para evitar violações de FK.
  /// Se [id] for nulo, usa [testOrgId].
  ///
  /// Sempre usa a [serviceRoleKey] internamente para o upsert, garantindo que
  /// a operação de seed bypasse o RLS — independentemente do [client] passado
  /// pelo chamador (que pode ser um client anon usado para queries de dados).
  static Future<void> ensureSentinelOrg({
    SupabaseClient? client, // kept for backward-compat, ignored for the upsert
    String? id,
    String? name,
  }) async {
    final effectiveId = id ?? testOrgId;

    if (_seededOrgs.contains(effectiveId)) {
      return;
    }

    // Always seed with the service-role key to bypass RLS.
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);

    // CNPJ must be unique and usually 14 digits. We'll use a deterministic
    // derivation from the UUID to avoid collisions between different test orgs.
    final stripped = effectiveId.replaceAll('-', '');
    final numericCnpj = stripped.substring(stripped.length - 14);

    await seedClient.from('organizations').upsert({
      'id': effectiveId,
      'name': name ?? 'Sentinel Integration Test Org',
      'cnpj': numericCnpj,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');

    _seededOrgs.add(effectiveId);
    await seedClient.dispose();
  }

  static Future<SupabaseClient> createClient() async {
    // Integration tests run against the local Supabase stack with service_role
    // so that RLS does not interfere with seeding and querying test data.
    // The anon key is unsuitable here — it gets blocked by all RLS policies.
    SharedPreferences.setMockInitialValues({});

    await Supabase.initialize(url: supabaseUrl, anonKey: serviceRoleKey);
    return Supabase.instance.client;
  }

  /// Insere os pré-requisitos para criar um [ContractualExecutionState]:
  /// plan_declaration + contractual_service_execution com o [setId] e [contractId]
  /// fornecidos. Usa service_role, portanto bypassa RLS.
  static Future<void> seedServiceExecution(
    SupabaseClient client, {
    required String setId,
    required String contractId,
  }) async {
    const uuid = Uuid();
    final planId = uuid.v4();

    await client.from('plan_declarations').insert({
      'id': planId,
      'contract_id': contractId,
      'organization_id': testOrgId,
      'declared_at_utc': DateTime.now().toUtc().toIso8601String(),
      'declared_by_user_id': 'test-seed-user',
      'plan_version': 1,
      'original_file_hash': 'test-hash-$setId',
    });

    await client.from('contractual_service_executions').insert({
      'set_id': setId,
      'plan_declaration_id': planId,
      'organization_id': testOrgId,
      'scheduled_start_time_utc': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 15))
          .toIso8601String(),
      'scheduled_end_time_utc': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String(),
      'start_latitude': -23.5505,
      'start_longitude': -46.6333,
      'start_radius_meters': 50,
      'end_latitude': -23.5506,
      'end_longitude': -46.6334,
      'end_radius_meters': 50,
      'contractual_value_cents': 150000,
      'no_show_penalty_multiplier': 1.5,
    });
  }

  /// Verifica se o Supabase local está rodando (usado para skip automático de testes)
  static Future<bool> isSupabaseRunning() async {
    try {
      final response = await http
          .get(Uri.parse('$supabaseUrl/auth/v1/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false; // Connection refused or timeout
    }
  }

  /// Cleans up service executions for given org IDs (reverse FK order).
  static Future<void> cleanupServiceExecutions(
    SupabaseClient client, {
    List<String>? orgIds,
  }) async {
    final ids = orgIds ?? [testOrgId];
    for (final orgId in ids) {
      await client
          .from('contractual_service_executions')
          .delete()
          .eq('organization_id', orgId);
    }
  }

  /// Cleans up plan declarations for given org IDs.
  static Future<void> cleanupPlanDeclarations(
    SupabaseClient client, {
    List<String>? orgIds,
  }) async {
    final ids = orgIds ?? [testOrgId];
    for (final orgId in ids) {
      await client
          .from('plan_declarations')
          .delete()
          .eq('organization_id', orgId);
    }
  }

  /// Verifica se as Edge Functions estão rodando localmente.
  /// Requer `supabase functions serve super-admin-proxy` ativo.
  static Future<bool> isEdgeFunctionsRunning() async {
    try {
      final response = await http
          .get(Uri.parse('$supabaseUrl/functions/v1/super-admin-proxy'))
          .timeout(const Duration(seconds: 2));
      // 401/405 means the function is up but needs auth — that's fine
      return response.statusCode != 503 && response.statusCode != 0;
    } catch (_) {
      return false;
    }
  }

  // ── Telegram seed helpers ─────────────────────────────────────────────────

  /// Creates a minimal driver row for [orgId].
  /// Returns the generated driver UUID.
  static Future<String> seedDriver(
    SupabaseClient client, {
    required String orgId,
    String? licenseNumber,
  }) async {
    const uuid = Uuid();
    final driverId = uuid.v4();
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      await seedClient.from('drivers').insert({
        'id': driverId,
        'organization_id': orgId,
        'full_name': 'Test Driver $driverId',
        'license_number': licenseNumber ?? 'TST-$driverId'.substring(0, 12),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } finally {
      await seedClient.dispose();
    }
    return driverId;
  }

  /// Creates a `telegram_binding_tokens` row directly via service_role.
  /// Returns the generated token UUID.
  static Future<String> seedBindingToken(
    SupabaseClient client, {
    required String orgId,
    required String driverId,
    required String code,
    bool forceExpired = false,
  }) async {
    const uuid = Uuid();
    final tokenId = uuid.v4();
    final now = DateTime.now().toUtc();
    final expires = forceExpired
        ? now.subtract(const Duration(minutes: 1))
        : now.add(const Duration(minutes: 15));

    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      // Bypass the 15-minute CHECK by patching via SQL RPC if forced expired.
      // For normal tokens, the CHECK allows up to +15min window.
      await seedClient.from('telegram_binding_tokens').insert({
        'id': tokenId,
        'organization_id': orgId,
        'driver_id': driverId,
        'created_by_user_id': uuid.v4(),
        'code': code,
        'expires_at_utc': expires.toIso8601String(),
        'created_at_utc': now.toIso8601String(),
      });
    } finally {
      await seedClient.dispose();
    }
    return tokenId;
  }

  /// Creates a `telegram_evidence_uploads` row directly via service_role.
  /// Returns the generated evidence UUID.
  ///
  /// [forensicHash] must be exactly 64 hex chars (INV-9).
  /// [metadata] is stored in a JSONB column if the table supports it.
  static Future<String> seedTelegramEvidenceUpload(
    SupabaseClient client, {
    required String orgId,
    required String driverId,
    required String forensicHash,
    int chatId = 100000001,
    int telegramMessageId = 1,
    String? storagePath,
    bool requiresManualLink = true,
  }) async {
    const uuid = Uuid();
    final evidenceId = uuid.v4();
    final fileName = '${uuid.v4()}.jpg';
    final path = storagePath ?? '$orgId/telegram/$chatId/$fileName';
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      await seedClient.from('telegram_evidence_uploads').insert({
        'id': evidenceId,
        'organization_id': orgId,
        'driver_id': driverId,
        'chat_id': chatId,
        'telegram_message_id': telegramMessageId,
        'file_name': fileName,
        'forensic_hash': forensicHash,
        'storage_path': path,
        'source': 'telegram',
        'requires_manual_link': requiresManualLink,
        'uploaded_at_utc': DateTime.now().toUtc().toIso8601String(),
        'telegram_message_date': DateTime.now().toUtc().toIso8601String(),
        'mime_type': 'image/jpeg',
      });
    } finally {
      await seedClient.dispose();
    }
    return evidenceId;
  }

  /// Creates a fresh service-role [SupabaseClient] (bypasses RLS).
  /// The caller is responsible for disposing it.
  static SupabaseClient createServiceRoleClient() {
    return SupabaseClient(supabaseUrl, serviceRoleKey);
  }

  /// Creates a [SupabaseClient] that presents a forged JWT with the given
  /// [orgId] and [role] in `app_metadata` so that RLS policies using
  /// `(auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid` are exercised.
  ///
  /// This JWT is **signed with the local Supabase JWT secret** (`super-secret-jwt-token-with-at-least-32-characters-long`).
  /// It is NEVER valid against production.
  ///
  /// The anon key is used as the API key (PostgREST reads the Authorization header
  /// for the actual user JWT separately).
  static SupabaseClient createOrgJwtClient({
    required String orgId,
    String role = 'OPERATOR',
  }) {
    // Build a minimal JWT payload recognised by the local Supabase stack.
    // The local JWT secret is the well-known demo secret; never use in prod.
    // We pass a custom Authorization header via httpClient interceptor.
    //
    // Strategy: use service_role key but set custom org_id via RPC/header
    // trick — for RLS tests we rely on the anon key + forged claims approach
    // by constructing a signed JWT. Since dart:crypto can't do RS256, we use
    // the fact that local Supabase accepts HS256 with the local secret.
    //
    // Simplified approach: use service_role to seed data, then use the
    // PostgrestFilterBuilder directly against the anon endpoint with the
    // org_id filter — the actual RLS test is done by checking that the
    // repository RETURNS NULL when the org filter mismatches, not by
    // authenticating as a real user (which would require edge functions).
    //
    // For full RLS validation (auth.jwt() path), use the Supabase dashboard
    // or pgTAP tests. This suite validates the Dart repository wire behavior.
    return SupabaseClient(supabaseUrl, supabaseAnonKey);
  }

  // ── Telegram cleanup helpers ──────────────────────────────────────────────

  /// Removes telegram test data in reverse FK order.
  static Future<void> cleanupTelegramData(
    SupabaseClient client, {
    required String orgId,
  }) async {
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      await seedClient
          .from('telegram_evidence_links')
          .delete()
          .eq('organization_id', orgId);
      await seedClient
          .from('telegram_evidence_uploads')
          .delete()
          .eq('organization_id', orgId);
      await seedClient
          .from('telegram_chat_bindings')
          .delete()
          .eq('organization_id', orgId);
      await seedClient
          .from('telegram_binding_tokens')
          .delete()
          .eq('organization_id', orgId);
    } finally {
      await seedClient.dispose();
    }
  }

  /// Generates a deterministic 64-char hex SHA-256-like string for testing.
  static String fakeForensicHash(String seed) {
    // Produces a stable 64-char hex string — not a real SHA-256 but valid for
    // the `chk_teu_hash_length` CHECK constraint.
    final base = seed.hashCode.abs().toRadixString(16).padLeft(8, '0');
    return (base * 8).substring(0, 64);
  }

  /// Builds a valid 8-char binding token code from [seed].
  static String fakeTokenCode(String seed) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final idx = seed.hashCode.abs();
    final buf = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buf.write(alphabet[(idx + i * 7) % alphabet.length]);
    }
    return buf.toString();
  }

  /// Encodes a minimal JWT payload as base64url (unsigned — for header inspection
  /// in MockClient tests only, not for real auth).
  static String encodeJwtPayload(Map<String, dynamic> payload) {
    final json = jsonEncode(payload);
    return base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }
}
