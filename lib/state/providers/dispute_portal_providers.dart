import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/dispute_portal/portal_dispute_gateway.dart';
import 'package:veraprob/infrastructure/dispute_portal/supabase_portal_dispute_gateway.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';

/// Anon-side gateway for the external dispute portal. Overridable in tests via
/// `portalDisputeGatewayProvider.overrideWithValue(fake)`.
final portalDisputeGatewayProvider = Provider<PortalDisputeGateway>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SupabasePortalDisputeGateway(client);
});
