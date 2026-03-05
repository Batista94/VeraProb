import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final supabase = Supabase.instance.client;

class SupabaseConfig {
  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: ".env");
    } catch (e) {
      // It's okay if .env is missing in CI or if environment is injected via --dart-define
    }

    final supabaseUrl =
        dotenv.env['SUPABASE_URL'] ??
        const String.fromEnvironment('SUPABASE_URL');

    final supabaseAnonKey =
        dotenv.env['SUPABASE_KEY'] ??
        const String.fromEnvironment('SUPABASE_KEY');

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      // In Phase 0, we allow fallback for the InMemory persistence mode tests.
      return;
    }

    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    } catch (e) {
      // Allowed to fail if running strictly local tests without mock setup.
    }
  }
}
