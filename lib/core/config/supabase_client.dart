import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class SupabaseConfig {
  // A02: Security Misconfiguration - Use Env Vars
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xyzcompany.supabase.co',
  );

  static const String supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'public-anon-key',
  );

  static Future<void> initialize() async {
    // Pending: Replace with actual credentials
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }
}
