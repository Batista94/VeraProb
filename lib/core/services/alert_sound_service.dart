import 'package:just_audio/just_audio.dart';

/// Industrial sound feedback for CRITICAL alerts.
///
/// Plays a short ping (200ms, 880Hz) with a 3-second debounce
/// to prevent audio spam during bulk alert arrivals.
///
/// Lifecycle: managed via Riverpod provider with ref.onDispose.
class AlertSoundService {
  final AudioPlayer _player;
  DateTime _lastPlayedAt = DateTime.utc(2000);

  static const _debounceSeconds = 3;
  static const _assetPath = 'assets/sounds/industrial_ping.wav';

  AlertSoundService() : _player = AudioPlayer();

  /// Plays the industrial ping if at least [_debounceSeconds] have elapsed.
  Future<void> playAlertPing() async {
    final now = DateTime.now().toUtc();
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
