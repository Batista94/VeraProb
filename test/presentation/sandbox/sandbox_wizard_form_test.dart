import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/presentation/sandbox/providers/sandbox_wizard_provider.dart';
import 'package:veraprob/presentation/sandbox/widgets/wizard/sandbox_wizard_form.dart';

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

      // Still invalid — missing contract + dates
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
}
