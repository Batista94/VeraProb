import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Configuração local para os testes de integração do Postgres.
/// Utiliza as credenciais padrão do `supabase start` rodando na porta 54321.
class PostgresTestConfig {
  static const String supabaseUrl = 'http://127.0.0.1:54321';
  // Chave anônima padrão do ambiente local do Supabase CLI
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRlZmF1bHQiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTY0MDI3NTIwMCwiZXhwIjoxOTU1ODUxMjAwfQ.B_L-kX1nEx0xGz-yU2Zszf3t60h0yqO0uX7oH8o--Jk';

  static Future<SupabaseClient> createClient() async {
    // Mocking SharedPreferences to avoid MissingPluginException in unit tests
    // when Supabase.initialize is called.
    SharedPreferences.setMockInitialValues({});
    
    await Supabase.initialize(
      url: supabaseUrl, 
      anonKey: supabaseAnonKey,
    );
    return Supabase.instance.client;
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
}
