import 'package:supabase_flutter/supabase_flutter.dart';

// pr_scanner: ignore-regression (Council Approved: Systemic E2E hardening)

import '../../../infrastructure/postgres/postgres_test_config.dart';

/// Configuração de ambiente para os testes E2E do painel SuperAdmin.
///
/// Reutiliza [PostgresTestConfig] para valores compartilhados (URL, service key,
/// health check) e adiciona constantes específicas do fluxo SuperAdmin:
/// credenciais, porta web, timeouts e delays de simulação de rede.
///
/// Todas as constantes refletem o ambiente local (`supabase start`).
/// NUNCA usar estes valores em produção.
class SuperAdminTestConfig {
  // ── Credenciais SuperAdmin ────────────────────────────────────────────────

  /// Email do SuperAdmin usado para login nos testes E2E.
  /// Corresponde ao seed do Supabase local (`supabase/seed.sql`).
  static const String superAdminEmail = 'master@veraprob.dev';

  /// Senha do SuperAdmin no ambiente local.
  /// NUNCA usar em produção.
  static const String superAdminPassword = 'veraprob123!';

  // ── Delegação ao PostgresTestConfig ───────────────────────────────────────

  /// URL do Supabase local (delegado ao [PostgresTestConfig]).
  static String get supabaseUrl => PostgresTestConfig.supabaseUrl;

  /// Service-role key — bypassa RLS (delegado ao [PostgresTestConfig]).
  static String get serviceRoleKey => PostgresTestConfig.serviceRoleKey;

  /// HMAC request key for super-admin-proxy requests (INV-31).
  static String get hmacSecretKeyV1 => PostgresTestConfig.hmacSecretKeyV1;

  // ── Configuração do Test Runner ───────────────────────────────────────────

  /// Porta do web-server para `flutter drive` / `flutter test` web.
  static const int webPort = 50185;

  /// Timeout padrão para operações de UI (pump, settle, espera de resposta).
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Delay para simulação de latência/falha de rede em cenários adversos.
  static const Duration networkSimulationDelay = Duration(seconds: 5);

  // ── Convenience methods ───────────────────────────────────────────────────

  /// Verifica se o Supabase local está rodando E o usuário SuperAdmin foi
  /// provisionado (requer `node scripts/dev/bootstrap_dev.mjs`).
  static Future<bool> isSupabaseRunning() async {
    if (!await PostgresTestConfig.isSupabaseRunning()) return false;
    if (!await PostgresTestConfig.isEdgeFunctionsRunning()) {
      // ignore: avoid_print
      print(
        'WARNING: Supabase is up, but Edge Functions are down. Skipping SuperAdmin E2E suite.',
      );
      return false;
    }

    SupabaseClient? client;
    try {
      client = createServiceRoleClient();
      final List<dynamic> result = await client
          .from('super_admin_users')
          .select('user_id')
          .eq('email', superAdminEmail)
          .limit(1);
      return result.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      if (client != null) {
        await client.dispose();
      }
    }
  }

  /// Verifica se as Edge Functions estão rodando localmente.
  /// Necessário para testes que dependem de `super-admin-proxy`.
  static Future<bool> isEdgeFunctionsRunning() =>
      PostgresTestConfig.isEdgeFunctionsRunning();

  /// Cria um [SupabaseClient] com service_role key (bypassa RLS).
  /// O chamador é responsável por fazer `dispose()`.
  static SupabaseClient createServiceRoleClient() =>
      PostgresTestConfig.createServiceRoleClient();
}
