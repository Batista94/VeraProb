import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/widgets/universal_csv_importer.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(0.8)),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('UniversalCsvImporterDialog Widget Tests', () {
    testWidgets('W1: Renderiza wizard com 3 steps', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_wrap(const UniversalCsvImporterDialog()));
      await tester.pumpAndSettle();

      expect(find.text('① UPLOAD'), findsOneWidget);
      expect(find.text('② MAPEAMENTO'), findsOneWidget);
      expect(find.text('③ VALIDAÇÃO'), findsOneWidget);
    });

    testWidgets('W2: Step 1: dropdowns mostram entidades', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_wrap(const UniversalCsvImporterDialog()));
      await tester.pumpAndSettle();

      expect(find.text('Tipo de Entidade'), findsOneWidget);
      expect(find.text('Ativo (Veículo)'), findsOneWidget);
      expect(find.text('Template Salvo'), findsOneWidget);
      expect(find.text('Nenhum — Novo Mapeamento'), findsOneWidget);
    });

    testWidgets('W3: Step 2: mapping grid mostra headers', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_wrap(const UniversalCsvImporterDialog()));
      await tester.pumpAndSettle();

      // Click "SELECIONAR ARQUIVO" to enable mapping navigation
      await tester.tap(find.text('SELECIONAR ARQUIVO'));
      await tester.pumpAndSettle();

      // Click "MAPEAMENTO" to proceed to step 2
      await tester.tap(find.text('MAPEAMENTO'));
      await tester.pumpAndSettle();

      expect(find.text('COLUNA DO CSV'), findsOneWidget);
      expect(find.text('CAMPO VERAPROB'), findsOneWidget);
      expect(find.text('TRANSFORM'), findsOneWidget);
      expect(find.text('PLACA'), findsOneWidget);
      expect(find.text('MODELO'), findsOneWidget);
    });

    testWidgets('W4: Step 3: mostra contagem de erros', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_wrap(const UniversalCsvImporterDialog()));
      await tester.pumpAndSettle();

      // Step 1 -> Upload file and go to step 2
      await tester.tap(find.text('SELECIONAR ARQUIVO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MAPEAMENTO'));
      await tester.pumpAndSettle();

      // Step 2 -> Validate mappings and go to step 3
      await tester.tap(find.text('VALIDAR'));
      await tester.pumpAndSettle();

      expect(find.text('150 linhas analisadas'), findsOneWidget);
      expect(find.text('142 válidas'), findsOneWidget);
      expect(find.text('8 com erros'), findsOneWidget);
      expect(find.text('Erros Detalhados (Delta)'), findsOneWidget);
    });

    testWidgets('W5: Botão fechar funciona', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) {
                  return ElevatedButton(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (BuildContext context) =>
                            const UniversalCsvImporterDialog(),
                      );
                    },
                    child: const Text('OPEN DIALOG'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Open the dialog
      await tester.tap(find.text('OPEN DIALOG'));
      await tester.pumpAndSettle();

      expect(find.byType(UniversalCsvImporterDialog), findsOneWidget);

      // Tap close button in dialog
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(UniversalCsvImporterDialog), findsNothing);
    });
  });
}
