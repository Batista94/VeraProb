import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

/// Industrial sound feedback for CRITICAL alerts.
///
/// Plays a short ping (200ms, 880Hz) with a 3-second debounce
/// to prevent audio spam during bulk alert arrivals.
///
/// Lifecycle: managed via Riverpod provider with ref.onDispose.
class AlertSoundService {
  final AudioPlayer _player;
  final IDateTimeProvider _clock;
  DateTime _lastPlayedAt = DateTime.utc(2000);

  static const _debounceSeconds = 3;
  static const _assetPath = 'assets/sounds/industrial_ping.wav';

  AlertSoundService({
    @visibleForTesting AudioPlayer? player,
    @visibleForTesting IDateTimeProvider? clock,
  }) : _player = player ?? AudioPlayer(),
       _clock = clock ?? UtcDateTimeProvider();

  /// Plays the industrial ping if at least [_debounceSeconds] have elapsed.
  Future<void> playAlertPing() async {
    final now = _clock.nowUtc();
    if (now.difference(_lastPlayedAt).inSeconds < _debounceSeconds) return;
    _lastPlayedAt = now;

    try {
      await _player.setAsset(_assetPath);
      await _player.play();
    } catch (_) {
      // Non-blocking: sound failure must never crash the OCC.
    }
  }

  /// Releases native audio resources.
  Future<void> dispose() async {
    await _player.dispose();
  }
}
