import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/domain/super_admin/cnpj_company_data.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/i_cnpj_lookup_service.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/features/super_admin/presentation/screens/create_organization_wizard.dart';
import 'package:veraprob/infrastructure/providers/super_admin_providers.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';
import 'package:veraprob/application/super_admin/create_organization_handler.dart';
import 'package:veraprob/application/super_admin/create_organization_result.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/core/theme/app_theme.dart';

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
        isSuperAdminProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: CreateOrganizationWizard(onSuccess: onSuccess ?? () {}),
        ),
      ),
    );
  }

  group('CreateOrganizationWizard (Forensic & UX)', () {
    testWidgets(
      'Wizard Step 1: Structural CNPJ validation blocks progression',
      (tester) async {
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
        final nextButton1 = find.text('Próximo');
        await tester.ensureVisible(nextButton1);
        await tester.tap(nextButton1);
        await tester.pumpAndSettle();

        // Verify it stays on step 1 due to validation error
        // Verify it appears exactly once (no duplication)
        expect(find.text('CNPJ inválido'), findsOneWidget);
      },
    );

    testWidgets('Wizard Completion: Full 3-Step Flow and Success Dialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const orgId = 'new-org-id';
      var successCalled = false;

      when(() => mockHandler.handle(any())).thenAnswer(
        (_) async => const CreateOrganizationResult(
          orgId: orgId,
          invitationTokens: ['mock-token'],
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
      await tester.enterText(
        find.ancestor(
          of: find.text('CNPJ *'),
          matching: find.byType(TextFormField),
        ),
        '11.444.777/0001-61',
      );

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      final nextButtonStep1 = find.text('Próximo');
      await tester.ensureVisible(nextButtonStep1);
      await tester.tap(nextButtonStep1);
      await tester.pumpAndSettle();

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

      final nextButtonStep2 = find.text('Próximo');
      await tester.ensureVisible(nextButtonStep2);
      await tester.tap(nextButtonStep2);
      await tester.pumpAndSettle();

      final emailField1 = find.ancestor(
        of: find.text('E-mails dos Admins *'),
        matching: find.byType(TextField),
      );
      await tester.enterText(emailField1, 'admin@omni.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final submitButton = find.widgetWithText(
        ElevatedButton,
        'Criar e Enviar Convite',
      );
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('Organização Criada!'), findsOneWidget);
      await tester.tap(find.text('Concluir'));
      await tester.pumpAndSettle();

      expect(successCalled, isTrue);
    });

    testWidgets(
      'Wizard Error: Repository failure displays forensic error snackbar',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1500));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        when(() => mockHandler.handle(any())).thenAnswer(
          (_) async =>
              throw const DomainException('Forensic Permission Denied'),
        );

        await tester.pumpWidget(createWizard(mockRepo, mockLookup));
        await tester.pumpAndSettle();

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
        final nextButtonErr1 = find.text('Próximo');
        await tester.ensureVisible(nextButtonErr1);
        await tester.tap(nextButtonErr1);
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
        final nextButtonErr2 = find.text('Próximo');
        await tester.ensureVisible(nextButtonErr2);
        await tester.tap(nextButtonErr2);
        await tester.pumpAndSettle();

        final emailField2 = find.ancestor(
          of: find.text('E-mails dos Admins *'),
          matching: find.byType(TextField),
        );
        await tester.enterText(emailField2, 'bad@email.com');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        final submitButton = find.widgetWithText(
          ElevatedButton,
          'Criar e Enviar Convite',
        );
        await tester.ensureVisible(submitButton);
        await tester.tap(submitButton);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(
          find.text('Você não tem permissão para realizar esta operação.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('UX: CNPJ Debounce Integrity', (tester) async {
      await tester.pumpWidget(createWizard(mockRepo, mockLookup));

      final cnpjFinder = find.ancestor(
        of: find.text('CNPJ *'),
        matching: find.byType(TextFormField),
      );

      await tester.enterText(cnpjFinder, '11.444.777/0001-61');

      // Wait less than debounce (300ms < 600ms)
      await tester.pump(const Duration(milliseconds: 300));
      verifyNever(() => mockRepo.checkCnpjExists(any()));

      // Wait more to trigger (another 400ms = 700ms total)
      await tester.pump(const Duration(milliseconds: 400));
      verify(() => mockRepo.checkCnpjExists('11444777000161')).called(1);
    });

    testWidgets('UX: Auto-Fill Intention Preservation', (tester) async {
      final mockData = CnpjCompanyData(
        cnpj: '11444777000161',
        legalName: 'Omni Consorcio Ltda',
        tradeName: 'Omni Digital',
        situation: 'ATIVA',
      );

      when(
        () => mockLookup.lookup('11444777000161'),
      ).thenAnswer((_) async => mockData);

      await tester.pumpWidget(createWizard(mockRepo, mockLookup));

      final tradeNameFinder = find.ancestor(
        of: find.text('Nome Fantasia *'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(tradeNameFinder, 'Meu Nome Customizado');

      final cnpjFinder = find.ancestor(
        of: find.text('CNPJ *'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(cnpjFinder, '11.444.777/0001-61');

      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      final legalNameFinder = find.ancestor(
        of: find.text('Razão Social *'),
        matching: find.byType(TextFormField),
      );
      expect(
        tester.widget<TextFormField>(legalNameFinder).controller?.text,
        equals('Omni Consorcio Ltda'),
      );
      expect(
        tester.widget<TextFormField>(tradeNameFinder).controller?.text,
        equals('Meu Nome Customizado'),
      );
    });

    testWidgets('Resilience: API Failure does not crash UI', (tester) async {
      when(
        () => mockLookup.lookup(any()),
      ).thenThrow(Exception('Service Unavailable'));

      await tester.pumpWidget(createWizard(mockRepo, mockLookup));

      final cnpjFinder = find.ancestor(
        of: find.text('CNPJ *'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(cnpjFinder, '11.444.777/0001-61');

      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pumpAndSettle();

      expect(find.byType(CreateOrganizationWizard), findsOneWidget);
      expect(find.text('Razão Social *'), findsOneWidget);
    });
    testWidgets('CT07: DomainException mapping and UI persistence', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      when(() => mockHandler.handle(any())).thenThrow(
        const DomainException('DomainException: invite_already_exists'),
      );

      await tester.pumpWidget(createWizard(mockRepo, mockLookup));
      await tester.pumpAndSettle();

      // Step 1
      await tester.enterText(
        find.ancestor(of: find.text('Razão Social *'), matching: find.byType(TextFormField)),
        'Org Test',
      );
      await tester.enterText(
        find.ancestor(of: find.text('Nome Fantasia *'), matching: find.byType(TextFormField)),
        'Org',
      );
      await tester.enterText(
        find.ancestor(of: find.text('CNPJ *'), matching: find.byType(TextFormField)),
        '11.444.777/0001-61',
      );
      // Aguarda o debounce de 600ms do _checkCnpjExists
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();

      // Step 2
      await tester.enterText(
        find.ancestor(of: find.text('Máximo de Veículos *'), matching: find.byType(TextFormField)),
        '50',
      );
      await tester.enterText(
        find.ancestor(of: find.text('Máximo de Contratos Ativos *'), matching: find.byType(TextFormField)),
        '10',
      );
      await tester.enterText(
        find.ancestor(of: find.text('Custo Mensal da Ferramenta *'), matching: find.byType(TextFormField)),
        '500000',
      );
      // O título Justificativa é um widget separado, usamos o hintText para achar o campo
      await tester.enterText(
        find.ancestor(
          of: find.text('Ex: Criação de novo tenant conforme contrato comercial #123'),
          matching: find.byType(TextFormField),
        ),
        'Justificativa de teste válida',
      );
      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();

      // Step 3
      final emailField = find.ancestor(
        of: find.text('E-mails dos Admins *'),
        matching: find.byType(TextField),
      );
      await tester.enterText(emailField, 'admin@teste.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final submitBtn = find.widgetWithText(ElevatedButton, 'Criar e Enviar Convite');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verify Friendly Message (mapped from tech string)
      expect(
        find.text('Um convite já foi enviado para um destes administradores.'),
        findsOneWidget,
      );

      // Verify UI Persistence (Wizard didn't close)
      expect(find.byType(CreateOrganizationWizard), findsOneWidget);
    });
  });
}
