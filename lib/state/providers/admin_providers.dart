import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/supabase_client.dart';
import '../../domain/admin/organization.dart';
import '../../domain/admin/organization_repository.dart';
import '../../infrastructure/admin/postgres_organization_repository.dart';
import '../../infrastructure/admin/postgres_user_management_command_service.dart';
import '../../infrastructure/admin/postgres_user_management_query_service.dart';
import '../../application/admin/user_management_command_service.dart';
import '../../application/admin/update_org_settings_handler.dart';
import '../../application/admin/change_user_role_handler.dart';
import '../../application/admin/remove_member_handler.dart';
import 'auth_providers.dart';

/// Provider for the organization repository implementation.
final organizationRepositoryProvider = Provider<OrganizationRepository>((ref) {
  return PostgresOrganizationRepository(supabase);
});

/// Future provider for current organization settings.
final orgSettingsProvider = FutureProvider<Organization?>((ref) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return null;
  return ref.watch(organizationRepositoryProvider).findById(orgId);
});

/// Provider for the update organization settings handler.
final updateOrgSettingsHandlerProvider = Provider<UpdateOrgSettingsHandler>((ref) {
  return UpdateOrgSettingsHandler(
    repository: ref.watch(organizationRepositoryProvider),
  );
});

/// Provider for the user management query service (members list).
final userManagementQueryServiceProvider = Provider<PostgresUserManagementQueryService>((ref) {
  return PostgresUserManagementQueryService(supabase);
});

/// Provider for the user management command service (RPCS).
final userManagementCommandServiceProvider = Provider<UserManagementCommandService>((ref) {
  return PostgresUserManagementCommandService(supabase);
});

/// Future provider for organization members.
final orgMembersProvider = FutureProvider<List<OrgMember>>((ref) async {
  // Ensure we react to auth changes
  ref.watch(authStateProvider);
  return ref.watch(userManagementQueryServiceProvider).getMembers();
});

/// Provider for the change user role handler.
final changeUserRoleHandlerProvider = Provider<ChangeUserRoleHandler>((ref) {
  return ChangeUserRoleHandler(ref.watch(userManagementCommandServiceProvider));
});

/// Provider for the remove member handler.
final removeMemberHandlerProvider = Provider<RemoveMemberHandler>((ref) {
  return RemoveMemberHandler(
    commandService: ref.watch(userManagementCommandServiceProvider),
    queryService: ref.watch(userManagementQueryServiceProvider),
  );
});
