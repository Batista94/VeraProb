import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../application/sla_audit/webhook_dispatcher_port.dart';

class SupabaseWebhookDispatchKicker implements IWebhookDispatcherPort {
  final SupabaseClient _supabaseClient;

  SupabaseWebhookDispatchKicker(this._supabaseClient);

  @override
  Future<void> dispatchVerdictWebhooks({required String organizationId}) async {
    // Fire and forget pattern. We do not await this in the main execution path.
    // If it fails, the cron job (reconciler) will pick up the pending webhooks.
    try {
      unawaited(
        _supabaseClient.functions
            .invoke(
              'dispatch-verdict-webhooks',
              body: {'organization_id': organizationId},
            )
            .catchError((e) {
              // Silently capture error. Network failures here are expected and handled by cron.
              return FunctionResponse(data: null, status: 500);
            }),
      );
    } catch (e) {
      // Ignored synchronously
    }
  }
}
