import 'auth_failure_exception.dart';

/// Port for authentication operations.
///
/// Concrete implementation: [SupabaseAuthRepository].
/// INV-18: Pure Dart interface — zero infrastructure dependencies.
/// INV-6: SuperAdmin sign-out clears the MFA AAL2 session.
abstract class IAuthRepository {
  /// Returns true if there is an active session (synchronous read).
  bool get isAuthenticated;

  /// Stream of authentication status changes.
  ///
  /// Emits `true` on sign-in and `false` on sign-out.
  /// Replaces direct `auth.onAuthStateChange` subscriptions in widgets.
  Stream<bool> get authStatusStream;

  /// Signs in with email and password.
  ///
  /// Returns the [userId] on success.
  /// Throws [AuthFailureException] if the provider returns no user.
  Future<String> signInWithPassword({
    required String email,
    required String password,
  });

  /// Signs up a new user with email and password.
  ///
  /// Returns the [userId] on success.
  /// Throws [AuthFailureException] if the provider returns no user.
  Future<String> signUpWithPassword({
    required String email,
    required String password,
  });

  /// Signs out the current user from all sessions.
  Future<void> signOut();

  /// Refreshes the JWT session.
  ///
  /// Re-triggers the `custom_access_token_hook` so that
  /// `organization_id` and `role` claims are re-injected into the token.
  /// Called after invitation acceptance to hydrate the new JWT claims.
  Future<void> refreshSession();
}
