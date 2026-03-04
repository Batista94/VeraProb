import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuração local para os testes de integração do Postgres.
/// Utiliza as credenciais padrão do `supabase start` rodando na porta 54321.
class PostgresTestConfig {
  static const String supabaseUrl = 'http://127.0.0.1:54321';
  // Chave anônima padrão do ambiente local do Supabase CLI
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRlZmF1bHQiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTY0MDI3NTIwMCwiZXhwIjoxOTU1ODUxMjAwfQ.B_L-kX1nEx0xGz-yU2Zszf3t60h0yqO0uX7oH8o--Jk';

  static Future<SupabaseClient> createClient() async {
    // Para testes isolados, inicializamos uma nova instância sem afetar o global
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    return Supabase.instance.client;
  }
}
