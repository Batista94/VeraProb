/// Defines the runtime environment for the PactaFlow application.
///
/// Values are injected at compile time via `--dart-define` in CI/CD pipelines,
/// or read from a local `.env` file during development.
/// NEVER hard-code credentials — use [EnvironmentConfig] accessors.
///
/// Invocation examples:
///   Dev:     flutter run  (reads .env automatically)
///   Staging: flutter run  --dart-define=ENV=staging --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
///   Prod:    flutter build web --dart-define=ENV=prod --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
enum AppEnvironment {
  dev,
  staging,
  prod;

  static AppEnvironment fromString(String value) {
    return AppEnvironment.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => AppEnvironment.dev,
    );
  }
}

/// Central access point for all environment-specific configuration.
///
/// Resolution order (highest priority first):
///  1. `--dart-define` values (injected by CI/CD — production-safe)
///  2. `.env` file values (local development convenience)
///  3. Default values (safe fallbacks for in-memory test mode)
class EnvironmentConfig {
  EnvironmentConfig._();

  // ── Environment Detection ───────────────────────────
  static const _envName = String.fromEnvironment('ENV', defaultValue: 'dev');

  /// The currently active environment.
  static AppEnvironment get environment =>
      AppEnvironment.fromString(_envName);

  static bool get isDev => environment == AppEnvironment.dev;
  static bool get isStaging => environment == AppEnvironment.staging;
  static bool get isProd => environment == AppEnvironment.prod;

  // ── Supabase Credentials (injected via --dart-define) ──
  /// Supabase project URL. In dev, overridden by .env file.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anonymous/public key. In dev, overridden by .env file.
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_KEY');

  // ── Feature Flags ────────────────────────────────────
  /// Show debug banners and verbose logging only in dev/staging.
  static bool get showDebugBanner => !isProd;

  /// Enable Sentry error reporting in staging and production.
  static bool get sentryEnabled => isStaging || isProd;

  /// Sentry DSN — injected per environment.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  // ── Map Config ───────────────────────────────────────
  static const mapTilerKey = String.fromEnvironment(
    'MAPTILER_KEY',
    defaultValue: 'get_your_own_key',
  );

  // ── Validation ───────────────────────────────────────
  /// Returns true if the minimum required credentials are present.
  /// Only fails silently in dev (in-memory test mode).
  static bool get hasSupabaseCredentials =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Human-readable environment label for logging and UI.
  static String get label => switch (environment) {
    AppEnvironment.dev => '🔧 DEV',
    AppEnvironment.staging => '🧪 STAGING',
    AppEnvironment.prod => '🚀 PROD',
  };
}
