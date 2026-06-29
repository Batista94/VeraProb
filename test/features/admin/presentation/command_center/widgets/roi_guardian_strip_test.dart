import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/roi_guardian_strip.dart';
import 'package:veraprob/state/providers/forensic_ledger_providers.dart';

Widget _buildWith(Stream<RoiSummary?> stream) {
  return ProviderScope(
    overrides: [roiSummaryProvider.overrideWith((_) => stream)],
    child: const MaterialApp(home: Scaffold(body: RoiGuardianStrip())),
  );
}

void main() {
  group('RoiGuardianStrip', () {
    testWidgets('shows loading indicator while stream has no data', (
      tester,
    ) async {
      await tester.pumpWidget(_buildWith(const Stream.empty()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders metrics when data is present', (tester) async {
      const summary = RoiSummary(
        recoveredTrips: 5,
        totalRecoveredCents: 100000,
        totalAvoidedPenaltyCents: 50000,
        totalLinkedTrips: 12,
        pendingOrphans: 0,
      );
      await tester.pumpWidget(_buildWith(Stream.value(summary)));
      await tester.pumpAndSettle();
      expect(find.textContaining('RECEITA RECUPERADA'), findsOneWidget);
    });

    testWidgets('renders nothing when data is null', (tester) async {
      await tester.pumpWidget(_buildWith(Stream.value(null)));
      await tester.pumpAndSettle();
      expect(find.textContaining('RECEITA RECUPERADA'), findsNothing);
    });
  });
}
