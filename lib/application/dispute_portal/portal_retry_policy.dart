/// Backoff policy for retryable dispute-portal submission failures.
///
/// Only genuine infrastructure unavailability (edge-function 503, transient
/// transport, storage 5xx) is retried; business rejections (INV-26) are surfaced
/// immediately as opaque non-retryable failures. Injected via a provider so tests
/// can substitute a zero-delay policy.
class PortalRetryPolicy {
  /// Total attempts including the first. `1` disables retrying.
  final int maxAttempts;

  /// Base gap before the first retry; doubles each subsequent attempt.
  final Duration baseDelay;

  const PortalRetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 600),
  });

  /// Exponential backoff gap to wait AFTER the (1-based) [attempt] that failed,
  /// before the next attempt: 600ms, 1.2s, 2.4s, …
  Duration delayAfterAttempt(int attempt) => baseDelay * (1 << (attempt - 1));

  /// No-wait policy for deterministic tests (retry orchestration without sleeps).
  static const PortalRetryPolicy zeroDelay = PortalRetryPolicy(
    baseDelay: Duration.zero,
  );
}
