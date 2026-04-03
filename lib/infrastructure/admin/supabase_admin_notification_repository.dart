import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/admin/i_admin_notification_repository.dart';

/// Supabase implementation of [IAdminNotificationRepository].
///
/// Wraps the [notify-invite] Edge Function call so that no Widget
/// ever calls `supabase.functions.invoke` directly (SRP-UI-LEAK prevention).
class SupabaseAdminNotificationRepository
    implements IAdminNotificationRepository {
  final SupabaseClient _client;

  SupabaseAdminNotificationRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  @override
  Future<void> notifyInvite({
    required String email,
    required String inviteUrl,
    required String orgName,
  }) async {
    await _client.functions.invoke(
      'notify-invite',
      body: {'email': email, 'inviteUrl': inviteUrl, 'orgName': orgName},
    );
  }
}
