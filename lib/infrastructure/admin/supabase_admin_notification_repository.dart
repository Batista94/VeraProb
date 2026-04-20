import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/admin/i_admin_notification_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Supabase implementation of [IAdminNotificationRepository].
///
/// Wraps the [notify-invite] Edge Function call so that no Widget
/// ever calls `supabase.functions.invoke` directly (SRP-UI-LEAK prevention).
class SupabaseAdminNotificationRepository extends BasePostgresRepository
    implements IAdminNotificationRepository {
  SupabaseAdminNotificationRepository(super.client);

  @override
  Future<void> notifyInvite({
    required String email,
    required String inviteUrl,
    required String orgName,
  }) async {
    try {
      await client.functions.invoke(
        'notify-invite',
        body: {'email': email, 'inviteUrl': inviteUrl, 'orgName': orgName},
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'notification');
    }
  }
}
