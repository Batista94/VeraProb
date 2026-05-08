import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/domain/sla_audit/operational_alert.dart';
import 'package:veraprob/state/providers/alert_providers.dart';

/// Creates a minimal [OperationalAlert] fixture for testing.
OperationalAlert _makeAlert({
  String id = 'alert-1',
  String organizationId = 'org-1',
  String severity = 'CRITICAL',
  String status = 'ACTIVE',
}) {
  return OperationalAlert(
    id: id,
    organizationId: organizationId,
    entityId: 'entity-1',
    contractId: 'contract-1',
    alertType: 'SLA_BREACH',
    severity: severity,
    triggeredAtUtc: DateTime.utc(2026, 5, 20, 14, 30),
    status: status,
  );
}

/// Validates: Requirements 8.2
///
/// Verifies that [ActiveAlertsNotifier.updateShouldNotify] always returns
/// `true`, ensuring every stream emission triggers a rebuild in listeners
/// regardless of equality.
void main() {
  group('ActiveAlertsNotifier updateShouldNotify always-notify (Req 8.2)', () {
    test('updateShouldNotify returns true for identical values', () {
      final notifier = ActiveAlertsNotifier();
      final alerts = [_makeAlert()];
      final previous = AsyncData(alerts);
      final next = AsyncData(alerts);

      expect(notifier.updateShouldNotify(previous, next), isTrue);
    });

    test(
      'updateShouldNotify returns true for equal but different instances',
      () {
        final notifier = ActiveAlertsNotifier();
        final alertsA = [_makeAlert(id: 'alert-1')];
        final alertsB = [_makeAlert(id: 'alert-1')];

        // Verify they are equal by ==
        expect(alertsA, equals(alertsB));

        final previous = AsyncData(alertsA);
        final next = AsyncData(alertsB);

        // Despite equality, should still notify
        expect(notifier.updateShouldNotify(previous, next), isTrue);
      },
    );

    test('updateShouldNotify returns true for different values', () {
      final notifier = ActiveAlertsNotifier();
      final previous = AsyncData([_makeAlert(id: 'alert-1')]);
      final next = AsyncData([_makeAlert(id: 'alert-2')]);

      expect(notifier.updateShouldNotify(previous, next), isTrue);
    });

    test('updateShouldNotify returns true for empty lists', () {
      final notifier = ActiveAlertsNotifier();
      const previous = AsyncData(<OperationalAlert>[]);
      const next = AsyncData(<OperationalAlert>[]);

      expect(notifier.updateShouldNotify(previous, next), isTrue);
    });

    test('updateShouldNotify returns true for loading to data transition', () {
      final notifier = ActiveAlertsNotifier();
      const previous = AsyncLoading<List<OperationalAlert>>();
      final next = AsyncData([_makeAlert()]);

      expect(notifier.updateShouldNotify(previous, next), isTrue);
    });

    test('updateShouldNotify returns true for error to data transition', () {
      final notifier = ActiveAlertsNotifier();
      final previous = AsyncError<List<OperationalAlert>>(
        Exception('network'),
        StackTrace.empty,
      );
      final next = AsyncData([_makeAlert()]);

      expect(notifier.updateShouldNotify(previous, next), isTrue);
    });

    test(
      'every emission triggers rebuild even with identical consecutive values',
      () async {
        // This test verifies the end-to-end behavior: a StreamNotifier with
        // updateShouldNotify returning true propagates every emission.
        final controller = StreamController<List<OperationalAlert>>();
        addTearDown(controller.close);

        // Override the provider with a custom build that uses our stream
        final container = ProviderContainer.test(
          overrides: [
            activeAlertsStreamProvider.overrideWithBuild(
              (ref, self) => controller.stream,
            ),
          ],
        );

        var rebuildCount = 0;
        container.listen(activeAlertsStreamProvider, (previous, next) {
          rebuildCount++;
        });

        // Force provider initialization
        container.read(activeAlertsStreamProvider);

        // Wait for stream subscription to be established
        await Future<void>.delayed(Duration.zero);

        // Emit identical lists multiple times
        final identicalAlerts = [_makeAlert(id: 'alert-1')];

        controller.add(identicalAlerts);
        await Future<void>.delayed(Duration.zero);
        final countAfterFirst = rebuildCount;

        controller.add(identicalAlerts);
        await Future<void>.delayed(Duration.zero);
        final countAfterSecond = rebuildCount;

        controller.add(identicalAlerts);
        await Future<void>.delayed(Duration.zero);
        final countAfterThird = rebuildCount;

        // Each emission should trigger a rebuild because updateShouldNotify
        // always returns true
        expect(
          countAfterSecond,
          greaterThan(countAfterFirst),
          reason:
              'Second identical emission should trigger rebuild (always-notify)',
        );
        expect(
          countAfterThird,
          greaterThan(countAfterSecond),
          reason:
              'Third identical emission should trigger rebuild (always-notify)',
        );
      },
    );
  });
}
