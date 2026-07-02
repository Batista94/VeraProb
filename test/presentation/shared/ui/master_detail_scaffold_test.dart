// master_detail_scaffold_test.dart
//
// TDD P2: testes escritos ANTES da implementação (protocol obrigatório).
// Cobre: split wide, stack narrow (sem/com seleção), callback back.
// Todos os seletores são key-based (INV das decisões P2).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/presentation/shared/ui/master_detail_scaffold.dart';

Widget _buildSut({
  required bool hasSelection,
  VoidCallback? onBack,
  double width = 1200,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: MasterDetailScaffold(
          masterBuilder: (_) =>
              const Text('Master', key: ValueKey('master-panel')),
          detailBuilder: (_) =>
              const Text('Detail', key: ValueKey('detail-panel')),
          hasSelection: hasSelection,
          onBack: onBack ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('MasterDetailScaffold', () {
    group('wide layout (>900px)', () {
      testWidgets('shows master and detail side by side', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        await tester.pumpWidget(_buildSut(hasSelection: false));

        expect(find.byKey(const ValueKey('master-panel')), findsOneWidget);
        expect(find.byKey(const ValueKey('detail-panel')), findsOneWidget);
        expect(find.byType(VerticalDivider), findsOneWidget);
      });

      testWidgets('back button absent in wide layout', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        await tester.pumpWidget(_buildSut(hasSelection: true));

        expect(find.byKey(const ValueKey('master-detail-back')), findsNothing);
      });
    });

    group('narrow layout (<=900px) — no selection', () {
      testWidgets('shows only master panel', (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 800));
        await tester.pumpWidget(_buildSut(hasSelection: false, width: 600));

        expect(find.byKey(const ValueKey('master-panel')), findsOneWidget);
        expect(find.byKey(const ValueKey('detail-panel')), findsNothing);
      });

      testWidgets('back button absent when no selection', (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 800));
        await tester.pumpWidget(_buildSut(hasSelection: false, width: 600));

        expect(find.byKey(const ValueKey('master-detail-back')), findsNothing);
      });
    });

    group('narrow layout (<=900px) — with selection', () {
      testWidgets('shows only detail panel', (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 800));
        await tester.pumpWidget(_buildSut(hasSelection: true, width: 600));

        expect(find.byKey(const ValueKey('detail-panel')), findsOneWidget);
        expect(find.byKey(const ValueKey('master-panel')), findsNothing);
      });

      testWidgets('back button is visible', (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 800));
        await tester.pumpWidget(_buildSut(hasSelection: true, width: 600));

        expect(
          find.byKey(const ValueKey('master-detail-back')),
          findsOneWidget,
        );
      });

      testWidgets('tapping back calls onBack callback', (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 800));
        var called = false;
        await tester.pumpWidget(
          _buildSut(
            hasSelection: true,
            width: 600,
            onBack: () => called = true,
          ),
        );

        await tester.tap(find.byKey(const ValueKey('master-detail-back')));
        await tester.pump();

        expect(called, isTrue);
      });
    });
  });
}
