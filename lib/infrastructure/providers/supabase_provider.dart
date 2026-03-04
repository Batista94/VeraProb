import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fase 0: Infra Neutra
/// A detached provider that exposes the initialized Supabase client.
/// This provider must not be consumed by any existing logic during this phase.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
