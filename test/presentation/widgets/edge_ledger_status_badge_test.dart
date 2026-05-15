import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/presentation/shared/ui/edge_ledger_status_badge.dart';
import 'package:veraprob/state/notifiers/connectivity_notifier.dart';
import 'package:veraprob/state/providers/local_fact_queue_providers.dart';

// ── Widget builder ────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('EdgeLedgerStatusBadge', () {
    testWidgets('shows Synced chip when count is 0 and connected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const EdgeLedgerStatusBadge(),
          overrides: [
            pendingFactCountProvider.overrideWith((_) => Stream.value(0)),
            connectivityNotifierProvider.overrideWithBuild(
              (ref, self) => EdgeLedgerConnectionState.connected,
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Synced'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('shows N buffered chip when count > 0', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EdgeLedgerStatusBadge(),
          overrides: [
            pendingFactCountProvider.overrideWith((_) => Stream.value(7)),
            connectivityNotifierProvider.overrideWithBuild(
              (ref, self) => EdgeLedgerConnectionState.connected,
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('7 buffered'), findsOneWidget);
      expect(find.byIcon(Icons.sync_outlined), findsOneWidget);
    });

    testWidgets('shows Syncing chip when connection state is syncing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const EdgeLedgerStatusBadge(),
          overrides: [
            pendingFactCountProvider.overrideWith((_) => Stream.value(3)),
            connectivityNotifierProvider.overrideWithBuild(
              (ref, self) => EdgeLedgerConnectionState.syncing,
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Syncing\u2026'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error chip when stream emits an error', (tester) async {
      // StreamController guarantees the error is enqueued before pump, so
      // the StreamProvider surfaces it as AsyncLoading.copyWithPrevious(
      // AsyncError) on first frame — handled by the widget's `hasError`
      // short-circuit ahead of the AsyncLoading branch.
      final controller = StreamController<int>();
      controller.addError(Exception('db error'));
      addTearDown(controller.close);

      await tester.pumpWidget(
        _wrap(
          const EdgeLedgerStatusBadge(),
          overrides: [
            pendingFactCountProvider.overrideWith((_) => controller.stream),
            connectivityNotifierProvider.overrideWithBuild(
              (ref, self) => EdgeLedgerConnectionState.connected,
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Sync error'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('tapping N buffered chip opens detail dialog', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EdgeLedgerStatusBadge(),
          overrides: [
            pendingFactCountProvider.overrideWith((_) => Stream.value(5)),
            connectivityNotifierProvider.overrideWithBuild(
              (ref, self) => EdgeLedgerConnectionState.connected,
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.text('5 buffered'));
      await tester.pumpAndSettle();

      expect(find.text('Edge Ledger'), findsOneWidget);
      expect(find.text('Buffered facts: 5'), findsOneWidget);
      expect(find.text('Retry Now'), findsOneWidget);
    });

    testWidgets('detail dialog close button dismisses dialog', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EdgeLedgerStatusBadge(),
          overrides: [
            pendingFactCountProvider.overrideWith((_) => Stream.value(2)),
            connectivityNotifierProvider.overrideWithBuild(
              (ref, self) => EdgeLedgerConnectionState.connected,
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.text('2 buffered'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Edge Ledger'), findsNothing);
    });
  });
}
