// pr_scanner: ignore-regression
//
import 'user_role.dart';

/// Granular permissions for the veraprob operational environment.
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

  // Sanction review permissions (admin + auditor)
  canApproveSanctions,
  canRejectSanctions,

  // Justification permissions (Phase 9.8.J)
  canSubmitJustification,
  canReviewJustifications,

  // SuperAdmin-exclusive permissions
  canManageTenants,
  canViewAllTenants,
  canViewSystemAuditLog,
  canImpersonateTenant,
}

/// Centralized RBAC mapping.
const Map<UserPermission, Set<UserRole>> rolePermissions = {
  UserPermission.canEditSlaRules: {UserRole.admin},
  UserPermission.canInviteUsers: {UserRole.admin, UserRole.superAdmin},
  UserPermission.canManageOrganization: {UserRole.admin, UserRole.superAdmin},
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

  UserPermission.canApproveSanctions: {UserRole.admin, UserRole.auditor},
  UserPermission.canRejectSanctions: {UserRole.admin, UserRole.auditor},

  // Justification permissions (Phase 9.8.J)
  UserPermission.canSubmitJustification: {UserRole.admin, UserRole.operator},
  UserPermission.canReviewJustifications: {UserRole.admin, UserRole.operator},

  // SuperAdmin-exclusive
  UserPermission.canManageTenants: {UserRole.superAdmin},
  UserPermission.canViewAllTenants: {UserRole.superAdmin},
  UserPermission.canViewSystemAuditLog: {UserRole.superAdmin},
  UserPermission.canImpersonateTenant: {UserRole.superAdmin},
};
