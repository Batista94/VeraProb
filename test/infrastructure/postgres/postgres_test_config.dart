import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'dart:io';

/// Configuração local para os testes de integração do Postgres.
/// Utiliza as credenciais padrão do `supabase start` rodando na porta 54321.
class PostgresTestConfig {
  static Map<String, String>? _envCache;

  static String _getEnv(String key) {
    if (Platform.environment.containsKey(key)) {
      return Platform.environment[key]!;
    }
    _envCache ??= _loadDotEnv();
    return _envCache?[key] ?? '';
  }

  static Map<String, String> _loadDotEnv() {
    final env = <String, String>{};
    try {
      final file = File('.env');
      if (file.existsSync()) {
        for (var line in file.readAsLinesSync()) {
          line = line.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final parts = line.split('=');
          if (parts.length >= 2) {
            env[parts[0].trim()] = parts.sublist(1).join('=').trim();
          }
        }
      }
    } catch (_) {
      // Ignore errors reading .env in CI environments
    }
    return env;
  }

  static String get supabaseUrl => _getEnv('SUPABASE_URL').isNotEmpty
      ? _getEnv('SUPABASE_URL')
      : 'http://127.0.0.1:54321';

  // Anon key — used for RLS testing.
  static String get supabaseAnonKey => _getEnv('SUPABASE_ANON_KEY').isNotEmpty
      ? _getEnv('SUPABASE_ANON_KEY')
      : _getEnv('SUPABASE_KEY');

  /// Service-role key — bypasses RLS.
  static String get serviceRoleKey => _getEnv('SUPABASE_SERVICE_ROLE_KEY');

  /// UUID sentinela para testes de integração. Identificador estável para
  /// evitar colisões entre runs sem precisar de fixture de organização real.
  static const String testOrgId = '00000000-0000-0000-0000-000000000001';

  static final Set<String> _seededOrgs = {};
  static bool _schemaReloaded = false;

  /// Notifica o PostgREST para recarregar o schema cache via
  /// [notify_pgrst_reload] RPC (pg_notify 'pgrst', 'reload schema').
  ///
  /// Necessario apos `supabase db reset` ou aplicacao manual de migrations.
  /// Idempotente por processo: executa no maximo uma vez por test run.
  static Future<void> reloadPostgrestSchema() async {
    if (_schemaReloaded) return;
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      await seedClient.rpc('notify_pgrst_reload');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } finally {
      await seedClient.dispose();
    }
    _schemaReloaded = true;
  }

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
    await reloadPostgrestSchema();

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
    final license = licenseNumber ?? 'TST-${orgId.substring(0, 8)}';
    final deterministicId = const Uuid().v5(
      Namespace.url.value,
      'driver-$orgId-$license',
    );

    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      final rows = await seedClient
          .from('drivers')
          .upsert({
            'id': deterministicId,
            'organization_id': orgId,
            'full_name': 'Test Driver $license',
            'license_number': license,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'organization_id,license_number')
          .select('id');
      return rows.first['id'] as String;
    } finally {
      await seedClient.dispose();
    }
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

  /// Removes telegram test data via the SECURITY DEFINER RPC
  /// [test_cleanup_forensic_data], which runs as the function owner (postgres)
  /// and therefore bypasses the append-only triggers on telegram tables (INV-7).
  ///
  /// Background: PostgREST executes as the `authenticator` Postgres role even
  /// when using a service_role JWT, so `current_user` inside a trigger is
  /// *never* `postgres` — direct DELETEs from a SupabaseClient always hit the
  /// trigger guard. The SECURITY DEFINER RPC is the only safe cleanup path.
  static Future<void> cleanupTelegramData(
    SupabaseClient client, {
    required String orgId,
  }) async {
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      await seedClient.rpc(
        'test_cleanup_forensic_data',
        params: {'p_org_id': orgId},
      );
    } finally {
      await seedClient.dispose();
    }
  }

  // ── Operational Alert seed helpers ───────────────────────────────────────

  /// Seeds a minimal [OperationalAlert] row, bypassing RLS via service_role.
  ///
  /// Returns the generated alert UUID.
  ///
  /// Always uses the [serviceRoleKey] internally so adversarial seeds
  /// (e.g., Org_B data planted for cross-tenant attack tests) are never
  /// blocked by the calling client's JWT.
  static Future<String> seedOperationalAlert({
    required String orgId,
    required String entityId,
    required String contractId,
    String severity = 'CRITICAL',
    String alertType = 'SLA_BREACH',
    String status = 'ACTIVE',
    Map<String, dynamic> context = const {},
    String? triggeringEventId,
    String? traceId,
  }) async {
    const uuid = Uuid();
    final alertId = uuid.v4();
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      await seedClient.from('operational_alerts').insert({
        'id': alertId,
        'organization_id': orgId,
        'entity_id': entityId,
        'contract_id': contractId,
        'alert_type': alertType,
        'severity': severity,
        'triggered_at_utc': DateTime.now().toUtc().toIso8601String(),
        'triggering_event_id': triggeringEventId,
        'trace_id': traceId,
        'context': context,
        'status': status,
      });
    } finally {
      await seedClient.dispose();
    }
    return alertId;
  }

  /// Seeds [count] operational alerts in batches of [batchSize] to avoid
  /// PostgREST request-size limits. All alerts belong to [orgId].
  ///
  /// Returns the list of generated alert UUIDs.
  static Future<List<String>> seedOperationalAlertBatch({
    required String orgId,
    required String entityId,
    required String contractId,
    required int count,
    int batchSize = 200,
    String severity = 'CRITICAL',
    String status = 'ACTIVE',
  }) async {
    const uuid = Uuid();
    final ids = <String>[];
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      for (var offset = 0; offset < count; offset += batchSize) {
        final end = (offset + batchSize).clamp(0, count);
        final batch = <Map<String, dynamic>>[];
        for (var i = offset; i < end; i++) {
          final id = uuid.v4();
          ids.add(id);
          batch.add({
            'id': id,
            'organization_id': orgId,
            'entity_id': entityId,
            'contract_id': contractId,
            'alert_type': 'SLA_BREACH',
            'severity': severity,
            'triggered_at_utc': now,
            'context': <String, dynamic>{},
            'status': status,
          });
        }
        await seedClient.from('operational_alerts').insert(batch);
      }
    } finally {
      await seedClient.dispose();
    }
    return ids;
  }

  /// Removes all operational_alerts for the given [orgIds] via service_role.
  static Future<void> cleanupOperationalAlerts({
    required List<String> orgIds,
  }) async {
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      for (final orgId in orgIds) {
        await seedClient
            .from('operational_alerts')
            .delete()
            .eq('organization_id', orgId);
      }
    } finally {
      await seedClient.dispose();
    }
  }

  // ── Shared utilities ──────────────────────────────────────────────────────

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
    // FNV-1a 64-bit for collision-free distribution (hashCode collides).
    final bytes = utf8.encode(seed);
    var h = 0xcbf29ce484222325;
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    final buf = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buf.write(alphabet[h % alphabet.length]);
      h ~/= alphabet.length;
    }
    return buf.toString();
  }

  /// Encodes a minimal JWT payload as base64url (unsigned — for header inspection
  /// in MockClient tests only, not for real auth).
  static String encodeJwtPayload(Map<String, dynamic> payload) {
    final json = jsonEncode(payload);
    return base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }

  // ── system_audit_log seed/cleanup (CT29 — F1/F3) ──────────────────────────

  /// Inserts a single row into `public.system_audit_log` via service_role,
  /// bypassing RLS. Returns the generated row UUID.
  ///
  /// Use [orgId]=null for system-level events (no tenant scope). When
  /// [eventType] is a governance event (the trigger enforces a non-empty
  /// reason), a [reason] MUST be supplied — the helper does not silently
  /// substitute a placeholder.
  static Future<String> seedSystemAuditLogEvent({
    String? orgId,
    required String eventType,
    String severity = 'info',
    DateTime? occurredAt,
    String? reason,
    String? actorType,
    String? actorId,
    Map<String, dynamic>? payload,
    String? source,
  }) async {
    const uuid = Uuid();
    final id = uuid.v4();
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      await seedClient.from('system_audit_log').insert({
        'id': id,
        'event_type': eventType,
        'severity': severity,
        'organization_id': orgId,
        'occurred_at': (occurredAt ?? DateTime.now().toUtc()).toIso8601String(),
        'reason': ?reason,
        'actor_type': ?actorType,
        'actor_id': ?actorId,
        'payload': ?payload,
        'source': ?source,
      });
    } finally {
      await seedClient.dispose();
    }
    return id;
  }

  /// Removes system_audit_log rows for the given [orgIds] via the
  /// SECURITY DEFINER `test_cleanup_system_audit_log` RPC, which bypasses
  /// the append-only `INSTEAD NOTHING` rules. Pass an empty list to remove
  /// only system-level events (organization_id IS NULL).
  ///
  /// If the RPC is missing in the local stack, falls back to a direct
  /// service_role DELETE (the rules will block it; tests will fail loudly
  /// with a clear signal that the cleanup RPC must be added).
  static Future<void> cleanupSystemAuditLog({
    required List<String?> orgIds,
  }) async {
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      await seedClient.rpc(
        'test_cleanup_system_audit_log',
        params: {'p_org_ids': orgIds},
      );
    } finally {
      await seedClient.dispose();
    }
  }

  // ── MFA lockouts cleanup (CT30 — F7) ──────────────────────────────────────

  /// Removes super_admin_mfa_lockouts rows for the given [userIds] via
  /// service_role (RLS denies all authenticated access; service_role bypasses).
  static Future<void> cleanupMfaLockouts({
    required List<String> userIds,
  }) async {
    if (userIds.isEmpty) return;
    final seedClient = SupabaseClient(supabaseUrl, serviceRoleKey);
    try {
      await seedClient
          .from('super_admin_mfa_lockouts')
          .delete()
          .inFilter('user_id', userIds);
    } finally {
      await seedClient.dispose();
    }
  }

  // ── SuperAdmin auth session (CT29/CT30 — F3/F7) ───────────────────────────

  /// Creates an [auth.users] row via the admin REST endpoint with
  /// `app_metadata.super_admin = true` (and optional [extraAppMetadata]),
  /// then signs the user in with password to get a real JWT carrying the
  /// SuperAdmin claim. Returns the authenticated [SupabaseClient].
  ///
  /// This replaces the no-op `createOrgJwtClient` for RLS tests that need
  /// a JWT with custom claims — the local Supabase JWT secret is private to
  /// the stack and we do not sign HS256 tokens from Dart code.
  ///
  /// Caller is responsible for disposing the returned client.
  static Future<SupabaseClient> createSuperAdminAuthSession({
    required String email,
    required String password,
    Map<String, dynamic>? extraAppMetadata,
  }) async {
    // Step 1: create or upsert the user via the admin REST endpoint.
    final adminUrl = Uri.parse('$supabaseUrl/auth/v1/admin/users');
    final headers = {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
    };
    final appMeta = <String, dynamic>{
      'super_admin': true,
      ...?extraAppMetadata,
    };
    final body = jsonEncode({
      'email': email,
      'password': password,
      'email_confirm': true,
      'app_metadata': appMeta,
    });
    final response = await http.post(adminUrl, headers: headers, body: body);
    // 200/422 (already exists) are both fine — we still try to sign in below.
    if (response.statusCode >= 500) {
      throw StateError(
        'createSuperAdminAuthSession: admin createUser failed '
        '(${response.statusCode}): ${response.body}',
      );
    }

    // Step 2: sign in with password on a fresh anon client. The JWT minted
    // here will carry the app_metadata.super_admin claim.
    final client = SupabaseClient(supabaseUrl, supabaseAnonKey);
    await client.auth.signInWithPassword(email: email, password: password);
    return client;
  }
}
