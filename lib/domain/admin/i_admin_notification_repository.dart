/// Port for admin notification side-effects.
///
/// Concrete implementation: [SupabaseAdminNotificationRepository].
/// INV-18: Pure Dart interface — zero infrastructure dependencies.
abstract class IAdminNotificationRepository {
  /// Dispatches the [notify-invite] Edge Function.
  ///
  /// Failure is non-fatal by design — the invite link is always shown
  /// in the dialog as fallback. Callers MUST silently catch exceptions.
  Future<void> notifyInvite({
    required String email,
    required String inviteUrl,
    required String orgName,
  });
}
