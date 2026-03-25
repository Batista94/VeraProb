import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart';
import 'package:veraprob/features/admin/presentation/widgets/sanction_verdict_card.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

SanctionQueueItemView _makeItem() {
  final evidence = VerdictEvidence.create(
    clauseRef: 'ATR-01',
    ruleId: 'rule-001',
    ruleVersion: 1,
    primaryEvidenceLat: -23.5,
    primaryEvidenceLng: -46.6,
    primaryEvidenceTimestampUtc: DateTime.utc(2026, 1, 15, 10, 0),
    deltaValue: 5.0,
    thresholdValue: 0.0,
    fineCents: const Money(150000),
    confidenceScore: 95,
  );
  return SanctionQueueItemView(
    id: 'test-id-001',
    organizationId: 'org-001',
    ledgerEntryId: 'ledger-001',
    setId: 'set-001',
    contractId: 'contract-001',
    verdictEvidence: evidence,
    status: SanctionReviewStatus.pending,
    createdAtUtc: DateTime.utc(2026, 1, 15, 10, 0),
  );
}

Widget _buildCard(SanctionQueueItemView item) {
  return ProviderScope(
    overrides: [
      contractNameProvider.overrideWith((ref, id) async => 'Test Contract'),
      pendingSanctionsStreamProvider.overrideWith(
        (ref) => Stream.value([item]),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: SanctionVerdictCard(item: item)),
      ),
    ),
  );
}

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('SanctionVerdictCard', () {
    testWidgets('renders fine amount and clause badge', (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(find.text('R\$ 1.500,00'), findsOneWidget);
      expect(find.text('ATR-01'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('shows VALIDAR and REJEITAR buttons', (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      expect(find.text('VALIDAR'), findsOneWidget);
      expect(find.text('REJEITAR'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });

    testWidgets('tapping REJEITAR reveals rejection reason field', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(_buildCard(_makeItem()));
      await tester.pump();

      // Rejection field should not be visible before tap
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('REJEITAR'));
      await tester.pump();

      // Rejection reason text field appears after tap
      expect(find.byType(TextField), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
    });
  });
}
