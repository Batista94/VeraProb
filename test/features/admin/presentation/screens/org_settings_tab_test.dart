import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/screens/org_settings_screen.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/admin/organization.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/admin_providers.dart';

void main() {
  group('OrgSettingsTab (INV-9/INV-19)', () {
    late Organization mockOrg;

    setUp(() {
      mockOrg = Organization(
        id: 'org-123',
        name: 'Operation Hydra',
        legalName: 'Hydra B2B Solutions',
        cnpj: '12.345.678/0001-90',
        timezone: 'UTC',
        currencyCode: 'USD',
        status: OrgStatus.active,
        createdAt: DateTime.now().toUtc(),
      );
    });

    testWidgets('Super Admin can edit all fields', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => UserRole.superAdmin),
            orgSettingsProvider.overrideWith((ref) => mockOrg),
          ],
          child: const MaterialApp(home: Scaffold(body: OrgSettingsTab())),
        ),
      );

      await tester.pump(); // Handle AsyncValue loading -> data

      await tester.pumpAndSettle();

      // find.widgetWithText doesn't work for labels, but find.text + ancestor does
      final nameField = tester.widget<TextField>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Nome da Organização'),
            matching: find.byType(TextFormField),
          ),
          matching: find.byType(TextField),
        ),
      );
      expect(
        nameField.readOnly,
        isFalse,
        reason: 'Super Admin should be able to edit Name',
      );
    });

    testWidgets('Tenant Admin CANNOT edit critical SLA fields (INV-19)', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
            orgSettingsProvider.overrideWith((ref) => mockOrg),
          ],
          child: const MaterialApp(home: Scaffold(body: OrgSettingsTab())),
        ),
      );

      await tester.pump();

      await tester.pumpAndSettle();

      final nameField = tester.widget<TextField>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Nome da Organização'),
            matching: find.byType(TextFormField),
          ),
          matching: find.byType(TextField),
        ),
      );
      expect(
        nameField.readOnly,
        isTrue,
        reason: 'Tenant Admin should NOT be able to edit Name',
      );

      final timezoneField = tester.widget<TextField>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Fuso Horário'),
            matching: find.byType(TextFormField),
          ),
          matching: find.byType(TextField),
        ),
      );
      expect(
        timezoneField.readOnly,
        isTrue,
        reason: 'Tenant Admin should NOT be able to edit Timezone',
      );
    });
  });
}
