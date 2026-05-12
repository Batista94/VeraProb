import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Circuit Breaker Configuration ────────────────────────────────────────────

/// Injectable cooldown duration. Override with `Duration.zero` in tests.
final proxyResilienceCooldownProvider = Provider<Duration>(
  (_) => const Duration(seconds: 30),
);

/// Max consecutive failures before circuit opens (Unavailable).
final proxyResilienceThresholdProvider = Provider<int>((_) => 3);

// ── State ────────────────────────────────────────────────────────────────────

enum ResilienceStatus { healthy, degraded, unavailable }

class ProxyResilienceState {
  final ResilienceStatus status;
  final int consecutiveFailures;
  final DateTime? lastFailureAt;

  const ProxyResilienceState({
    this.status = ResilienceStatus.healthy,
    this.consecutiveFailures = 0,
    this.lastFailureAt,
  });

  bool get canWrite => status == ResilienceStatus.healthy;
  bool get isStale => status != ResilienceStatus.healthy;

  ProxyResilienceState copyWith({
    ResilienceStatus? status,
    int? consecutiveFailures,
    DateTime? lastFailureAt,
  }) {
    return ProxyResilienceState(
      status: status ?? this.status,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      lastFailureAt: lastFailureAt ?? this.lastFailureAt,
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class ProxyResilienceNotifier extends Notifier<ProxyResilienceState> {
  Timer? _cooldownTimer;

  @override
  ProxyResilienceState build() {
    ref.onDispose(_cancelTimer);
    return const ProxyResilienceState();
  }

  /// Record a proxy failure. After threshold, enters Unavailable.
  void recordFailure() {
    final threshold = ref.read(proxyResilienceThresholdProvider);
    final newCount = state.consecutiveFailures + 1;

    if (newCount >= threshold) {
      state = state.copyWith(
        status: ResilienceStatus.unavailable,
        consecutiveFailures: newCount,
        lastFailureAt: DateTime.now().toUtc(),
      );
      _startCooldown();
    } else {
      state = state.copyWith(
        status: ResilienceStatus.degraded,
        consecutiveFailures: newCount,
        lastFailureAt: DateTime.now().toUtc(),
      );
    }
  }

  /// Record a successful proxy call. Resets circuit breaker.
  void recordSuccess() {
    _cancelTimer();
    state = const ProxyResilienceState();
  }

  /// Explicit reset (INV-22: called on logout to prevent cross-session leak).
  void reset() {
    _cancelTimer();
    state = const ProxyResilienceState();
  }

  void _startCooldown() {
    _cancelTimer();
    final cooldown = ref.read(proxyResilienceCooldownProvider);
    if (cooldown == Duration.zero) return;
    _cooldownTimer = Timer(cooldown, () {
      // After cooldown, allow one retry (move to degraded).
      state = state.copyWith(
        status: ResilienceStatus.degraded,
        consecutiveFailures: state.consecutiveFailures,
      );
    });
  }

  void _cancelTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final proxyResilienceProvider =
    NotifierProvider<ProxyResilienceNotifier, ProxyResilienceState>(
      ProxyResilienceNotifier.new,
    );
