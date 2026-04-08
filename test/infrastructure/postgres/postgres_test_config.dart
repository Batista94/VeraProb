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
      'sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz';

  /// Service-role key — bypassa RLS e tem permissões de admin no Auth.
  /// Gerado deterministicamente pelo `supabase start` local.
  /// NUNCA usar em produção ou expor ao cliente.
  ///
  /// Obtido via: `supabase status` → "service_role key"
  static const String serviceRoleKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hj04zWl196z2-SBc0';

  /// UUID sentinela para testes de integração. Identificador estável para
  /// evitar colisões entre runs sem precisar de fixture de organização real.
  static const String testOrgId = '00000000-0000-0000-0000-000000000001';

  static final Set<String> _seededOrgs = {};

  /// Garante que uma organização existe no banco para evitar violações de FK.
  /// Se [id] for nulo, usa [testOrgId].
  static Future<void> ensureSentinelOrg({
    SupabaseClient? client,
    String? id,
    String? name,
  }) async {
    final effectiveId = id ?? testOrgId;

    if (_seededOrgs.contains(effectiveId)) {
      return;
    }

    final effectiveClient =
        client ?? SupabaseClient(supabaseUrl, supabaseAnonKey);

    // CNPJ must be unique and usually 14 digits. We'll use a deterministic
    // derivation from the UUID to avoid collisions between different test orgs.
    final stripped = effectiveId.replaceAll('-', '');
    final numericCnpj = stripped.substring(stripped.length - 14);

    await effectiveClient.from('organizations').upsert({
      'id': effectiveId,
      'name': name ?? 'Sentinel Integration Test Org',
      'cnpj': numericCnpj,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');

    _seededOrgs.add(effectiveId);
  }

  static Future<SupabaseClient> createClient() async {
    // Mocking SharedPreferences to avoid MissingPluginException in unit tests
    // when Supabase.initialize is called.
    SharedPreferences.setMockInitialValues({});

    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
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
}
