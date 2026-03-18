import 'user_role.dart';

/// Granular permissions for the PactaFlow operational environment.
enum UserPermission {
  canEditSlaRules,
  canInviteUsers,
  canCloseContracts,
  canDeclareContractualPlan,
  canViewAuditExports,
  canManageAssets,
  canManageOrganization,
  canApproveContractAcceptance,
  canManageUsers,
  canManageContractors,
}

/// Centralized RBAC mapping.
const Map<UserPermission, Set<UserRole>> rolePermissions = {
  UserPermission.canEditSlaRules: {UserRole.admin},
  UserPermission.canInviteUsers: {UserRole.admin},
  UserPermission.canManageOrganization: {UserRole.admin},
  UserPermission.canApproveContractAcceptance: {UserRole.admin},
  UserPermission.canManageUsers: {UserRole.admin},

  UserPermission.canCloseContracts: {UserRole.admin, UserRole.operator},
  UserPermission.canDeclareContractualPlan: {UserRole.admin, UserRole.operator},
  UserPermission.canManageAssets: {UserRole.admin, UserRole.operator},
  UserPermission.canManageContractors: {UserRole.admin, UserRole.operator},

  UserPermission.canViewAuditExports: {
    UserRole.admin,
    UserRole.operator,
    UserRole.auditor,
  },
};
