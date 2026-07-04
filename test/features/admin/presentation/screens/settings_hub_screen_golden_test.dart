import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/screens/settings_hub_screen.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/application/shared/app_types.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      currentUserRoleProvider.overrideWith((ref) => UserRole.superAdmin),
      // Empty perms → Access tab stays hidden; also keeps the golden off the
      // real authState/Supabase chain (permissionServiceProvider is read in
      // SettingsHubScreen.initState).
      permissionServiceProvider.overrideWith(
        (ref) => const PermissionService(
          permissions: <String>{},
          scopes: <String, Set<String>>{},
        ),
      ),
      currentOperatorNameProvider.overrideWith((ref) => 'Steve Rogers'),
      currentOperatorIdProvider.overrideWith((ref) => 'op-123'),
      orgSettingsProvider.overrideWith(
        (ref) => Organization(
          id: 'org-123',
          name: 'Operation Hydra',
          legalName: 'Hydra B2B Solutions',
          cnpj: '12.345.678/0001-90',
          timezone: 'UTC',
          currencyCode: 'USD',
          status: OrgStatus.active,
          createdAt: DateTime.now().toUtc(),
        ),
      ),
      orgMembersProvider.overrideWith(
        (ref) => [
          OrgMember(
            userId: 'user-1',
            email: 'admin@hydra.com',
            role: UserRole.admin,
            invitedAt: DateTime(2026, 1, 1).toUtc(),
          ),
        ],
      ),
      orgInvitationsProvider.overrideWith((ref) => []),
    ],
    child: MaterialApp(debugShowCheckedModeBanner: false, home: child),
  );
}

void main() {
  group('SettingsHubScreen Goldens (GOLDEN-UNWIRED)', () {
    goldenTest(
      'golden test — settings hub general tab (desktop)',
      fileName: 'settings_hub_general_tab',
      builder: () => SizedBox(
        width: 1024,
        height: 768,
        child: _wrap(const SettingsHubScreen()),
      ),
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );

    goldenTest(
      'golden test — settings hub org tab (desktop)',
      fileName: 'settings_hub_org_tab',
      builder: () => SizedBox(
        width: 1024,
        height: 768,
        child: _wrap(const SettingsHubScreen(initialTab: 'org')),
      ),
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
    );
  });
}
