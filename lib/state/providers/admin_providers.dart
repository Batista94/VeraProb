import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/features/super_admin/application/quota_warning_service.dart';
import 'package:veraprob/domain/admin/quota_warning.dart';
import 'package:veraprob/application/admin/accept_invitation_handler.dart';
import 'package:veraprob/application/admin/change_user_role_handler.dart';
import 'package:veraprob/application/admin/deactivate_member_handler.dart';
import 'package:veraprob/application/admin/invitation_command_service.dart';
import 'package:veraprob/application/admin/invite_user_handler.dart';
import 'package:veraprob/application/admin/remove_member_handler.dart';
import 'package:veraprob/application/admin/revoke_invitation_handler.dart';
import 'package:veraprob/application/admin/create_execution_handler.dart';
import 'package:veraprob/application/admin/update_org_settings_handler.dart';
import 'package:veraprob/application/admin/update_org_operational_params_handler.dart';
import 'package:veraprob/application/admin/user_management_command_service.dart';
import 'package:veraprob/domain/admin/data_seeding_repository.dart';
import 'package:veraprob/domain/admin/i_active_vehicle_repository.dart';
import 'package:veraprob/domain/admin/invitation.dart';
import 'package:veraprob/domain/admin/invitation_repository.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/admin/organization_repository.dart';
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/infrastructure/admin/admin_providers.dart';
import 'package:veraprob/infrastructure/admin/in_memory_active_vehicle_repository.dart';
import 'package:veraprob/infrastructure/admin/postgres_active_vehicle_repository.dart';
import 'package:veraprob/infrastructure/admin/postgres_invitation_command_service.dart';
import 'package:veraprob/infrastructure/admin/postgres_invitation_query_service.dart';
import 'package:veraprob/infrastructure/admin/postgres_organization_repository.dart';
import 'package:veraprob/infrastructure/admin/postgres_user_management_command_service.dart';
import 'package:veraprob/infrastructure/admin/supabase_admin_notification_repository.dart';
import 'package:veraprob/infrastructure/admin/supabase_data_seeding_repository.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'auth_providers.dart';

// ── Infrastructure Providers ──────────────────────────────────────────────────

final invitationCommandServiceProvider = Provider<InvitationCommandService>((
  ref,
) {
  return PostgresInvitationCommandService(ref.watch(supabaseClientProvider));
});

final invitationQueryServiceProvider = Provider<InvitationRepository>((ref) {
  return PostgresInvitationQueryService(
    ref.watch(supabaseClientProvider),
    ref.watch(dateTimeProviderProvider),
  );
});

final userManagementCommandServiceProvider =
    Provider<UserManagementCommandService>((ref) {
      return PostgresUserManagementCommandService(
        ref.watch(supabaseClientProvider),
      );
    });

// Moved to infrastructure/admin/admin_providers.dart

final organizationRepositoryProvider = Provider<OrganizationRepository>((ref) {
  return PostgresOrganizationRepository(ref.watch(supabaseClientProvider));
});

final activeVehicleRepositoryProvider = Provider<IActiveVehicleRepository>((
  ref,
) {
  final mode = ref.watch(persistenceModeProvider);
  return switch (mode) {
    PersistenceMode.inMemory => const InMemoryActiveVehicleRepository(),
    PersistenceMode.postgres => PostgresActiveVehicleRepository(
      ref.watch(supabaseClientProvider),
    ),
  };
});

final adminNotificationRepositoryProvider =
    Provider<SupabaseAdminNotificationRepository>((ref) {
      return SupabaseAdminNotificationRepository(
        ref.watch(supabaseClientProvider),
      );
    });

final dataSeedingRepositoryProvider = Provider<DataSeedingRepository>((ref) {
  return SupabaseDataSeedingRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(dateTimeProviderProvider),
  );
});

// ── Application Handlers ─────────────────────────────────────────────────────

final inviteUserHandlerProvider = Provider<InviteUserHandler>((ref) {
  return InviteUserHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    commandService: ref.watch(invitationCommandServiceProvider),
    dateTimeProvider: ref.watch(dateTimeProviderProvider),
  );
});

final revokeInvitationHandlerProvider = Provider<RevokeInvitationHandler>((
  ref,
) {
  return RevokeInvitationHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    commandService: ref.watch(invitationCommandServiceProvider),
  );
});

final acceptInvitationHandlerProvider = Provider<AcceptInvitationHandler>((
  ref,
) {
  return AcceptInvitationHandler(ref.watch(invitationCommandServiceProvider));
});

final changeUserRoleHandlerProvider = Provider<ChangeUserRoleHandler>((ref) {
  return ChangeUserRoleHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    commandService: ref.watch(userManagementCommandServiceProvider),
  );
});

final removeMemberHandlerProvider = Provider<RemoveMemberHandler>((ref) {
  return RemoveMemberHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    commandService: ref.watch(userManagementCommandServiceProvider),
    queryService: ref.watch(userManagementQueryServiceProvider),
  );
});

final deactivateMemberHandlerProvider = Provider<DeactivateMemberHandler>((
  ref,
) {
  return DeactivateMemberHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    commandService: ref.watch(userManagementCommandServiceProvider),
    queryService: ref.watch(userManagementQueryServiceProvider),
  );
});

final updateOrgSettingsHandlerProvider = Provider<UpdateOrgSettingsHandler>((
  ref,
) {
  return UpdateOrgSettingsHandler(
    tenantValidator: ref.watch(tenantValidationServiceProvider),
    repository: ref.watch(organizationRepositoryProvider),
    auditLogService: ref.watch(systemAuditLogServiceProvider),
  );
});

final updateOrgOperationalParamsHandlerProvider =
    Provider<UpdateOrgOperationalParamsHandler>((ref) {
      return UpdateOrgOperationalParamsHandler(
        tenantValidator: ref.watch(tenantValidationServiceProvider),
        repository: ref.watch(organizationRepositoryProvider),
        auditLogService: ref.watch(systemAuditLogServiceProvider),
      );
    });

final createExecutionHandlerProvider = Provider<CreateExecutionHandler>((ref) {
  return CreateExecutionHandler(
    client: ref.watch(supabaseClientProvider),
    tenantValidator: ref.watch(tenantValidationServiceProvider),
  );
});

// ── Quota Warning Providers ───────────────────────────────────────────────────

final quotaWarningServiceProvider = Provider<QuotaWarningService>((ref) {
  return QuotaWarningService(ref.watch(supabaseClientProvider));
});

final activeQuotaWarningsProvider =
    FutureProvider.autoDispose<List<QuotaWarning>>((ref) async {
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) return const [];
      return ref.watch(quotaWarningServiceProvider).getActiveWarnings(orgId);
    });

// ── UI Data Providers ────────────────────────────────────────────────────────

final orgMembersProvider = FutureProvider.autoDispose<List<OrgMember>>((
  ref,
) async {
  return ref.watch(userManagementQueryServiceProvider).getMembers();
});

final orgInvitationsProvider = FutureProvider.autoDispose<List<Invitation>>((
  ref,
) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return const [];
  return ref.watch(invitationQueryServiceProvider).listByOrganization(orgId);
});

final orgSettingsProvider = FutureProvider.autoDispose<Organization?>((
  ref,
) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return null;
  return ref.watch(organizationRepositoryProvider).findById(orgId);
});
