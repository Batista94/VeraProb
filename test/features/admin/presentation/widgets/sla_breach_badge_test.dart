import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/features/admin/presentation/widgets/sla_breach_badge.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';

Widget _host(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: Scaffold(body: SlaBreachBadge())),
  );
}

void main() {
  testWidgets('hidden when no overdue disputes', (tester) async {
    await tester.pumpWidget(
      _host([overdueDisputesCountProvider.overrideWith((ref) => 0)]),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('sla-breach-badge')), findsNothing);
    expect(find.textContaining('SLA VENCIDO'), findsNothing);
  });

  testWidgets('renders red counter pill when breached', (tester) async {
    await tester.pumpWidget(
      _host([overdueDisputesCountProvider.overrideWith((ref) => 3)]),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('sla-breach-badge')), findsOneWidget);
    expect(find.text('SLA VENCIDO · 3'), findsOneWidget);
  });

  testWidgets('tap drills queue down to overdue disputed lane', (tester) async {
    await tester.pumpWidget(
      _host([overdueDisputesCountProvider.overrideWith((ref) => 2)]),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SlaBreachBadge)),
    );
    // Pin the autoDispose drill-down providers so the tap's state survives the
    // read (otherwise each listener-less read rebuilds a fresh instance).
    final subA = container.listen(disputeOverdueOnlyProvider, (_, _) {});
    final subB = container.listen(auditorQueueFilterProvider, (_, _) {});
    addTearDown(subA.close);
    addTearDown(subB.close);

    expect(subA.read(), isFalse);
    expect(subB.read(), AuditorQueueFilter.pending);

    await tester.tap(find.byKey(const ValueKey('sla-breach-badge')));
    await tester.pump();

    expect(subA.read(), isTrue);
    expect(subB.read(), AuditorQueueFilter.disputed);
  });
}
