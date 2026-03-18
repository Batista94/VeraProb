import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'environment.dart';

final supabase = Supabase.instance.client;

/// Initializes the Supabase client using [EnvironmentConfig].
///
/// Credential resolution order:
///  1. `.env` file (local dev convenience — never committed)
///  2. `--dart-define` values (CI/CD injection — no secrets in source)
///  3. Silent skip (in-memory test mode, no Supabase required)
class SupabaseConfig {
  static Future<void> initialize() async {
    // Load .env for local dev. Silently ignored in CI (file won't exist).
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Expected in CI/CD environments where --dart-define is used instead.
    }

    // .env takes priority over --dart-define for local dev overrides.
    final url =
        dotenv.env['SUPABASE_URL'] ?? EnvironmentConfig.supabaseUrl;
    final anonKey =
        dotenv.env['SUPABASE_KEY'] ?? EnvironmentConfig.supabaseAnonKey;

    if (url.isEmpty || anonKey.isEmpty) {
      // Allowed in Phase 0 / in-memory test mode — no Supabase connection needed.
      return;
    }

    try {
      await Supabase.initialize(url: url, anonKey: anonKey);
    } catch (_) {
      // Allowed to fail if running strictly local tests without a real Supabase instance.
    }
  }
}
