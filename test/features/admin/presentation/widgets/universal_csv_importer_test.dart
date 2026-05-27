import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/admin/import_csv_handler.dart';
import 'package:veraprob/features/admin/presentation/widgets/universal_csv_importer.dart';
import 'package:veraprob/features/admin/providers/csv_import_providers.dart';

// ── Fake notifier for testing ─────────────────────────────────────────────────

class _FakeCsvImportFlowNotifier extends CsvImportFlowNotifier {
  final CsvImportFlowState Function() _builder;
  _FakeCsvImportFlowNotifier(this._builder);

  @override
  CsvImportFlowState build() => _builder();

  @override
  void init(String _) {
    // No-op: test controls state directly.
  }

  @override
  Future<void> pickFile() async {
    // No-op for widget tests.
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {CsvImportFlowState? flowState}) {
  return ProviderScope(
    overrides: [
      if (flowState != null)
        csvImportFlowProvider.overrideWith(
          () => _FakeCsvImportFlowNotifier(() => flowState),
        ),
    ],
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

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('UniversalCsvImporterDialog', () {
    // W1 — step labels visible on open
    testWidgets('W1: shows 4 step labels on initial render', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const UniversalCsvImporterDialog(initialEntity: 'operator'),
          flowState: const CsvImportInitial(targetEntity: 'operator'),
        ),
      );
      await tester.pump(); // microtask frame

      expect(find.text('UPLOAD'), findsOneWidget);
      expect(find.text('MAPEAMENTO'), findsOneWidget);
      expect(find.text('VALIDAÇÃO'), findsOneWidget);
      expect(find.text('RESULTADO'), findsOneWidget);
    });

    // W2 — upload step shows drop zone text
    testWidgets('W2: upload step shows pick-file affordance', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const UniversalCsvImporterDialog(initialEntity: 'operator'),
          flowState: const CsvImportInitial(targetEntity: 'operator'),
        ),
      );
      await tester.pump();

      // Upload step must show the drag-drop / click area
      expect(find.byIcon(Icons.upload_file_outlined), findsWidgets);
    });

    // W3 — error banner appears on CsvImportError state
    testWidgets('W3: shows error banner when state is CsvImportError', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const errorMsg = 'Formato inválido. Use .csv ou .tsv.';
      await tester.pumpWidget(
        _wrap(
          const UniversalCsvImporterDialog(initialEntity: 'operator'),
          flowState: const CsvImportError(
            targetEntity: 'operator',
            currentStep: 0,
            message: errorMsg,
          ),
        ),
      );
      await tester.pump();

      expect(find.text(errorMsg), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    // W4 — dialog with required initialEntity compiles and renders
    testWidgets('W4: initialEntity param accepted without compile error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // These all MUST compile — regression guard for missing initialEntity.
      final widgets = [
        const UniversalCsvImporterDialog(initialEntity: 'operator'),
        const UniversalCsvImporterDialog(initialEntity: 'contract'),
        const UniversalCsvImporterDialog(initialEntity: 'zone'),
        const UniversalCsvImporterDialog(initialEntity: 'asset'),
      ];

      for (final w in widgets) {
        await tester.pumpWidget(
          _wrap(w, flowState: CsvImportInitial(targetEntity: w.initialEntity)),
        );
        await tester.pump();
        expect(find.byType(UniversalCsvImporterDialog), findsOneWidget);
      }
    });

    // W5 — close button pops dialog when state is Initial (no dirty-check)
    testWidgets('W5: close button dismisses dialog in clean state', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            csvImportFlowProvider.overrideWith(
              () => _FakeCsvImportFlowNotifier(
                () => const CsvImportInitial(targetEntity: 'operator'),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => const UniversalCsvImporterDialog(
                      initialEntity: 'operator',
                    ),
                  ),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(find.byType(UniversalCsvImporterDialog), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(UniversalCsvImporterDialog), findsNothing);
    });

    // W6 — Voltar button visible on CsvImportMapped state
    testWidgets('W6: footer shows Voltar button in mapped state', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const UniversalCsvImporterDialog(initialEntity: 'operator'),
          flowState: const CsvImportMapped(
            targetEntity: 'operator',
            fileName: 'test.csv',
            headers: ['PLACA'],
            previewRows: [
              {'PLACA': 'ABC-1234'},
            ],
            allRows: [
              {'PLACA': 'ABC-1234'},
            ],
            rawBytes: [1, 2, 3],
            mappings: {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Voltar'), findsOneWidget);
    });

    // W7 — done state hides footer
    testWidgets('W7: footer hidden when state is CsvImportDone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const UniversalCsvImporterDialog(initialEntity: 'operator'),
          flowState: const CsvImportDone(
            targetEntity: 'operator',
            result: CsvImportResult(
              totalProcessed: 5,
              rowsImported: 5,
              rowsSkipped: 0,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Voltar'), findsNothing);
      expect(find.text('Validar'), findsNothing);
    });

    // W8 — no RenderFlex overflow at narrow viewport
    testWidgets('W8: no overflow at 600px viewport', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const UniversalCsvImporterDialog(initialEntity: 'operator'),
          flowState: const CsvImportInitial(targetEntity: 'operator'),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // W9 — active step pill text color is not equal to background (invisible text regression)
    testWidgets('W9: active step pill text color != background color', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          const UniversalCsvImporterDialog(initialEntity: 'operator'),
          flowState: const CsvImportInitial(targetEntity: 'operator'),
        ),
      );
      await tester.pump();

      // Active pill (step 0 = UPLOAD) must use Colors.white text.
      // Find all Text widgets with 'UPLOAD' label.
      final uploadFinder = find.text('UPLOAD');
      expect(uploadFinder, findsOneWidget);

      final uploadText = tester.widget<Text>(uploadFinder);
      final textColor = uploadText.style?.color;

      // Text must not be null and must not equal the action bg color (invisible bug).
      const actionBgColor = Color(0x26_00A3FF); // action.withValues(alpha:0.15)
      expect(textColor, isNotNull);
      expect(textColor, isNot(equals(actionBgColor)));
      expect(textColor, isNot(equals(Colors.transparent)));
    });
  });
}
