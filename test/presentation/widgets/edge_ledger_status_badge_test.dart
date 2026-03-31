import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/presentation/widgets/edge_ledger_status_badge.dart';
import 'package:veraprob/state/notifiers/connectivity_notifier.dart';
import 'package:veraprob/state/providers/local_fact_queue_providers.dart';

// ── Fake notifier ──────────────────────────────────────────────────────────────

class _FakeConnectivityNotifier extends ConnectivityNotifier {
  final EdgeLedgerConnectionState _initial;
  _FakeConnectivityNotifier(this._initial);

  @override
  EdgeLedgerConnectionState build() => _initial;
}

// ── Widget builder ────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('EdgeLedgerStatusBadge', () {
    testWidgets('shows Synced chip when count is 0 and connected',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EdgeLedgerStatusBadge(),
          overrides: [
            pendingFactCountProvider.overrideWith((_) => Stream.value(0)),
            connectivityNotifierProvider.overrideWith(
              _FakeConnectivityNotifier.new.callWith(
                  EdgeLedgerConnectionState.connected),
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
            connectivityNotifierProvider.overrideWith(
              _FakeConnectivityNotifier.new.callWith(
                  EdgeLedgerConnectionState.connected),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('7 buffered'), findsOneWidget);
      expect(find.byIcon(Icons.sync_outlined), findsOneWidget);
    });

    testWidgets('shows Syncing chip when connection state is syncing',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EdgeLedgerStatusBadge(),
          overrides: [
            pendingFactCountProvider.overrideWith((_) => Stream.value(3)),
            connectivityNotifierProvider.overrideWith(
              _FakeConnectivityNotifier.new.callWith(
                  EdgeLedgerConnectionState.syncing),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Syncing\u2026'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error chip when stream emits an error', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EdgeLedgerStatusBadge(),
          overrides: [
            pendingFactCountProvider.overrideWith(
              (_) => Stream.error(Exception('db error')),
            ),
            connectivityNotifierProvider.overrideWith(
              _FakeConnectivityNotifier.new.callWith(
                  EdgeLedgerConnectionState.connected),
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
            connectivityNotifierProvider.overrideWith(
              _FakeConnectivityNotifier.new.callWith(
                  EdgeLedgerConnectionState.connected),
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
            connectivityNotifierProvider.overrideWith(
              _FakeConnectivityNotifier.new.callWith(
                  EdgeLedgerConnectionState.connected),
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

// ── Extension helper ───────────────────────────────────────────────────────────

extension on _FakeConnectivityNotifier Function(EdgeLedgerConnectionState) {
  ConnectivityNotifier Function() callWith(EdgeLedgerConnectionState s) =>
      () => this(s);
}
