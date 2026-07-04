// settings_hub_screen_test.dart
//
// P4: comportamento do hub consolidado de configurações.
// - Deep link `?tab=` mapeia para a aba certa no primeiro mount.
// - didUpdateWidget: o IndexedStack do shell preserva o State, então um deep
//   link posterior (initialTab novo) PRECISA mover o TabController.
// - Troca manual de aba monta o conteúdo correspondente.
// Goldens ficam em settings_hub_screen_golden_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/features/admin/presentation/screens/org_settings_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/settings_hub_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/user_management_screen.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
      // No roles:manage → Access tab hidden (3 tabs). Also keeps the widget off
      // the real authState/Supabase chain now read in initState / build.
      permissionServiceProvider.overrideWith(
        (ref) => const PermissionService(
          permissions: <String>{},
          scopes: <String, Set<String>>{},
        ),
      ),
      currentOperatorNameProvider.overrideWith((ref) => 'Operador Teste'),
      currentOperatorIdProvider.overrideWith((ref) => 'op-123'),
      orgSettingsProvider.overrideWith(
        (ref) => Organization(
          id: 'org-123',
          name: 'Org Teste',
          legalName: 'Org Teste LTDA',
          cnpj: '12.345.678/0001-90',
          timezone: 'UTC',
          currencyCode: 'BRL',
          status: OrgStatus.active,
          createdAt: DateTime.now().toUtc(),
        ),
      ),
      orgMembersProvider.overrideWith(
        (ref) => [
          OrgMember(
            userId: 'op-123',
            email: 'admin@teste.com',
            role: UserRole.admin,
            invitedAt: DateTime(2026, 1, 1).toUtc(),
          ),
        ],
      ),
      orgInvitationsProvider.overrideWith((ref) => []),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('sem initialTab abre na aba Geral', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsHubScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('CONFIGURAÇÕES DO SISTEMA'), findsOneWidget);
  });

  testWidgets('initialTab users abre na aba Equipe', (tester) async {
    await tester.pumpWidget(
      _wrap(const SettingsHubScreen(initialTab: 'users')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gestão de Equipe'), findsOneWidget);
    expect(find.text('CONFIGURAÇÕES DO SISTEMA'), findsNothing);
  });

  testWidgets('initialTab org abre na aba Organização', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsHubScreen(initialTab: 'org')));
    await tester.pumpAndSettle();

    expect(find.byType(OrgSettingsTab), findsOneWidget);
  });

  testWidgets('deep link posterior move a aba (didUpdateWidget)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const SettingsHubScreen()));
    await tester.pumpAndSettle();
    expect(find.text('CONFIGURAÇÕES DO SISTEMA'), findsOneWidget);

    // Mesmo State (IndexedStack preserva) — só o initialTab muda, como num
    // context.go('/admin/hub/settings?tab=users') com a branch já visitada.
    await tester.pumpWidget(
      _wrap(const SettingsHubScreen(initialTab: 'users')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gestão de Equipe'), findsOneWidget);
  });

  testWidgets('tap na aba Equipe monta a gestão de usuários', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsHubScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Equipe'));
    await tester.pumpAndSettle();

    expect(find.byType(UserManagementTab), findsOneWidget);
    expect(find.text('Convidar'), findsOneWidget);
  });
}
