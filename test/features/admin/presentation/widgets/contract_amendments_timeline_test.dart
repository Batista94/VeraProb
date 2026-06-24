import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/sla_audit/projections/contract_financial_amendment_view.dart';
import 'package:veraprob/features/admin/presentation/widgets/contract_amendments_timeline.dart';
import 'package:veraprob/state/providers/contract_providers.dart';

const _contractId = 'contract-1';

ContractFinancialAmendmentView _amendment({
  required String id,
  int? ceilingCents,
  required int bps,
  required DateTime effectiveAt,
  String? notes,
}) {
  return ContractFinancialAmendmentView(
    id: id,
    financialCeilingCents: ceilingCents,
    penaltyMultiplierBps: bps,
    effectiveAtUtc: effectiveAt,
    amendedAtUtc: effectiveAt,
    notes: notes,
  );
}

Widget _host(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      home: Scaffold(body: ContractAmendmentsTimeline(contractId: _contractId)),
    ),
  );
}

void main() {
  group('ContractFinancialAmendmentView.fromJson', () {
    test('parses fields and derives penaltyMultiplier (bps/10000)', () {
      final view = ContractFinancialAmendmentView.fromJson({
        'id': 'a1',
        'financial_ceiling_cents': 5000000,
        'penalty_multiplier_bps': 15000,
        'effective_at_utc': '2026-06-01T12:00:00Z',
        'amended_at_utc': '2026-05-31T08:30:00Z',
        'notes': 'Renegociação Q2',
      });

      expect(view.id, 'a1');
      expect(view.financialCeilingCents, 5000000);
      expect(view.penaltyMultiplierBps, 15000);
      expect(view.penaltyMultiplierLabel, '1.50x');
      expect(view.effectiveAtUtc.isUtc, isTrue);
      expect(view.notes, 'Renegociação Q2');
    });

    test('null ceiling parses to null (sem teto)', () {
      final view = ContractFinancialAmendmentView.fromJson({
        'id': 'a2',
        'financial_ceiling_cents': null,
        'penalty_multiplier_bps': 10000,
        'effective_at_utc': '2026-06-01T12:00:00Z',
        'amended_at_utc': '2026-06-01T12:00:00Z',
        'notes': null,
      });

      expect(view.financialCeilingCents, isNull);
      expect(view.penaltyMultiplierLabel, '1.00x');
      expect(view.notes, isNull);
    });
  });

  group('ContractAmendmentsTimeline', () {
    testWidgets(
      'renders nodes: newest tagged VIGENTE, multiplier and ceiling',
      (tester) async {
        final amendments = [
          _amendment(
            id: 'a1',
            ceilingCents: 5000000,
            bps: 15000,
            effectiveAt: DateTime.utc(2026, 6, 1),
            notes: 'Renegociação Q2',
          ),
          _amendment(
            id: 'a2',
            ceilingCents: null,
            bps: 10000,
            effectiveAt: DateTime.utc(2026, 1, 1),
          ),
        ];

        await tester.pumpWidget(
          _host([
            contractFinancialAmendmentsProvider(
              _contractId,
            ).overrideWith((ref) async => amendments),
          ]),
        );
        await tester.pumpAndSettle();

        expect(find.text('Histórico de Aditivos Financeiros'), findsOneWidget);
        // Only the newest amendment is current.
        expect(find.text('VIGENTE'), findsOneWidget);
        expect(find.text('1.50x'), findsOneWidget);
        expect(find.text('1.00x'), findsOneWidget);
        // One node has no ceiling.
        expect(find.text('Sem teto'), findsOneWidget);
        expect(find.text('Renegociação Q2'), findsOneWidget);
      },
    );

    testWidgets('empty history shows the empty message', (tester) async {
      await tester.pumpWidget(
        _host([
          contractFinancialAmendmentsProvider(
            _contractId,
          ).overrideWith((ref) async => const []),
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhum aditivo financeiro registrado.'),
        findsOneWidget,
      );
    });

    testWidgets('error surfaces a domain-language message, not the exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([
          contractFinancialAmendmentsProvider(
            _contractId,
          ).overrideWith((ref) async => throw StateError('boom')),
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível carregar o histórico de aditivos.'),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
    });
  });
}
