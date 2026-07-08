// import 'dart:io'; (Removed to fix web build)

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:veraprob/core/utils/jwt_utils.dart';
import 'package:veraprob/domain/auth/auth_failure_exception.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/infrastructure/auth/supabase_user_mapper.dart';
import 'package:veraprob/infrastructure/shared/auth_error_interceptor.dart';

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
class SupabaseAuthRepository
    with AuthErrorInterceptor
    implements IAuthRepository {
  final sb.SupabaseClient _client;

  /// INV-30: SupabaseClient must be injected — no fallback to singleton.
  SupabaseAuthRepository(this._client);

  @override
  bool get isAuthenticated {
    final session = _client.auth.currentSession;
    return session != null &&
        (!session.isExpired ||
            (session.refreshToken != null && session.refreshToken!.isNotEmpty));
  }

  @override
  Stream<bool> get authStatusStream => _client.auth.onAuthStateChange.map((
    state,
  ) {
    final session = state.session;
    return session != null &&
        (!session.isExpired ||
            (session.refreshToken != null && session.refreshToken!.isNotEmpty));
  });

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
    } catch (e) {
      if (e.toString().contains('SocketException')) {
        throw const AuthFailureException(
          'Erro de conexão com o servidor de autenticação.',
        );
      }
      if (e is sb.AuthException) {
        throw mapAuthExceptionToDomain(e);
      }
      rethrow;
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
    } catch (e) {
      if (e.toString().contains('SocketException')) {
        throw const AuthFailureException(
          'Erro de conexão com o servidor de autenticação.',
        );
      }
      if (e is sb.AuthException) {
        throw mapAuthExceptionToDomain(e);
      }
      rethrow;
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
      final userResponse = await _client.auth.getUser(sessionId);
      final user = userResponse.user;
      if (user == null) {
        _invalidateCache();
        return null;
      }

      // Read org_id from JWT access token claims (hook-injected).
      // raw_app_meta_data (user.appMetadata) is not updated by the hook.
      final jwtClaims = decodeJwtPayload(sessionId);
      final jwtAppMeta = jwtClaims['app_metadata'] as Map<String, dynamic>?;
      if (jwtAppMeta?['org_id'] == null) {
        _invalidateCache();
        return null;
      }

      final authUser = SupabaseUserMapper.mapToAuthUserFromJwtClaims(
        user,
        jwtClaims,
      );

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
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('ClientException')) {
        throw const AuthFailureException(
          'Falha de comunicação com o servidor de autenticação. Tente novamente.',
        );
      }
      // Server-side auth failure (invalid JWT, revoked, etc.)
      if (e is sb.AuthException && e.code == 'session_not_found') {
        try {
          await _client.auth.signOut(scope: sb.SignOutScope.local);
        } catch (_) {}
      }
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
    } catch (e) {
      if (e.toString().contains('SocketException')) {
        throw const AuthFailureException(
          'Erro de conexão com o servidor de autenticação.',
        );
      }
      if (e is sb.AuthException) {
        throw mapAuthExceptionToDomain(e);
      }
      rethrow;
    }
  }

  @override
  Future<void> refreshSession() async {
    try {
      await _client.auth.refreshSession();
      // INV-1: Invalidate cache on refresh — the JWT claims may have changed
      _invalidateCache();
    } catch (e) {
      if (e.toString().contains('SocketException')) {
        throw const AuthFailureException(
          'Erro de conexão com o servidor de autenticação.',
        );
      }
      if (e is sb.AuthException) {
        throw mapAuthExceptionToDomain(e);
      }
      rethrow;
    }
  }

  // ── Error Mapping ──────────────────────────────────────────────────────────
}
