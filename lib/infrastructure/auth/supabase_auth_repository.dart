import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/auth/auth_failure_exception.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';

/// Supabase implementation of [IAuthRepository].
///
/// Wraps `SupabaseClient.auth.*` so that no Widget ever imports
/// `supabase_flutter` directly (SRP-UI-LEAK prevention).
class SupabaseAuthRepository implements IAuthRepository {
  final SupabaseClient _client;

  SupabaseAuthRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  @override
  bool get isAuthenticated => _client.auth.currentSession != null;

  @override
  Stream<bool> get authStatusStream =>
      _client.auth.onAuthStateChange.map((state) => state.session != null);

  @override
  Future<String> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (res.user == null) {
      throw const AuthFailureException('Sign-in returned no user.');
    }
    return res.user!.id;
  }

  @override
  Future<String> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signUp(email: email, password: password);
    if (res.user == null) {
      throw const AuthFailureException('Sign-up returned no user.');
    }
    return res.user!.id;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> refreshSession() => _client.auth.refreshSession();
}
