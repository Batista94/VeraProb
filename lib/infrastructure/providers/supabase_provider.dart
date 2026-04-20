import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// INV-30 (DI Total — Anti-Singleton):
/// This provider is the **single bridge** between the Supabase singleton and
/// the Riverpod dependency graph. After app initialization, the client is
/// available here and MUST be used exclusively — no direct
/// `Supabase.instance.client` access anywhere else in the codebase.
///
/// **In production:** Initialized in `main()` after `Supabase.initialize()`.
/// **In tests:** Override with a mock/fake client via `ProviderScope(overrides: [...])`.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  throw UnimplementedError(
    'SupabaseClient must be provided via ProviderScope(overrides: [...]) '
    'or initialized before this provider is read. '
    'In production, main.dart overrides this after Supabase.initialize().',
  );
});

/// Test hook: use `supabaseClientProvider.overrideWithValue(mockClient)` directly.
///
/// Usage in tests:
/// ```dart
/// testWidgets('my test', (tester) async {
///   final mockClient = MockSupabaseClient();
///   await tester.pumpWidget(
///     ProviderScope(
///       overrides: [supabaseClientProvider.overrideWithValue(mockClient)],
///       child: MyApp(),
///     ),
///   );
/// });
/// ```
@visibleForTesting
Override supabaseClientOverride(SupabaseClient client) {
  return supabaseClientProvider.overrideWithValue(client);
}
