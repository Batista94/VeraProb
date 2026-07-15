// Smoke 4 — Regressão de Navegação (Cenário 14.11)
//
// Valida que ContractsScreen roteia corretamente com base em
// selectedContractIdProvider — sem Supabase, roda sempre.
//
// Executar:
//   flutter test test/smoke/navigation_smoke_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:veraprob/application/sla_audit/projections/contract_summary_view.dart';
import 'package:veraprob/features/admin/presentation/screens/contract_detail_screen.dart';
import 'package:veraprob/features/admin/presentation/screens/contracts_screen.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  List<Override> baseOverrides({String? selectedId}) => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    persistenceModeProvider.overrideWithValue(PersistenceMode.inMemory),
    currentOrganizationIdProvider.overrideWith((ref) => 'org-smoke'),
    currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
    contractListProvider.overrideWith((ref) async => <ContractSummaryView>[]),
    if (selectedId != null)
      selectedContractIdProvider.overrideWithBuild(
        (ref, notifier) => selectedId,
      ),
  ];

  group('Smoke 4: Regressão de Navegação (Cenário 14.11)', () {
    testWidgets('4.1 — selectedId=null: exibe lista de contratos', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(),
          child: const MaterialApp(home: Scaffold(body: ContractsScreen())),
        ),
      );
      await tester.pump();

      expect(
        find.text('Gestão de Contratos'),
        findsOneWidget,
        reason: 'Cabeçalho da lista deve aparecer quando selectedId é null',
      );
      expect(
        find.byType(ContractDetailScreen),
        findsNothing,
        reason: 'Tela de detalhe NÃO deve aparecer sem seleção',
      );
    });

    testWidgets(
      '4.2 — selectedId≠null: redireciona imediatamente para ContractDetailScreen',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ProviderScope(
            overrides: baseOverrides(selectedId: 'contract-nav-test'),
            child: const MaterialApp(home: Scaffold(body: ContractsScreen())),
          ),
        );
        await tester.pump(); // primeiro frame: routing síncrono

        expect(
          find.byType(ContractDetailScreen),
          findsOneWidget,
          reason:
              'Cenário 14.11 — ContractDetailScreen deve aparecer imediatamente após seleção',
        );
        expect(
          find.text('Gestão de Contratos'),
          findsNothing,
          reason: 'Lista NÃO deve coexistir com a tela de detalhe',
        );
      },
    );

    testWidgets(
      '4.3 — Transição dinâmica null→ID: ContractDetailScreen exibido após set',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: baseOverrides(),
            child: const MaterialApp(home: Scaffold(body: ContractsScreen())),
          ),
        );
        await tester.pump();

        expect(find.text('Gestão de Contratos'), findsOneWidget);

        // Simula retorno do wizard com o novo contractId
        tester.container().read(selectedContractIdProvider.notifier).state =
            'contract-after-creation';
        await tester.pump();

        expect(
          find.byType(ContractDetailScreen),
          findsOneWidget,
          reason:
              'ContractDetailScreen deve aparecer após definir selectedId via notifier',
        );
      },
    );
  });
}
