import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/infrastructure/admin/postgres_user_management_query_service.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';

/// Provider for organization member query service.
///
/// Decoupling: Infrastructure-layer provider returning application-layer interface.
final userManagementQueryServiceProvider = Provider<UserManagementQueryService>(
  (ref) {
    return PostgresUserManagementQueryService(
      ref.watch(supabaseClientProvider),
    );
  },
);
