import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/admin/accept_invitation_handler.dart';
import '../../application/admin/change_user_role_handler.dart';
import '../../application/admin/invitation_command_service.dart';
import '../../application/admin/invite_user_handler.dart';
import '../../application/admin/remove_member_handler.dart';
import '../../application/admin/revoke_invitation_handler.dart';
import '../../application/admin/update_org_settings_handler.dart';
import '../../application/admin/user_management_command_service.dart';
import '../../domain/admin/data_seeding_repository.dart';
import '../../domain/admin/i_active_vehicle_repository.dart';
import '../../domain/admin/invitation.dart';
import '../../domain/admin/invitation_repository.dart';
import '../../domain/admin/organization.dart';
import '../../domain/admin/organization_repository.dart';
import '../../infrastructure/admin/in_memory_active_vehicle_repository.dart';
import '../../infrastructure/admin/postgres_active_vehicle_repository.dart';
import '../../infrastructure/admin/postgres_invitation_command_service.dart';
import '../../infrastructure/admin/postgres_invitation_query_service.dart';
import '../../infrastructure/admin/postgres_organization_repository.dart';
import '../../infrastructure/admin/postgres_user_management_command_service.dart';
import '../../infrastructure/admin/postgres_user_management_query_service.dart';
import '../../infrastructure/admin/supabase_admin_notification_repository.dart';
import '../../infrastructure/admin/supabase_data_seeding_repository.dart';
import '../../infrastructure/persistence/persistence_mode.dart';
import '../../infrastructure/persistence/persistence_provider.dart';
import '../../infrastructure/providers/supabase_provider.dart';
import 'auth_providers.dart';

// ── Infrastructure Providers ──────────────────────────────────────────────────

final invitationCommandServiceProvider = Provider<InvitationCommandService>((ref) {
  return PostgresInvitationCommandService(ref.watch(supabaseClientProvider));
});

final invitationQueryServiceProvider = Provider<InvitationRepository>((ref) {
  return PostgresInvitationQueryService(ref.watch(supabaseClientProvider));
});

final userManagementCommandServiceProvider =
    Provider<UserManagementCommandService>((ref) {
  return PostgresUserManagementCommandService(ref.watch(supabaseClientProvider));
});

final userManagementQueryServiceProvider =
    Provider<PostgresUserManagementQueryService>((ref) {
  return PostgresUserManagementQueryService(ref.watch(supabaseClientProvider));
});

final organizationRepositoryProvider = Provider<OrganizationRepository>((ref) {
  return PostgresOrganizationRepository(ref.watch(supabaseClientProvider));
});

final activeVehicleRepositoryProvider = Provider<IActiveVehicleRepository>((ref) {
  final mode = ref.watch(persistenceModeProvider);
  return switch (mode) {
    PersistenceMode.inMemory => const InMemoryActiveVehicleRepository(),
    PersistenceMode.postgres =>
      PostgresActiveVehicleRepository(ref.watch(supabaseClientProvider)),
  };
});

final adminNotificationRepositoryProvider =
    Provider<SupabaseAdminNotificationRepository>((ref) {
  return SupabaseAdminNotificationRepository(ref.watch(supabaseClientProvider));
});

final dataSeedingRepositoryProvider = Provider<DataSeedingRepository>((ref) {
  return SupabaseDataSeedingRepository(ref.watch(supabaseClientProvider));
});

// ── Application Handlers ─────────────────────────────────────────────────────

final inviteUserHandlerProvider = Provider<InviteUserHandler>((ref) {
  return InviteUserHandler(ref.watch(invitationCommandServiceProvider));
});

final revokeInvitationHandlerProvider = Provider<RevokeInvitationHandler>((ref) {
  return RevokeInvitationHandler(ref.watch(invitationCommandServiceProvider));
});

final acceptInvitationHandlerProvider = Provider<AcceptInvitationHandler>((ref) {
  return AcceptInvitationHandler(ref.watch(invitationCommandServiceProvider));
});

final changeUserRoleHandlerProvider = Provider<ChangeUserRoleHandler>((ref) {
  return ChangeUserRoleHandler(ref.watch(userManagementCommandServiceProvider));
});

final removeMemberHandlerProvider = Provider<RemoveMemberHandler>((ref) {
  return RemoveMemberHandler(
    commandService: ref.watch(userManagementCommandServiceProvider),
    queryService: ref.watch(userManagementQueryServiceProvider),
  );
});

final updateOrgSettingsHandlerProvider =
    Provider<UpdateOrgSettingsHandler>((ref) {
  return UpdateOrgSettingsHandler(
    repository: ref.watch(organizationRepositoryProvider),
  );
});

// ── UI Data Providers ────────────────────────────────────────────────────────

final orgMembersProvider = FutureProvider.autoDispose<List<OrgMember>>((ref) async {
  return ref.watch(userManagementQueryServiceProvider).getMembers();
});

final orgInvitationsProvider =
    FutureProvider.autoDispose<List<Invitation>>((ref) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return const [];
  return ref.watch(invitationQueryServiceProvider).listByOrganization(orgId);
});

final orgSettingsProvider = FutureProvider.autoDispose<Organization?>((ref) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return null;
  return ref.watch(organizationRepositoryProvider).findById(orgId);
});
