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
  Future<AuthUser?> getCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    // Delegates to the infrastructure mapper — extracts org_id from
    // app_metadata exclusively ([INV-1]).
    return SupabaseUserMapper.mapToAuthUser(user);
  }

  // ── Session Cache (LRU-style with TTL) ────────────────────────────────

  /// Cached AuthUser from the last successful session validation.
  AuthUser? _cachedSessionUser;

  /// UTC expiry timestamp for the cached session user.
  /// INV-6: All time comparisons use UTC.
  DateTime? _cacheExpiryUtc;

  /// The actual session token expiry time — used to reject cached entries
  /// whose underlying JWT has expired, even if the cache TTL is still valid.
  DateTime? _sessionExpiresAtUtc;

  /// TTL for the session cache — 30 seconds.
  /// Short enough to catch sign-out events, long enough to avoid redundant
  /// work during batch handler operations.
  static const _sessionCacheTtl = Duration(seconds: 30);

  @override
  Future<AuthUser?> getUserBySessionId(String sessionId) async {
    // INV-6: All time comparisons use UTC.
    final nowUtc = DateTime.now().toUtc(); // pr_scanner: ignore

    // Cache hit: within TTL AND session token not expired
    if (_cachedSessionUser != null &&
        _cacheExpiryUtc != null &&
        _sessionExpiresAtUtc != null &&
        nowUtc.isBefore(_cacheExpiryUtc!) &&
        nowUtc.isBefore(_sessionExpiresAtUtc!)) {
      return _cachedSessionUser;
    }

    // Cache miss — SERVER-SIDE validation via _client.auth.getUser().
    // This makes an HTTP call to Supabase Auth server to validate the JWT
    // signature and revocation status, closing the 1-hour JWT staleness window.
    // Any user ban or permission revocation in the Supabase Dashboard is
    // detected as soon as the 30s cache expires.
    try {
      final userResponse = await _client.auth.getUser();
      final user = userResponse.user;
      if (user == null) {
        _invalidateCache();
        return null;
      }

      if (user.appMetadata['org_id'] == null) {
        // Tenant isolation violation — no org in app_metadata
        _invalidateCache();
        return null;
      }

      final authUser = SupabaseUserMapper.mapToAuthUser(user);

      // Populate cache with both cache TTL and actual session expiry.
      // INV-6: Convert Unix timestamp (int seconds) to DateTime UTC.
      // Security: if expiresAt is unknown, do NOT cache — we can't verify
      // the session is still valid on cache hit.
      final session = _client.auth.currentSession;
      final expiresAtUnix = session?.expiresAt;
      if (expiresAtUnix == null) {
        _cachedSessionUser = authUser;
        _cacheExpiryUtc = null; // Null TTL = no caching
        _sessionExpiresAtUtc = null;
        return authUser;
      }

      _cachedSessionUser = authUser;
      _cacheExpiryUtc = nowUtc.add(_sessionCacheTtl);
      _sessionExpiresAtUtc = DateTime.fromMillisecondsSinceEpoch(
        expiresAtUnix * 1000,
      ).toUtc();

      return authUser;
    } on sb.AuthException {
      // Server-side auth failure (invalid JWT, revoked, etc.)
      _invalidateCache();
      return null;
    } on SocketException {
      _invalidateCache();
      return null;
    }
  }

  /// Clears the session cache entry.
  /// Called on sign-out, session refresh, and cache miss.
  void _invalidateCache() {
    _cachedSessionUser = null;
    _cacheExpiryUtc = null;
    _sessionExpiresAtUtc = null;
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut(scope: sb.SignOutScope.global);
      // INV-1: Invalidate cache on sign-out to prevent stale session reuse
      _invalidateCache();
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
      // INV-1: Invalidate cache on refresh — the JWT claims may have changed
      _invalidateCache();
    } on sb.AuthException catch (e) {
      throw _mapAuthException(e);
    } on SocketException {
      throw const AuthFailureException(
        'Erro de conexão com o servidor de autenticação.',
      );
    }
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
