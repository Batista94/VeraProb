// TDD anchor — Phase 10: DomainChipInput widget
// Tests FAIL until C1 (DomainChipInput) is implemented.
// Happy path + 4 adversarial scenarios.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/presentation/shared/ui/domain_chip_input.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('DomainChipInput — happy path', () {
    testWidgets('typing valid domain + tap + adds chip, clears controller', (
      tester,
    ) async {
      final added = <List<String>>[];

      await tester.pumpWidget(
        _wrap(
          DomainChipInput(
            initialDomains: const [],
            onChanged: added.add,
            hintText: 'ex: empresa.com.br',
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'empresa.com.br');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(find.text('empresa.com.br'), findsOneWidget); // chip label
      expect(added, isNotEmpty);
      expect(added.last, contains('empresa.com.br'));

      // Controller should be cleared
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller?.text ?? '', isEmpty);
    });

    testWidgets('deleting a chip removes it and calls onChanged', (
      tester,
    ) async {
      final changed = <List<String>>[];

      await tester.pumpWidget(
        _wrap(
          DomainChipInput(
            initialDomains: const ['empresa.com.br'],
            onChanged: changed.add,
          ),
        ),
      );

      await tester.pump();
      expect(find.text('empresa.com.br'), findsOneWidget);

      // Tap the delete icon on the InputChip
      await tester.tap(find.byIcon(Icons.cancel));
      await tester.pump();

      expect(find.text('empresa.com.br'), findsNothing);
      expect(changed.last, isEmpty);
    });

    testWidgets('pressing Enter key adds chip', (tester) async {
      final added = <List<String>>[];

      await tester.pumpWidget(
        _wrap(DomainChipInput(initialDomains: const [], onChanged: added.add)),
      );

      await tester.enterText(find.byType(TextField), 'parceiro.io');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('parceiro.io'), findsOneWidget);
      expect(added.last, contains('parceiro.io'));
    });

    testWidgets('normalizes domain to lowercase before adding', (tester) async {
      final added = <List<String>>[];

      await tester.pumpWidget(
        _wrap(DomainChipInput(initialDomains: const [], onChanged: added.add)),
      );

      await tester.enterText(find.byType(TextField), 'Empresa.COM.BR');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(find.widgetWithText(InputChip, 'empresa.com.br'), findsOneWidget);
      expect(added.last.first, 'empresa.com.br');
    });

    testWidgets('duplicate domain is rejected (chip not added twice)', (
      tester,
    ) async {
      final added = <List<String>>[];

      await tester.pumpWidget(
        _wrap(
          DomainChipInput(
            initialDomains: const ['empresa.com.br'],
            onChanged: added.add,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'empresa.com.br');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(added, isEmpty); // onChanged NOT called for duplicate
      // Only one chip should exist
      expect(find.widgetWithText(InputChip, 'empresa.com.br'), findsOneWidget);
    });
  });

  group('Adversarial — Domínio Malformado', () {
    Future<void> expectRejected(WidgetTester tester, String input) async {
      final added = <List<String>>[];

      await tester.pumpWidget(
        _wrap(DomainChipInput(initialDomains: const [], onChanged: added.add)),
      );

      await tester.enterText(find.byType(TextField), input);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(
        added,
        isEmpty,
        reason: 'onChanged must NOT be called for "$input"',
      );
      expect(
        find.byType(InputChip),
        findsNothing,
        reason: 'No chip should be added for "$input"',
      );
    }

    testWidgets('rejects full URL (https://...)', (tester) async {
      await expectRejected(tester, 'https://google.com');
    });

    testWidgets('rejects email address (user@domain)', (tester) async {
      await expectRejected(tester, 'user@google.com');
    });

    testWidgets('rejects double-dot (..)', (tester) async {
      await expectRejected(tester, '..');
    });

    testWidgets('rejects empty string', (tester) async {
      await expectRejected(tester, '');
    });

    testWidgets('rejects whitespace-only string', (tester) async {
      await expectRejected(tester, '   ');
    });

    testWidgets('rejects domain with spaces', (tester) async {
      await expectRejected(tester, 'em presa.com');
    });

    testWidgets('shows error message on invalid input', (tester) async {
      await tester.pumpWidget(
        _wrap(DomainChipInput(initialDomains: const [], onChanged: (_) {})),
      );

      await tester.enterText(find.byType(TextField), 'https://google.com');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      // Error text should appear in the external Text widget
      expect(find.text('Não use URL completa'), findsOneWidget);
    });
  });

  group('Adversarial — Lista Exaustiva (20 domains, no overflow)', () {
    testWidgets('renders 20 long domains in Wrap without overflow', (
      tester,
    ) async {
      // Set viewport to phone size
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final domains = List.generate(
        20,
        (i) => 'very-long-domain-name-$i.example.com.br',
      );

      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: DomainChipInput(initialDomains: domains, onChanged: (_) {}),
          ),
        ),
      );

      await tester.pump();

      // No RenderFlex overflow should be thrown
      expect(tester.takeException(), isNull);
      // All 20 chips present
      expect(find.byType(InputChip), findsNWidgets(20));
    });
  });
}
