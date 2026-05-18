import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/cnpj_autofill_field.dart';
import 'package:veraprob/domain/super_admin/cnpj_company_data.dart';
import 'package:veraprob/domain/super_admin/i_cnpj_lookup_service.dart';
import 'package:veraprob/state/providers/super_admin_providers.dart';
import 'package:mockito/mockito.dart';

// Mock for the proxy-based ICnpjLookupService (INV-14 compliant)
class MockCnpjLookupService extends Mock implements ICnpjLookupService {
  @override
  Future<CnpjCompanyData?> lookup(String? cnpjDigits) {
    return super.noSuchMethod(
          Invocation.method(#lookup, [cnpjDigits]),
          returnValue: Future.value(null),
        )
        as Future<CnpjCompanyData?>;
  }
}

void main() {
  group('CnpjAutofillField (CT17)', () {
    late MockCnpjLookupService mockService;
    final companyNameController = TextEditingController();

    setUp(() {
      mockService = MockCnpjLookupService();
      companyNameController.clear();
    });

    Widget buildWidget() {
      return ProviderScope(
        overrides: [cnpjLookupServiceProvider.overrideWithValue(mockService)],
        child: MaterialApp(
          home: Scaffold(
            body: CnpjAutofillField(
              companyNameController: companyNameController,
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Debounce Protection: Only calls API once for multiple fast inputs',
      (tester) async {
        when(mockService.lookup(any)).thenAnswer((_) async => null);

        await tester.pumpWidget(buildWidget());

        final textField = find.byType(TextFormField).first; // CNPJ Field

        // Type partial CNPJ (less than 14 digits — lookup won't fire)
        await tester.enterText(textField, '12.345');
        await tester.pump(const Duration(milliseconds: 200));

        // Type a full 14-digit CNPJ before debounce expires
        await tester.enterText(textField, '45.518.855/0001-47');
        await tester.pump(const Duration(milliseconds: 600));

        // Should have been called only ONCE with the sanitized 14-digit value
        verify(mockService.lookup('45518855000147')).called(1);
      },
    );

    testWidgets(
      'Visual Feedback (UX-Ops): Shows loading during API call and resolves',
      (tester) async {
        // Simulate API delay
        when(mockService.lookup(any)).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          return CnpjCompanyData(
            cnpj: '45518855000147',
            legalName: 'Estrela Dalva Transportes Ltda',
            tradeName: 'Viação Estrela Dalva',
            situation: 'ATIVA',
          );
        });

        await tester.pumpWidget(buildWidget());
        final textField = find.byType(TextFormField).first;

        await tester.enterText(textField, '45.518.855/0001-47');
        await tester.pump(
          const Duration(milliseconds: 600),
        ); // Trigger debounce

        // Start the async operation
        await tester.pump();

        // Should show a loading indicator
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Complete the API call
        await tester.pumpAndSettle(const Duration(milliseconds: 500));

        // Loader should disappear and company name should be filled
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(companyNameController.text, 'Estrela Dalva Transportes Ltda');
      },
    );

    testWidgets('Graceful Degradation: Allows manual editing when API fails', (
      tester,
    ) async {
      when(mockService.lookup(any)).thenAnswer((_) async => null);

      await tester.pumpWidget(buildWidget());
      final textField = find.byType(TextFormField).first; // CNPJ field
      final nameField = find.byType(TextFormField).last; // Nome field

      await tester.enterText(textField, '45.518.855/0001-47');
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Mock returned null (simulating 500 or Timeout)
      // The Razão Social field should remain enabled and editable
      expect(companyNameController.text, isEmpty);

      // User can type manually without the screen freezing
      await tester.enterText(nameField, 'Empresa Inserida Manualmente');
      await tester.pump();

      expect(companyNameController.text, 'Empresa Inserida Manualmente');
    });

    testWidgets('Short CNPJ: Does not trigger lookup for less than 14 digits', (
      tester,
    ) async {
      when(mockService.lookup(any)).thenAnswer((_) async => null);

      await tester.pumpWidget(buildWidget());
      final textField = find.byType(TextFormField).first;

      // Type only 10 digits
      await tester.enterText(textField, '45.518.855/');
      await tester.pump(const Duration(milliseconds: 700));

      // Should NOT have called lookup (less than 14 digits)
      verifyNever(mockService.lookup(any));
    });

    group('Módulo 11 Validation (CT-MOD11-UI)', () {
      testWidgets('CNPJ inválido (Módulo 11): não chama API e exibe erro', (
        tester,
      ) async {
        // 12.345.678/0001-00 has 14 digits but fails Módulo 11
        await tester.pumpWidget(buildWidget());
        final textField = find.byType(TextFormField).first;

        await tester.enterText(textField, '12.345.678/0001-00');
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump();

        verifyNever(mockService.lookup(any));
        expect(
          find.text('CNPJ inválido ou não encontrado na Receita.'),
          findsOneWidget,
        );
      });

      testWidgets(
        'CNPJ inválido (Módulo 11): não exibe spinner de carregamento',
        (tester) async {
          await tester.pumpWidget(buildWidget());
          final textField = find.byType(TextFormField).first;

          await tester.enterText(textField, '12.345.678/0001-00');
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pump();

          expect(find.byType(CircularProgressIndicator), findsNothing);
        },
      );

      testWidgets(
        'CNPJ inválido (Módulo 11): re-edição limpa o erro imediatamente',
        (tester) async {
          await tester.pumpWidget(buildWidget());
          final textField = find.byType(TextFormField).first;

          // Trigger the invalid state
          await tester.enterText(textField, '12.345.678/0001-00');
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pump();
          expect(
            find.text('CNPJ inválido ou não encontrado na Receita.'),
            findsOneWidget,
          );

          // User starts editing again — error must vanish immediately
          await tester.enterText(textField, '12.345.678/0001-0');
          await tester.pump();
          expect(
            find.text('CNPJ inválido ou não encontrado na Receita.'),
            findsNothing,
          );
        },
      );
    });
  });
}
