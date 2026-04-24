import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:veraprob/core/theme/app_theme.dart';

/// Forensic audio player with deterministic waveform, speed control, and seeker.
///
/// Waveform bars are generated from [forensicHash] bytes (INV-15: deterministic).
/// Uses [just_audio] for OGG Opus playback via HTML5 `<audio>` on web (INV-17).
class ForensicAudioPlayer extends ConsumerStatefulWidget {
  final String audioUrl;
  final String forensicHash;
  final Map<String, String>? httpHeaders;

  const ForensicAudioPlayer({
    super.key,
    required this.audioUrl,
    required this.forensicHash,
    this.httpHeaders,
  });

  @override
  ConsumerState<ForensicAudioPlayer> createState() =>
      _ForensicAudioPlayerState();
}

class _ForensicAudioPlayerState extends ConsumerState<ForensicAudioPlayer> {
  late final AudioPlayer _player;
  late final List<double> _bars;

  static const _speeds = [1.0, 1.5, 2.0];
  int _speedIndex = 0;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _bars = _generateBars(widget.forensicHash);
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _player.setUrl(widget.audioUrl, headers: widget.httpHeaders);
    } catch (_) {
      // Non-blocking: player shows error state via stream
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Deterministic waveform from forensic hash (INV-15).
  /// Each pair of hex chars → bar height 0.2–1.0.
  static List<double> _generateBars(String hash) {
    final bars = <double>[];
    for (var i = 0; i + 1 < hash.length && bars.length < 32; i += 2) {
      final byte = int.tryParse(hash.substring(i, i + 2), radix: 16) ?? 128;
      bars.add(0.2 + (byte / 255) * 0.8);
    }
    // Pad to 32 bars minimum
    while (bars.length < 32) {
      bars.add(0.3);
    }
    return bars;
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _cycleSpeed() {
    setState(() {
      _speedIndex = (_speedIndex + 1) % _speeds.length;
    });
    _player.setSpeed(_speeds[_speedIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Waveform ──
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, posSnap) {
              final pos = posSnap.data ?? Duration.zero;
              final dur = _player.duration ?? Duration.zero;
              final progress = dur.inMilliseconds > 0
                  ? pos.inMilliseconds / dur.inMilliseconds
                  : 0.0;
              return CustomPaint(
                size: const Size(double.infinity, 40),
                painter: _WaveformPainter(
                  bars: _bars,
                  progress: progress,
                  activeColor: VeraProbColors.primary,
                  inactiveColor: VeraProbColors.border,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // ── Controls row ──
          Row(
            children: [
              // Play/Pause
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, snap) {
                  final state = snap.data;
                  final playing = state?.playing ?? false;
                  final completed =
                      state?.processingState == ProcessingState.completed;
                  return IconButton(
                    icon: Icon(
                      completed || !playing
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      color: VeraProbColors.primary,
                    ),
                    iconSize: 28,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      if (completed) {
                        await _player.seek(Duration.zero);
                        await _player.play();
                      } else if (playing) {
                        await _player.pause();
                      } else {
                        await _player.play();
                      }
                    },
                  );
                },
              ),
              // Seeker
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  builder: (context, posSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    final dur = _player.duration ?? Duration.zero;
                    return SliderTheme(
                      data: const SliderThemeData(
                        thumbShape: RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                        trackHeight: 2,
                        activeTrackColor: VeraProbColors.primary,
                        inactiveTrackColor: VeraProbColors.border,
                        thumbColor: VeraProbColors.primary,
                      ),
                      child: Slider(
                        value: dur.inMilliseconds > 0
                            ? pos.inMilliseconds
                                  .clamp(0, dur.inMilliseconds)
                                  .toDouble()
                            : 0,
                        max: dur.inMilliseconds > 0
                            ? dur.inMilliseconds.toDouble()
                            : 1,
                        onChanged: (v) {
                          _player.seek(Duration(milliseconds: v.round()));
                        },
                      ),
                    );
                  },
                ),
              ),
              // Duration
              StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, posSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = _player.duration ?? Duration.zero;
                  return Text(
                    '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                    style: VeraProbTypography.caption.copyWith(
                      fontFamily: 'monospace',
                      color: VeraProbColors.textSecondary,
                      fontSize: 10,
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              // Speed toggle
              GestureDetector(
                onTap: _cycleSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: VeraProbColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_speeds[_speedIndex]}x',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: VeraProbColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Deterministic waveform painter — bars from forensic hash (INV-15).
class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final barWidth = size.width / (bars.length * 2 - 1);
    final activePaint = Paint()..color = activeColor;
    final inactivePaint = Paint()..color = inactiveColor;

    for (var i = 0; i < bars.length; i++) {
      final x = i * barWidth * 2;
      final barHeight = bars[i] * size.height;
      final y = (size.height - barHeight) / 2;
      final isActive = (i / bars.length) <= progress;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(1.5),
        ),
        isActive ? activePaint : inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.bars != bars;
}
