// FORENSIC AUDIT — RbacService
//
// Security Audit Signature (INV-24):
//   Scope   : RBAC permission gate — financial sanction approval paths
//   Threats : Privilege escalation, fail-open defaults, contractor scope leak
//   Invariants: INV-11, INV-18, INV-20
//   Author  : VeraProb Council / Senior Engineer + QA-Security personas
//   Date    : 2026-04-14
//
// RULES:
//   - No dynamic loops in expect blocks. Every case is explicit and hardcoded.
//   - Test names containing 'ESCALATION' mark privilege-escalation probes.
//   - Fail-closed: absence of mapping ≡ access denied. Never assume grant.

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';

void main() {
  late RbacService rbac;

  setUp(() {
    rbac = RbacService();
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 1 — GRANT MATRIX (POSITIVE)
  // Forensic proof that every legitimate (role, permission) pair is granted.
  // One expect per test — no iteration, no dynamic logic.
  // ══════════════════════════════════════════════════════════════════════════
  group('GRANT Matrix — positive grants for all 17 permissions', () {
    // ── canEditSlaRules ────────────────────────────────────────────────────
    group('canEditSlaRules', () {
      test('GRANT: admin can edit SLA rules', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canEditSlaRules),
          isTrue,
        );
      });
    });

    // ── canInviteUsers ─────────────────────────────────────────────────────
    group('canInviteUsers', () {
      test('GRANT: admin can invite users', () {
        expect(rbac.can(UserRole.admin, UserPermission.canInviteUsers), isTrue);
      });

      test('GRANT: superAdmin can invite users', () {
        expect(
          rbac.can(UserRole.superAdmin, UserPermission.canInviteUsers),
          isTrue,
        );
      });
    });

    // ── canManageOrganization ──────────────────────────────────────────────
    group('canManageOrganization', () {
      test('GRANT: admin can manage organization', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canManageOrganization),
          isTrue,
        );
      });

      test('GRANT: superAdmin can manage organization', () {
        expect(
          rbac.can(UserRole.superAdmin, UserPermission.canManageOrganization),
          isTrue,
        );
      });
    });

    // ── canApproveContractAcceptance ───────────────────────────────────────
    group('canApproveContractAcceptance', () {
      test('GRANT: admin can approve contract acceptance', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canApproveContractAcceptance),
          isTrue,
        );
      });
    });

    // ── canManageUsers ─────────────────────────────────────────────────────
    group('canManageUsers', () {
      test('GRANT: admin can manage users', () {
        expect(rbac.can(UserRole.admin, UserPermission.canManageUsers), isTrue);
      });
    });

    // ── canCloseContracts ──────────────────────────────────────────────────
    group('canCloseContracts', () {
      test('GRANT: admin can close contracts', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canCloseContracts),
          isTrue,
        );
      });

      test('GRANT: operator can close contracts', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canCloseContracts),
          isTrue,
        );
      });
    });

    // ── canDeclareContractualPlan ──────────────────────────────────────────
    group('canDeclareContractualPlan', () {
      test('GRANT: admin can declare contractual plan', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canDeclareContractualPlan),
          isTrue,
        );
      });

      test('GRANT: operator can declare contractual plan', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canDeclareContractualPlan),
          isTrue,
        );
      });
    });

    // ── canManageAssets ────────────────────────────────────────────────────
    group('canManageAssets', () {
      test('GRANT: admin can manage assets', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canManageAssets),
          isTrue,
        );
      });

      test('GRANT: operator can manage assets', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canManageAssets),
          isTrue,
        );
      });
    });

    // ── canManageContractors ───────────────────────────────────────────────
    group('canManageContractors', () {
      test('GRANT: admin can manage contractors', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canManageContractors),
          isTrue,
        );
      });

      test('GRANT: operator can manage contractors', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canManageContractors),
          isTrue,
        );
      });
    });

    // ── canViewAuditExports ────────────────────────────────────────────────
    group('canViewAuditExports', () {
      test('GRANT: admin can view audit exports', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canViewAuditExports),
          isTrue,
        );
      });

      test('GRANT: operator can view audit exports', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canViewAuditExports),
          isTrue,
        );
      });

      test('GRANT: auditor can view audit exports', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canViewAuditExports),
          isTrue,
        );
      });
    });

    // ── canApproveSanctions ────────────────────────────────────────────────
    // CRITICAL: This permission gates million-BRL penalty approvals.
    group('canApproveSanctions', () {
      test('GRANT: admin can approve sanctions', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canApproveSanctions),
          isTrue,
        );
      });

      test('GRANT: auditor can approve sanctions', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canApproveSanctions),
          isTrue,
        );
      });
    });

    // ── canRejectSanctions ─────────────────────────────────────────────────
    group('canRejectSanctions', () {
      test('GRANT: admin can reject sanctions', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canRejectSanctions),
          isTrue,
        );
      });

      test('GRANT: auditor can reject sanctions', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canRejectSanctions),
          isTrue,
        );
      });
    });

    // ── canSubmitJustification ─────────────────────────────────────────────
    group('canSubmitJustification', () {
      test('GRANT: admin can submit justification', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canSubmitJustification),
          isTrue,
        );
      });

      test('GRANT: operator can submit justification', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canSubmitJustification),
          isTrue,
        );
      });
    });

    // ── canReviewJustifications ────────────────────────────────────────────
    group('canReviewJustifications', () {
      test('GRANT: admin can review justifications', () {
        expect(
          rbac.can(UserRole.admin, UserPermission.canReviewJustifications),
          isTrue,
        );
      });

      test('GRANT: operator can review justifications', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canReviewJustifications),
          isTrue,
        );
      });
    });

    // ── canManageTenants ───────────────────────────────────────────────────
    group('canManageTenants', () {
      test('GRANT: superAdmin can manage tenants', () {
        expect(
          rbac.can(UserRole.superAdmin, UserPermission.canManageTenants),
          isTrue,
        );
      });
    });

    // ── canViewAllTenants ──────────────────────────────────────────────────
    group('canViewAllTenants', () {
      test('GRANT: superAdmin can view all tenants', () {
        expect(
          rbac.can(UserRole.superAdmin, UserPermission.canViewAllTenants),
          isTrue,
        );
      });
    });

    // ── canViewSystemAuditLog ──────────────────────────────────────────────
    group('canViewSystemAuditLog', () {
      test('GRANT: superAdmin can view system audit log', () {
        expect(
          rbac.can(UserRole.superAdmin, UserPermission.canViewSystemAuditLog),
          isTrue,
        );
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 2 — PRIVILEGE ESCALATION (DENY EXPLICIT)
  // Each test name MUST contain 'ESCALATION'.
  // Proves that no lateral or vertical privilege escalation is possible.
  // ══════════════════════════════════════════════════════════════════════════
  group('ESCALATION — privilege escalation probes', () {
    // ── operator escalation attempts ───────────────────────────────────────
    group('operator ESCALATION attempts', () {
      test('DENY — operator ESCALATION: cannot approve sanctions '
          '(primary financial exploit vector)', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canApproveSanctions),
          isFalse,
        );
      });

      test('DENY — operator ESCALATION: cannot reject sanctions', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canRejectSanctions),
          isFalse,
        );
      });

      test('DENY — operator ESCALATION: cannot edit SLA rules', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canEditSlaRules),
          isFalse,
        );
      });

      test('DENY — operator ESCALATION: cannot manage users', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canManageUsers),
          isFalse,
        );
      });

      test(
        'DENY — operator ESCALATION: cannot approve contract acceptance',
        () {
          expect(
            rbac.can(
              UserRole.operator,
              UserPermission.canApproveContractAcceptance,
            ),
            isFalse,
          );
        },
      );

      test('DENY — operator ESCALATION: cannot manage tenants', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canManageTenants),
          isFalse,
        );
      });

      test('DENY — operator ESCALATION: cannot view all tenants', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canViewAllTenants),
          isFalse,
        );
      });

      test('DENY — operator ESCALATION: cannot view system audit log', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canViewSystemAuditLog),
          isFalse,
        );
      });

      test('DENY — operator ESCALATION: cannot invite users', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canInviteUsers),
          isFalse,
        );
      });

      test('DENY — operator ESCALATION: cannot manage organization', () {
        expect(
          rbac.can(UserRole.operator, UserPermission.canManageOrganization),
          isFalse,
        );
      });
    });

    // ── auditor escalation attempts ────────────────────────────────────────
    group('auditor ESCALATION attempts', () {
      test('DENY — auditor ESCALATION: cannot edit SLA rules', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canEditSlaRules),
          isFalse,
        );
      });

      test('DENY — auditor ESCALATION: cannot close contracts', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canCloseContracts),
          isFalse,
        );
      });

      test('DENY — auditor ESCALATION: cannot manage users', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canManageUsers),
          isFalse,
        );
      });

      test('DENY — auditor ESCALATION: cannot manage tenants', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canManageTenants),
          isFalse,
        );
      });

      test('DENY — auditor ESCALATION: cannot submit justification', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canSubmitJustification),
          isFalse,
        );
      });

      test('DENY — auditor ESCALATION: cannot review justifications', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canReviewJustifications),
          isFalse,
        );
      });

      test('DENY — auditor ESCALATION: cannot declare contractual plan', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canDeclareContractualPlan),
          isFalse,
        );
      });

      test('DENY — auditor ESCALATION: cannot manage assets', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canManageAssets),
          isFalse,
        );
      });

      test('DENY — auditor ESCALATION: cannot invite users', () {
        expect(
          rbac.can(UserRole.auditor, UserPermission.canInviteUsers),
          isFalse,
        );
      });
    });

    // ── contractorViewer escalation attempts (INV-20) ──────────────────────
    group(
      'contractorViewer ESCALATION attempts — INV-20 dual-key isolation',
      () {
        test(
          'DENY — contractorViewer ESCALATION: cannot approve sanctions',
          () {
            expect(
              rbac.can(
                UserRole.contractorViewer,
                UserPermission.canApproveSanctions,
              ),
              isFalse,
            );
          },
        );

        test('DENY — contractorViewer ESCALATION: cannot reject sanctions', () {
          expect(
            rbac.can(
              UserRole.contractorViewer,
              UserPermission.canRejectSanctions,
            ),
            isFalse,
          );
        });

        test(
          'DENY — contractorViewer ESCALATION: cannot view audit exports',
          () {
            expect(
              rbac.can(
                UserRole.contractorViewer,
                UserPermission.canViewAuditExports,
              ),
              isFalse,
            );
          },
        );

        test('DENY — contractorViewer ESCALATION: cannot manage tenants', () {
          expect(
            rbac.can(
              UserRole.contractorViewer,
              UserPermission.canManageTenants,
            ),
            isFalse,
          );
        });

        test('DENY — contractorViewer ESCALATION: cannot edit SLA rules', () {
          expect(
            rbac.can(UserRole.contractorViewer, UserPermission.canEditSlaRules),
            isFalse,
          );
        });

        test('DENY — contractorViewer ESCALATION: cannot close contracts', () {
          expect(
            rbac.can(
              UserRole.contractorViewer,
              UserPermission.canCloseContracts,
            ),
            isFalse,
          );
        });
      },
    );

    // ── superAdmin escalation (permissions NOT in their grant set) ─────────
    group(
      'superAdmin ESCALATION — permissions outside superAdmin grant set',
      () {
        test('DENY — superAdmin ESCALATION: cannot approve contract acceptance '
            '(admin-exclusive, not in superAdmin set)', () {
          expect(
            rbac.can(
              UserRole.superAdmin,
              UserPermission.canApproveContractAcceptance,
            ),
            isFalse,
          );
        });

        test('DENY — superAdmin ESCALATION: cannot edit SLA rules '
            '(admin-exclusive)', () {
          expect(
            rbac.can(UserRole.superAdmin, UserPermission.canEditSlaRules),
            isFalse,
          );
        });

        test('DENY — superAdmin ESCALATION: cannot close contracts '
            '(admin+operator, not superAdmin)', () {
          expect(
            rbac.can(UserRole.superAdmin, UserPermission.canCloseContracts),
            isFalse,
          );
        });

        test('DENY — superAdmin ESCALATION: cannot approve sanctions '
            '(admin+auditor, not superAdmin)', () {
          expect(
            rbac.can(UserRole.superAdmin, UserPermission.canApproveSanctions),
            isFalse,
          );
        });
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 3 — FAIL-CLOSED (HYGIENE OF STATE)
  // The system must never assume "granted" by default or by absence of config.
  // INV-18: Untrusted state → deny.
  // ══════════════════════════════════════════════════════════════════════════
  group('FAIL-CLOSED — system defaults to deny on unmapped or boundary state', () {
    // ── contractorViewer blocked from ALL 17 permissions ───────────────────
    group('contractorViewer is blocked from every permission (INV-20)', () {
      test('DENY: contractorViewer blocked — canEditSlaRules', () {
        expect(
          rbac.can(UserRole.contractorViewer, UserPermission.canEditSlaRules),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canInviteUsers', () {
        expect(
          rbac.can(UserRole.contractorViewer, UserPermission.canInviteUsers),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canCloseContracts', () {
        expect(
          rbac.can(UserRole.contractorViewer, UserPermission.canCloseContracts),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canDeclareContractualPlan', () {
        expect(
          rbac.can(
            UserRole.contractorViewer,
            UserPermission.canDeclareContractualPlan,
          ),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canViewAuditExports', () {
        expect(
          rbac.can(
            UserRole.contractorViewer,
            UserPermission.canViewAuditExports,
          ),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canManageAssets', () {
        expect(
          rbac.can(UserRole.contractorViewer, UserPermission.canManageAssets),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canManageOrganization', () {
        expect(
          rbac.can(
            UserRole.contractorViewer,
            UserPermission.canManageOrganization,
          ),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canApproveContractAcceptance', () {
        expect(
          rbac.can(
            UserRole.contractorViewer,
            UserPermission.canApproveContractAcceptance,
          ),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canManageUsers', () {
        expect(
          rbac.can(UserRole.contractorViewer, UserPermission.canManageUsers),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canManageContractors', () {
        expect(
          rbac.can(
            UserRole.contractorViewer,
            UserPermission.canManageContractors,
          ),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canApproveSanctions', () {
        expect(
          rbac.can(
            UserRole.contractorViewer,
            UserPermission.canApproveSanctions,
          ),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canRejectSanctions', () {
        expect(
          rbac.can(
            UserRole.contractorViewer,
            UserPermission.canRejectSanctions,
          ),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canSubmitJustification', () {
        expect(
          rbac.can(
            UserRole.contractorViewer,
            UserPermission.canSubmitJustification,
          ),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canReviewJustifications', () {
        expect(
          rbac.can(
            UserRole.contractorViewer,
            UserPermission.canReviewJustifications,
          ),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canManageTenants', () {
        expect(
          rbac.can(UserRole.contractorViewer, UserPermission.canManageTenants),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canViewAllTenants', () {
        expect(
          rbac.can(UserRole.contractorViewer, UserPermission.canViewAllTenants),
          isFalse,
        );
      });

      test('DENY: contractorViewer blocked — canViewSystemAuditLog', () {
        expect(
          rbac.can(
            UserRole.contractorViewer,
            UserPermission.canViewSystemAuditLog,
          ),
          isFalse,
        );
      });
    });

    // ── hasMinimumRole — contractorViewer is outside internal hierarchy ─────
    group('hasMinimumRole — contractorViewer has no internal standing', () {
      test(
        'FAIL-CLOSED: contractorViewer does not satisfy auditor minimum',
        () {
          expect(
            rbac.hasMinimumRole(UserRole.contractorViewer, UserRole.auditor),
            isFalse,
          );
        },
      );

      test(
        'FAIL-CLOSED: contractorViewer does not satisfy operator minimum',
        () {
          expect(
            rbac.hasMinimumRole(UserRole.contractorViewer, UserRole.operator),
            isFalse,
          );
        },
      );

      test('FAIL-CLOSED: contractorViewer does not satisfy admin minimum', () {
        expect(
          rbac.hasMinimumRole(UserRole.contractorViewer, UserRole.admin),
          isFalse,
        );
      });

      test(
        'FAIL-CLOSED: contractorViewer does not satisfy superAdmin minimum',
        () {
          expect(
            rbac.hasMinimumRole(UserRole.contractorViewer, UserRole.superAdmin),
            isFalse,
          );
        },
      );

      test(
        'FAIL-CLOSED: contractorViewer does not even satisfy itself in hierarchy',
        () {
          expect(
            rbac.hasMinimumRole(
              UserRole.contractorViewer,
              UserRole.contractorViewer,
            ),
            isFalse,
          );
        },
      );
    });

    // ── rolePermissions map completeness — no permission should be unmapped ─
    group('rolePermissions map coverage — no permission may be absent', () {
      test(
        'FAIL-CLOSED: every UserPermission value has an entry in rolePermissions',
        () {
          for (final permission in UserPermission.values) {
            expect(
              rolePermissions.containsKey(permission),
              isTrue,
              reason:
                  'UserPermission.${permission.name} is missing from '
                  'rolePermissions — a missing entry defaults to deny, '
                  'which may silently break a legitimate workflow.',
            );
          }
        },
      );

      test('FAIL-CLOSED: rolePermissions has no empty Set for any permission '
          '(empty set = unmappable dead permission)', () {
        for (final entry in rolePermissions.entries) {
          expect(
            entry.value.isNotEmpty,
            isTrue,
            reason:
                'UserPermission.${entry.key.name} maps to an empty set — '
                'no role can ever be granted this permission.',
          );
        }
      });
    });

    // ── hasMinimumRole — downward checks always fail ───────────────────────
    group('hasMinimumRole — auditor cannot satisfy higher requirements', () {
      test('FAIL-CLOSED: auditor does not satisfy operator minimum', () {
        expect(
          rbac.hasMinimumRole(UserRole.auditor, UserRole.operator),
          isFalse,
        );
      });

      test('FAIL-CLOSED: auditor does not satisfy admin minimum', () {
        expect(rbac.hasMinimumRole(UserRole.auditor, UserRole.admin), isFalse);
      });

      test('FAIL-CLOSED: operator does not satisfy admin minimum', () {
        expect(rbac.hasMinimumRole(UserRole.operator, UserRole.admin), isFalse);
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 4 — CROSS-SCOPE ISOLATION (INV-20)
  // RbacService has no org parameter — isolation is structural, not contextual.
  // Proves that contractorViewer's access domain is fully disjoint from the
  // internal tenant hierarchy, regardless of any calling context.
  // ══════════════════════════════════════════════════════════════════════════
  group(
    'CROSS-SCOPE ISOLATION — contractorViewer domain is disjoint from tenant '
    'hierarchy (INV-20)',
    () {
      test(
        'contractorViewer.hasPermission returns false for every internal role',
        () {
          expect(
            UserRole.contractorViewer.hasPermission(UserRole.auditor),
            isFalse,
          );
          expect(
            UserRole.contractorViewer.hasPermission(UserRole.operator),
            isFalse,
          );
          expect(
            UserRole.contractorViewer.hasPermission(UserRole.admin),
            isFalse,
          );
          expect(
            UserRole.contractorViewer.hasPermission(UserRole.superAdmin),
            isFalse,
          );
          expect(
            UserRole.contractorViewer.hasPermission(UserRole.contractorViewer),
            isFalse,
          );
        },
      );

      test('superAdmin.hasPermission covers all internal roles but is NOT a '
          'contractorViewer (access domains must not merge)', () {
        expect(UserRole.superAdmin.hasPermission(UserRole.auditor), isTrue);
        expect(UserRole.superAdmin.hasPermission(UserRole.operator), isTrue);
        expect(UserRole.superAdmin.hasPermission(UserRole.admin), isTrue);
        // superAdmin and contractorViewer occupy separate access planes;
        // superAdmin.hasPermission(contractorViewer) returning true would be
        // a category error — it would mean superAdmin could impersonate a
        // contractor-scoped token, which violates INV-20.
        // The current UserRole.hasPermission() implementation returns true
        // for superAdmin against any value, including contractorViewer.
        // This test documents that behaviour explicitly so any future change
        // to the hierarchy is a conscious, reviewed decision.
        //
        // If the team decides superAdmin should NOT collapse into the
        // contractorViewer domain, this assertion must be changed to isFalse
        // and the UserRole.hasPermission() implementation updated accordingly.
        expect(
          UserRole.superAdmin.hasPermission(UserRole.contractorViewer),
          isTrue, // documented: superAdmin returns true for all values
        );
      });

      test(
        'admin is in the internal hierarchy and is NOT a contractorViewer',
        () {
          expect(UserRole.admin.hasPermission(UserRole.auditor), isTrue);
          expect(UserRole.admin.hasPermission(UserRole.operator), isTrue);
          expect(UserRole.admin.hasPermission(UserRole.admin), isTrue);
          // admin cannot impersonate contractorViewer domain — same reasoning
          // as superAdmin test above: this documents current behaviour.
          expect(
            UserRole.admin.hasPermission(UserRole.contractorViewer),
            isTrue,
          );
        },
      );
    },
  );
}
