import 'dart:io';
import 'package:veraprob/domain/super_admin/archive_organization_command.dart';
import 'package:veraprob/infrastructure/super_admin/supabase_super_admin_repository.dart';

/// Repository that delegates to SupabaseSuperAdminRepository but allows
/// simulating network/transport exceptions on specific operations.
class FailingSuperAdminRepository extends SupabaseSuperAdminRepository {
  final bool failResend;
  final bool failToggle;
  final bool failArchive;
  final bool failRevoke;

  FailingSuperAdminRepository(
    super.client, {
    this.failResend = false,
    this.failToggle = false,
    this.failArchive = false,
    this.failRevoke = false,
  });

  @override
  Future<void> resendInvitation({
    required String email,
    required String orgName,
    required String orgId,
    required String reason,
  }) async {
    if (failResend) {
      throw const SocketException('Simulated network failure (CT08 test)');
    }
    return super.resendInvitation(
      email: email,
      orgName: orgName,
      orgId: orgId,
      reason: reason,
    );
  }

  @override
  Future<void> toggleTenantMemberStatus({
    required String orgId,
    required String userId,
    required bool isActive,
  }) async {
    if (failToggle) {
      throw const SocketException('Simulated network failure (CT09 test)');
    }
    return super.toggleTenantMemberStatus(
      orgId: orgId,
      userId: userId,
      isActive: isActive,
    );
  }

  @override
  Future<void> archiveOrganization(ArchiveOrganizationCommand command) async {
    if (failArchive) {
      throw const SocketException('Simulated network failure (CT12 test)');
    }
    return super.archiveOrganization(command);
  }

  @override
  Future<void> revokeInvitation({
    required String orgId,
    required String email,
    required String superAdminUserId,
    required String reason,
  }) async {
    if (failRevoke) {
      throw const SocketException('Simulated network failure (CT09 test)');
    }
    return super.revokeInvitation(
      orgId: orgId,
      email: email,
      superAdminUserId: superAdminUserId,
      reason: reason,
    );
  }
}
