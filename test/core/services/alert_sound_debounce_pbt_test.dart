import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll, setUp, tearDown, any;
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/infrastructure/audio/alert_sound_service.dart';

import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

/// **Validates: Requirements 6.2**
///
/// Property 7: Alert sound debounce invariant
///
/// For any sequence of N calls to `AlertSoundService.playAlertPing()` within
/// a 3-second window (N ≥ 2), the underlying `AudioPlayer.play()` SHALL be
/// invoked exactly once (the first call), and subsequent calls within the
/// debounce window SHALL be no-ops.

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAudioPlayer extends Mock implements AudioPlayer {}

// ── Test ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Generator: number of calls within the debounce window (N ≥ 2, up to 50)
  final callCountGen = Any().intInRange(2, 51);

  late MockAudioPlayer mockPlayer;
  late FakeDateTimeProvider fakeClock;
  late AlertSoundService service;

  setUp(() {
    mockPlayer = MockAudioPlayer();
    fakeClock = FakeDateTimeProvider(DateTime.utc(2026, 5, 10, 12, 0, 0));

    // Stub AudioPlayer methods to complete successfully
    when(
      () => mockPlayer.setAsset(any()),
    ).thenAnswer((_) async => const Duration(milliseconds: 200));
    when(() => mockPlayer.play()).thenAnswer((_) async {});
    when(() => mockPlayer.dispose()).thenAnswer((_) async {});

    service = AlertSoundService(player: mockPlayer, clock: fakeClock);
  });

  tearDown(() async {
    await service.dispose();
  });

  group('Feature: dependency-upgrade-phase3, '
      'Property 7: Alert sound debounce invariant', () {
    // ── PBT using Glados ────────────────────────────────────────────────────
    //
    // Core property: For N≥2 calls within a 3-second window, play() is
    // invoked exactly once. Uses a play counter for deterministic assertions
    // compatible with Glados's determinism verification.

    Glados(callCountGen).test(
      'PBT: N≥2 calls within 3-second window invoke AudioPlayer.play() '
      'exactly once',
      (n) async {
        var playCount = 0;

        final player = MockAudioPlayer();
        when(
          () => player.setAsset(any()),
        ).thenAnswer((_) async => const Duration(milliseconds: 200));
        when(() => player.play()).thenAnswer((_) async {
          playCount++;
        });
        when(() => player.dispose()).thenAnswer((_) async {});

        final clock = FakeDateTimeProvider(DateTime.utc(2026, 5, 10, 12, 0, 0));
        final svc = AlertSoundService(player: player, clock: clock);

        // Make N calls within the 3-second debounce window.
        // Space them evenly within 2.9 seconds to stay within the window.
        // Max total elapsed = (N-1) * interval.
        // With interval = 2900 ~/ max(N-1, 1), total ≤ 2900ms < 3000ms.
        final intervalMs = 2900 ~/ max(n - 1, 1);

        for (var i = 0; i < n; i++) {
          await svc.playAlertPing();
          if (i < n - 1) {
            clock.advance(Duration(milliseconds: intervalMs));
          }
        }

        // Property: play() invoked exactly once (the first call)
        expect(
          playCount,
          equals(1),
          reason: 'For $n calls within 3s, play() must be invoked once',
        );

        await svc.dispose();
      },
    );

    // ── Pre-generated iteration for debounce expiry property ─────────────────
    // Glados.test uses package:test's `test` which can have determinism issues
    // with multi-phase async tests. We pre-generate values and iterate with
    // standard `test()` to ensure minimum 100 iterations (same pattern as
    // super_admin_guard_pbt_test.dart).

    final random = Random(42);
    const iterations = 100;
    final preGeneratedCounts = List.generate(
      iterations,
      (_) => random.nextInt(49) + 2, // N ∈ [2, 50]
    );

    for (var i = 0; i < iterations; i++) {
      final n = preGeneratedCounts[i];
      test('PBT iter[$i]: after debounce window expires with N=$n calls, '
          'next call triggers play() again', () async {
        var playCount = 0;

        final player = MockAudioPlayer();
        when(
          () => player.setAsset(any()),
        ).thenAnswer((_) async => const Duration(milliseconds: 200));
        when(() => player.play()).thenAnswer((_) async {
          playCount++;
        });
        when(() => player.dispose()).thenAnswer((_) async {});

        final clock = FakeDateTimeProvider(DateTime.utc(2026, 5, 10, 12, 0, 0));
        final svc = AlertSoundService(player: player, clock: clock);

        // First call — should trigger play()
        await svc.playAlertPing();
        expect(playCount, equals(1), reason: 'First call must trigger play()');

        // N-1 calls within the debounce window — all should be no-ops.
        // Use intervals that keep total elapsed time under 3 seconds.
        final intervalMs = (2900 ~/ max(n, 2)).clamp(1, 2900);
        for (var j = 1; j < n; j++) {
          clock.advance(Duration(milliseconds: intervalMs));
          await svc.playAlertPing();
        }

        // Still only 1 call total (no additional invocations)
        expect(
          playCount,
          equals(1),
          reason: 'Calls within debounce window must be no-ops',
        );

        // Advance past the 3-second debounce window
        clock.advance(const Duration(seconds: 4));

        // Next call after debounce expires — should trigger play() again
        await svc.playAlertPing();
        expect(
          playCount,
          equals(2),
          reason: 'Call after debounce expires must trigger play() again',
        );

        await svc.dispose();
      });
    }

    // ── Deterministic edge-case tests ────────────────────────────────────────

    test('exactly 2 calls within 3s: play() invoked once', () async {
      await service.playAlertPing();
      fakeClock.advance(const Duration(seconds: 1));
      await service.playAlertPing();

      verify(() => mockPlayer.play()).called(1);
    });

    test(
      'call at exactly 2-second mark is still debounced (inSeconds < 3)',
      () async {
        await service.playAlertPing();
        fakeClock.advance(const Duration(seconds: 2));
        await service.playAlertPing();

        verify(() => mockPlayer.play()).called(1);
      },
    );

    test('call at 3-second mark passes debounce (inSeconds >= 3)', () async {
      await service.playAlertPing();
      fakeClock.advance(const Duration(seconds: 3));
      await service.playAlertPing();

      verify(() => mockPlayer.play()).called(2);
    });

    test('rapid-fire 10 calls with no time advancement: play() once', () async {
      for (var i = 0; i < 10; i++) {
        await service.playAlertPing();
      }

      verify(() => mockPlayer.play()).called(1);
    });
  });
}
