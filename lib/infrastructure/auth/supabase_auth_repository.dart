import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:veraprob/core/config/supabase_client.dart' as config;
import 'package:veraprob/domain/auth/auth_failure_exception.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/infrastructure/auth/supabase_user_mapper.dart';

/// Supabase implementation of [IAuthRepository].
///
/// Wraps `SupabaseClient.auth.*` so that no Widget ever imports
/// `supabase_flutter` directly (SRP-UI-LEAK prevention).
///
/// Security guarantees:
/// - All [sb.AuthException] codes are mapped to domain
///   [AuthFailureException] messages ([INV-18]).
/// - [SocketException] (offline) is caught and translated to a user-friendly
///   connection error.
/// - [signOut] uses [sb.SignOutScope.global] to invalidate tokens on
///   all devices (session replay prevention).
class SupabaseAuthRepository implements IAuthRepository {
  final sb.SupabaseClient _client;

  SupabaseAuthRepository([sb.SupabaseClient? client])
    : _client = client ?? config.supabase;

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
    try {
      final res = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.user == null) {
        throw const AuthFailureException('Sign-in returned no user.');
      }
      return res.user!.id;
    } on sb.AuthException catch (e) {
      throw _mapAuthException(e);
    } on SocketException {
      throw const AuthFailureException(
        'Erro de conexão com o servidor de autenticação.',
      );
    }
  }

  @override
  Future<String> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signUp(email: email, password: password);
      if (res.user == null) {
        throw const AuthFailureException('Sign-up returned no user.');
      }
      return res.user!.id;
    } on sb.AuthException catch (e) {
      throw _mapAuthException(e);
    } on SocketException {
      throw const AuthFailureException(
        'Erro de conexão com o servidor de autenticação.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut(scope: sb.SignOutScope.global);
    } on sb.AuthException catch (e) {
      throw _mapAuthException(e);
    } on SocketException {
      throw const AuthFailureException(
        'Erro de conexão com o servidor de autenticação.',
      );
    }
  }

  @override
  Future<void> refreshSession() async {
    try {
      await _client.auth.refreshSession();
    } on sb.AuthException catch (e) {
      throw _mapAuthException(e);
    } on SocketException {
      throw const AuthFailureException(
        'Erro de conexão com o servidor de autenticação.',
      );
    }
  }

  @override
  Future<AuthUser?> getCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    // Delegates to the infrastructure mapper — extracts org_id from
    // app_metadata exclusively ([INV-1]).
    return SupabaseUserMapper.mapToAuthUser(user);
  }

  // ── Error Mapping ──────────────────────────────────────────────────────

  /// Maps Supabase auth error codes to domain-level messages.
  ///
  /// Security: `invalid_credentials` and `user_not_found` return the SAME
  /// message to prevent user enumeration attacks.
  AuthFailureException _mapAuthException(sb.AuthException e) {
    return switch (e.code) {
      'invalid_credentials' ||
      'user_not_found' => const AuthFailureException('Credenciais inválidas.'),
      'email_not_confirmed' => const AuthFailureException(
        'E-mail pendente de confirmação.',
      ),
      'weak_password' => const AuthFailureException(
        'A senha não atende os requisitos de segurança.',
      ),
      'rate_limit_exceeded' ||
      'over_request_rate_limit' => const AuthFailureException(
        'Muitas tentativas. Tente novamente mais tarde.',
      ),
      _ => const AuthFailureException('Erro de autenticação. Tente novamente.'),
    };
  }
}
