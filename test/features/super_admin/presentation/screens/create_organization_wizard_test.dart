import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/i_cnpj_lookup_service.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/features/super_admin/presentation/screens/create_organization_wizard.dart';
import 'package:veraprob/infrastructure/providers/super_admin_providers.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';
import 'package:veraprob/application/super_admin/create_organization_handler.dart';
import 'package:veraprob/application/super_admin/create_organization_result.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

class MockSuperAdminRepository extends Mock implements ISuperAdminRepository {}

class MockCnpjLookupService extends Mock implements ICnpjLookupService {}

class MockCreateOrganizationHandler extends Mock
    implements CreateOrganizationHandler {}

class FakeCreateOrganizationCommand extends Fake
    implements CreateOrganizationCommand {}

void main() {
  late MockSuperAdminRepository mockRepo;
  late MockCnpjLookupService mockLookup;
  late MockCreateOrganizationHandler mockHandler;

  setUpAll(() {
    registerFallbackValue(FakeCreateOrganizationCommand());
  });

  setUp(() {
    mockRepo = MockSuperAdminRepository();
    mockLookup = MockCnpjLookupService();
    mockHandler = MockCreateOrganizationHandler();

    // Default behaviors
    when(() => mockRepo.checkCnpjExists(any())).thenAnswer((_) async => false);
    when(() => mockLookup.lookup(any())).thenAnswer((_) async => null);
    when(
      () => mockHandler.sendInviteNotification(
        email: any(named: 'email'),
        inviteUrl: any(named: 'inviteUrl'),
        orgName: any(named: 'orgName'),
      ),
    ).thenAnswer((_) async => {});
  });

  Widget createWizard(
    MockSuperAdminRepository repo,
    MockCnpjLookupService lookup, {
    VoidCallback? onSuccess,
  }) {
    return ProviderScope(
      overrides: [
        superAdminRepositoryProvider.overrideWithValue(repo),
        cnpjLookupServiceProvider.overrideWithValue(lookup),
        createOrganizationHandlerProvider.overrideWithValue(mockHandler),
        currentSuperAdminIdProvider.overrideWithValue('mock-super-admin-id'),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CreateOrganizationWizard(onSuccess: onSuccess ?? () {}),
        ),
      ),
    );
  }

  group('CreateOrganizationWizard (Forensic & UX)', () {
    testWidgets('Wizard Step 1: Structural CNPJ validation blocks progression', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createWizard(mockRepo, mockLookup));
      await tester.pumpAndSettle();

      // 1. Enter valid names
      await tester.enterText(
        find.ancestor(
          of: find.text('Razão Social *'),
          matching: find.byType(TextFormField),
        ),
        'Hydra Corp',
      );
      await tester.enterText(
        find.ancestor(
          of: find.text('Nome Fantasia *'),
          matching: find.byType(TextFormField),
        ),
        'Hydra',
      );

      // 2. Enter an invalid CNPJ (all same digits - structural failure)
      await tester.enterText(
        find.ancestor(
          of: find.text('CNPJ *'),
          matching: find.byType(TextFormField),
        ),
        '11.111.111/1111-11',
      );

      // Wait for debounce settle
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pumpAndSettle();

      // 3. Attempt to go to next step
      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();

      // Verify it stays on step 1 due to validation error
      // We use findsAtLeast(1) because both the validator and the manual text might show it
      expect(find.text('CNPJ inválido'), findsAtLeast(1));
    });

    testWidgets('Wizard Completion: Full 3-Step Flow and Success Dialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const orgId = 'new-org-id';
      var successCalled = false;

      // Mock Success Responses
      when(() => mockHandler.handle(any())).thenAnswer(
        (_) async => const CreateOrganizationResult(
          orgId: orgId,
          invitationToken: 'mock-token',
        ),
      );

      await tester.pumpWidget(
        createWizard(
          mockRepo,
          mockLookup,
          onSuccess: () => successCalled = true,
        ),
      );
      await tester.pumpAndSettle();

      // --- STEP 1: Basic Info ---
      await tester.enterText(
        find.ancestor(
          of: find.text('Razão Social *'),
          matching: find.byType(TextFormField),
        ),
        'Omni Consorcio',
      );
      await tester.enterText(
        find.ancestor(
          of: find.text('Nome Fantasia *'),
          matching: find.byType(TextFormField),
        ),
        'Omni',
      );

      // Use a valid CNPJ format (for mock check only)
      await tester.enterText(
        find.ancestor(
          of: find.text('CNPJ *'),
          matching: find.byType(TextFormField),
        ),
        '11.444.777/0001-61',
      );

      await tester.pump(const Duration(milliseconds: 800)); // Debounce
      await tester.pumpAndSettle();

      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();

      // --- STEP 2: Limits ---
      await tester.enterText(
        find.ancestor(
          of: find.text('Máximo de Veículos *'),
          matching: find.byType(TextFormField),
        ),
        '100',
      );
      await tester.enterText(
        find.ancestor(
          of: find.text('Máximo de Contratos Ativos *'),
          matching: find.byType(TextFormField),
        ),
        '50',
      );
      await tester.enterText(
        find.ancestor(
          of: find.text('Custo Mensal da Ferramenta *'),
          matching: find.byType(TextFormField),
        ),
        '50000',
      );
      await tester.enterText(
        find.ancestor(
          of: find.text(
            'Ex: Criação de novo tenant conforme contrato comercial #123',
          ),
          matching: find.byType(TextFormField),
        ),
        'Criação de novo tenant conforme contrato #123',
      );

      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();

      // --- STEP 3: Admin Invite ---
      await tester.enterText(
        find.ancestor(
          of: find.text('E-mail do Admin Inicial *'),
          matching: find.byType(TextFormField),
        ),
        'admin@omni.com',
      );

      // FINAL SUBMIT (Find the button that says 'Criar e Enviar Convite')
      final submitButton = find.widgetWithText(
        ElevatedButton,
        'Criar e Enviar Convite',
      );
      await tester.tap(submitButton);
      await tester.pump(); // Start submission

      // Wait for async operations
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Verify the Success Dialog appears
      expect(find.text('Organização Criada!'), findsOneWidget);

      // Close Dialog
      await tester.tap(find.text('Ver Tenants'));
      await tester.pumpAndSettle();

      expect(successCalled, isTrue);
    });

    testWidgets(
      'Wizard Error: Repository failure displays forensic error snackbar',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // thenThrow fires synchronously — the async wrapper never completes,
        // so Flutter's runner intercepts it before the wizard's try/catch.
        // thenAnswer with an async throw produces a rejected Future that
        // `await handler.handle(cmd)` correctly unwraps into the catch block.
        when(() => mockHandler.handle(any())).thenAnswer(
          (_) async =>
              throw const DomainException('Forensic Permission Denied'),
        );

        await tester.pumpWidget(createWizard(mockRepo, mockLookup));
        await tester.pumpAndSettle();

        // Advance Steps
        await tester.enterText(
          find.ancestor(
            of: find.text('Razão Social *'),
            matching: find.byType(TextFormField),
          ),
          'FailOrg',
        );
        await tester.enterText(
          find.ancestor(
            of: find.text('Nome Fantasia *'),
            matching: find.byType(TextFormField),
          ),
          'Fail',
        );
        await tester.enterText(
          find.ancestor(
            of: find.text('CNPJ *'),
            matching: find.byType(TextFormField),
          ),
          '11.444.777/0001-61',
        );
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Próximo'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.ancestor(
            of: find.text('Máximo de Veículos *'),
            matching: find.byType(TextFormField),
          ),
          '10',
        );
        await tester.enterText(
          find.ancestor(
            of: find.text('Máximo de Contratos Ativos *'),
            matching: find.byType(TextFormField),
          ),
          '5',
        );
        await tester.enterText(
          find.ancestor(
            of: find.text('Custo Mensal da Ferramenta *'),
            matching: find.byType(TextFormField),
          ),
          '50000',
        );
        await tester.enterText(
          find.ancestor(
            of: find.text(
              'Ex: Criação de novo tenant conforme contrato comercial #123',
            ),
            matching: find.byType(TextFormField),
          ),
          'Criação de novo tenant conforme contrato #123',
        );
        await tester.tap(find.text('Próximo'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.ancestor(
            of: find.text('E-mail do Admin Inicial *'),
            matching: find.byType(TextFormField),
          ),
          'bad@email.com',
        );

        // Submit
        final submitButton = find.widgetWithText(
          ElevatedButton,
          'Criar e Enviar Convite',
        );
        await tester.tap(submitButton);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        // Verify error handling (Snackbar)
        expect(find.text('Forensic Permission Denied'), findsOneWidget);
      },
    );
  });
}
