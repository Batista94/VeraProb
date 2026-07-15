import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/services/permission_service.dart';
import 'package:veraprob/presentation/sandbox/providers/sandbox_wizard_provider.dart';
import 'package:veraprob/presentation/sandbox/widgets/wizard/sandbox_wizard_form.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sandbox_providers.dart';

void main() {
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  group('SandboxWizardForm — execute gate', () {
    testWidgets('Executar Simulação is disabled until form is valid', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SandboxWizardForm(
            contracts: [SandboxContractOption(id: 'ct-1', label: 'CT-0042')],
          ),
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      await tester.enterText(
        find.byType(TextField).first,
        'Teste Tolerância 15min',
      );
      await tester.pump();

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('notifier converts masked cap to cents before overrides', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: ThemeData.dark(),
                home: const Scaffold(
                  body: SingleChildScrollView(
                    child: SandboxWizardForm(
                      contracts: [
                        SandboxContractOption(id: 'ct-1', label: 'CT-0042'),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      container.read(sandboxWizardProvider.notifier)
        ..setSessionLabel('Cap')
        ..setContractId('ct-1')
        ..setPeriod(
          startUtc: DateTime.utc(2026, 1, 1),
          endUtc: DateTime.utc(2026, 2, 1),
        )
        ..setMonthlyPenaltyCapFromMasked('R\$ 5.000,00');

      final overrides = container.read(sandboxWizardProvider).buildOverrides();
      expect(overrides.financialOverrides?.monthlyPenaltyCapCents, 500000);
      expect(overrides.financialOverrides?.monthlyPenaltyCapCents, isA<int>());
    });
  });

  group('SandboxWizardForm — lockedContractId', () {
    testWidgets('hides dropdown when contract is locked', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SandboxWizardForm(
            contracts: [SandboxContractOption(id: 'ct-1', label: 'CT-0042')],
            lockedContractId: 'ct-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('CT-0042'), findsOneWidget);
    });

    testWidgets(
      'tampered contractId shows snackbar and does not start simulation',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentUserRoleProvider.overrideWithValue(UserRole.admin),
              permissionServiceProvider.overrideWithValue(
                const PermissionService(permissions: {'*'}, scopes: {}),
              ),
              currentOrganizationIdProvider.overrideWithValue('org-1'),
              currentSessionIdProvider.overrideWithValue('sess-1'),
            ],
            child: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return MaterialApp(
                  theme: ThemeData.dark(),
                  home: const Scaffold(
                    body: SingleChildScrollView(
                      child: SandboxWizardForm(
                        contracts: [
                          SandboxContractOption(id: 'ct-1', label: 'CT-0042'),
                        ],
                        lockedContractId: 'ct-1',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        container.read(sandboxWizardProvider.notifier)
          ..setSessionLabel('Tamper test')
          ..setContractId('ct-1')
          ..setPeriod(
            startUtc: DateTime.utc(2026, 1, 1),
            endUtc: DateTime.utc(2026, 2, 1),
          );
        container.read(sandboxWizardProvider.notifier).setContractId('evil-id');
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Executar Simulação'));
        await tester.tap(find.text('Executar Simulação'));
        await tester.pumpAndSettle();

        expect(
          container.read(sandboxSimulationControllerProvider),
          const AsyncData<String?>(null),
        );
        expect(
          find.text(
            'Contrato inválido para esta simulação. Recarregue a página.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
