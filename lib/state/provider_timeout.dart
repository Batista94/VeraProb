import 'dart:async';

/// Default timeout for providers that make network calls without prior data.
///
/// **Validates: Requirement 5.6**
///
/// When a provider is in its initial load (no previous data), if no response
/// is received within this duration, the provider transitions to
/// `AsyncError(TimeoutException('Provider timeout after 30s'))`.
///
/// This prevents indefinite loading states in the UI and allows the
/// presentation layer to show an error with retry option.
const kProviderTimeout = Duration(seconds: 30);

/// Extension on [Future] to apply the standard provider timeout.
///
/// Usage inside a FutureProvider or AsyncNotifier build:
/// ```dart
/// final data = await service.fetchData().withProviderTimeout();
/// ```
///
/// Stale-while-revalidate note (Requirement 5.5):
/// In Riverpod v3, when a provider refreshes and has previous data
/// (`value != null`), the previous data remains accessible via `.value`
/// without transitioning to a visible Loading state. This is the DEFAULT
/// behavior — no explicit configuration is needed. The exhaustive `switch`
/// on AsyncValue shows previous data during refresh automatically.
///
/// This timeout only affects the initial load scenario where no previous
/// data exists, preventing the UI from showing a loading indicator forever.
extension ProviderTimeoutExtension<T> on Future<T> {
  /// Wraps this future with the standard 30-second provider timeout.
  ///
  /// Throws [TimeoutException] with message 'Provider timeout after 30s'
  /// if the future does not complete within [kProviderTimeout].
  Future<T> withProviderTimeout() {
    return timeout(
      kProviderTimeout,
      onTimeout: () => throw TimeoutException(
        'Provider timeout after 30s',
        kProviderTimeout,
      ),
    );
  }
}
