import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import 'package:veraprob/state/providers/fleet_providers.dart';

enum FeedHealthStatus { online, degraded, offline }

class FeedHealthProjection {
  final FeedHealthStatus status;
  final int currentDelayMs;
  final int activeVehicles;

  const FeedHealthProjection({
    required this.status,
    required this.currentDelayMs,
    required this.activeVehicles,
  });

  String get label {
    switch (status) {
      case FeedHealthStatus.online:
        return 'Online ($currentDelayMs ms)';
      case FeedHealthStatus.degraded:
        return 'Latência Alta ($currentDelayMs ms)';
      case FeedHealthStatus.offline:
        return 'Offline';
    }
  }

  Color get color {
    switch (status) {
      case FeedHealthStatus.online:
        return const Color(0xFF00C853);
      case FeedHealthStatus.degraded:
        return const Color(0xFFFF9100);
      case FeedHealthStatus.offline:
        return const Color(0xFFFF1744);
    }
  }
}

/// Computes the overall health of the real-time telemetry feed.
final feedHealthProjectionProvider = Provider<FeedHealthProjection>((ref) {
  final positionsAsync = ref.watch(normalizedStateProvider);

  if (!positionsAsync.hasValue || positionsAsync.value!.isEmpty) {
    return const FeedHealthProjection(
      status: FeedHealthStatus.offline,
      currentDelayMs: 0,
      activeVehicles: 0,
    );
  }

  final states = positionsAsync.value!;

  DateTime? latestPing;
  for (final state in states) {
    if (latestPing == null || state.lastRawPingAt.isAfter(latestPing)) {
      latestPing = state.lastRawPingAt;
    }
  }

  if (latestPing == null) {
    return FeedHealthProjection(
      status: FeedHealthStatus.offline,
      currentDelayMs: 0,
      activeVehicles: states.length,
    );
  }

  final delayMs = DateTime.now().toUtc().difference(latestPing).inMilliseconds;
  final boundedDelay = delayMs < 0 ? 0 : delayMs;

  FeedHealthStatus status = FeedHealthStatus.online;
  if (boundedDelay > 2000) {
    status = FeedHealthStatus.degraded;
  }
  if (boundedDelay > 10000) {
    status = FeedHealthStatus.offline;
  }

  return FeedHealthProjection(
    status: status,
    currentDelayMs: boundedDelay,
    activeVehicles: states.length,
  );
});
