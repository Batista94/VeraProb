import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/admin/quota_warning.dart';
import 'package:veraprob/features/admin/presentation/widgets/upgrade_nudge_banner.dart';
import 'package:veraprob/state/providers/admin_providers.dart';

Widget _wrap(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(home: Scaffold(body: UpgradeNudgeBanner())),
);

QuotaWarning _warning({required int threshold}) => QuotaWarning(
  id: 1,
  organizationId: 'org-1',
  resource: 'Contratos',
  usagePct: threshold,
  threshold: threshold,
  currentCount: threshold,
  maxAllowed: 100,
  triggeredAt: DateTime.utc(2026, 1, 1),
);

void main() {
  group('UpgradeNudgeBanner', () {
    testWidgets('renders nothing when warning list is empty', (tester) async {
      await tester.pumpWidget(
        _wrap([activeQuotaWarningsProvider.overrideWith((_) async => [])]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('renders critical banner when threshold >= 90', (tester) async {
      final warning = _warning(threshold: 90);
      await tester.pumpWidget(
        _wrap([
          activeQuotaWarningsProvider.overrideWith((_) async => [warning]),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Atenção:'), findsOneWidget);
    });

    testWidgets('renders urgent banner when threshold >= 80 and < 90', (
      tester,
    ) async {
      final warning = _warning(threshold: 80);
      await tester.pumpWidget(
        _wrap([
          activeQuotaWarningsProvider.overrideWith((_) async => [warning]),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Aviso:'), findsOneWidget);
    });
  });
}
