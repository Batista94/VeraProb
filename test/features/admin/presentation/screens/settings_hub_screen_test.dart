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
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/access_management_service.dart'
    show TenantPermission, TenantRole;
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/features/admin/presentation/screens/access_management_tab.dart';
import 'package:veraprob/features/admin/presentation/screens/org_settings_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/settings_hub_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/user_management_screen.dart';
import 'package:veraprob/state/providers/access_providers.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// Live, per-test permission set driving [permissionServiceProvider] — flipping
/// its state simulates a mid-session grant/revoke (PermissionsSyncController
/// forcing a refresh) without touching the real authState/Supabase chain.
final _testPerms = StateProvider<Set<String>>((ref) => <String>{});

Widget _wrap(Widget child, {Set<String> perms = const <String>{}}) {
  return ProviderScope(
    overrides: [
      currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
      _testPerms.overrideWith((ref) => perms),
      // Derives from _testPerms so tests can flip `roles:manage` live. Default
      // (empty) → Access tab hidden (3 tabs).
      permissionServiceProvider.overrideWith(
        (ref) => PermissionService(
          permissions: ref.watch(_testPerms),
          scopes: const <String, Set<String>>{},
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
      // Keep the Access tab hermetic when it mounts (revoke case) — no Supabase.
      tenantRolesProvider.overrideWith((ref) async => const <TenantRole>[]),
      permissionDictionaryProvider.overrideWith(
        (ref) async => const <TenantPermission>[],
      ),
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

  testWidgets('grant vivo de roles:manage revela a aba Acessos', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const SettingsHubScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Acessos'), findsNothing);

    // Mid-session grant (refreshSession re-aggregou as permissões).
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsHubScreen)),
    );
    container.read(_testPerms.notifier).state = {'roles:manage'};
    await tester.pumpAndSettle();

    expect(find.text('Acessos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'revoke com a aba Acessos ativa recua para uma aba válida sem exceção',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SettingsHubScreen(initialTab: 'access'),
          perms: const {'roles:manage'},
        ),
      );
      await tester.pumpAndSettle();
      // Começa na aba Acessos (índice 3).
      expect(find.byType(AccessManagementTab), findsOneWidget);

      // Revoke vivo: a aba ativa deixa de existir → clamp do índice.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsHubScreen)),
      );
      container.read(_testPerms.notifier).state = <String>{};
      await tester.pumpAndSettle();

      expect(find.text('Acessos'), findsNothing);
      expect(find.byType(AccessManagementTab), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
