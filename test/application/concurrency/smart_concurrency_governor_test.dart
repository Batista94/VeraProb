import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/concurrency/smart_concurrency_governor.dart';

void main() {
  group('SmartConcurrencyGovernor — FIFO semaphore', () {
    test(
      'caps concurrency at maxConcurrent (10) across 20 simultaneous tasks',
      () async {
        final governor = SmartConcurrencyGovernor(maxConcurrent: 10);
        final gate = <Completer<void>>[
          for (var i = 0; i < 20; i++) Completer(),
        ];

        var peakInFlight = 0;
        var currentInFlight = 0;

        final futures = <Future<int>>[];
        for (var i = 0; i < 20; i++) {
          futures.add(
            governor.run<int>(() async {
              currentInFlight++;
              if (currentInFlight > peakInFlight) {
                peakInFlight = currentInFlight;
              }
              await gate[i].future;
              currentInFlight--;
              return i;
            }),
          );
        }

        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(governor.inFlightCount, 10);
        expect(governor.queuedCount, 10);

        for (final c in gate) {
          c.complete();
        }

        final results = await Future.wait(futures);
        expect(results.length, 20);
        expect(peakInFlight, lessThanOrEqualTo(10));
        expect(peakInFlight, 10);
        expect(governor.inFlightCount, 0);
        expect(governor.queuedCount, 0);
      },
    );

    test('preserves FIFO order when queued tasks are released', () async {
      final governor = SmartConcurrencyGovernor(maxConcurrent: 2);
      final blockers = <Completer<void>>[
        Completer(),
        Completer(),
        Completer(),
        Completer(),
        Completer(),
      ];
      final completionOrder = <int>[];

      Future<void> submit(int id) => governor.run<void>(() async {
        await blockers[id].future;
        completionOrder.add(id);
      });

      final futures = [for (var i = 0; i < 5; i++) submit(i)];

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(governor.inFlightCount, 2);
      expect(governor.queuedCount, 3);

      blockers[0].complete();
      blockers[1].complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      blockers[2].complete();
      blockers[3].complete();
      blockers[4].complete();

      await Future.wait(futures);
      expect(completionOrder, [0, 1, 2, 3, 4]);
    });

    test('releases slot even when task throws', () async {
      final governor = SmartConcurrencyGovernor(maxConcurrent: 1);

      await expectLater(
        governor.run<void>(() async {
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      expect(governor.inFlightCount, 0);
      expect(governor.queuedCount, 0);

      final result = await governor.run<int>(() async => 42);
      expect(result, 42);
    });

    test('assert rejects maxConcurrent <= 0', () {
      expect(
        () => SmartConcurrencyGovernor(maxConcurrent: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => SmartConcurrencyGovernor(maxConcurrent: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
