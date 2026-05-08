import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Extensions on [AsyncValue] to support stale-while-revalidate pattern.
///
/// **Validates: Requirements 5.5, 5.6**
///
/// In Riverpod v3, `AsyncValue` preserves previous data during refresh:
/// - `isRefreshing == true` + `value != null` → stale data available
/// - `isRefreshing == true` + `value == null` → initial load (show loading)
///
/// These extensions make it easy to check the correct state in presentation code.
extension StaleWhileRevalidateExtension<T> on AsyncValue<T> {
  /// Returns `true` when the provider is refreshing but has previous data
  /// that should remain visible to the user.
  ///
  /// Use this to determine whether to show a subtle refresh indicator
  /// (e.g., [LinearProgressIndicator]) while keeping previous data visible,
  /// instead of replacing the entire UI with a loading spinner.
  ///
  /// ```dart
  /// final asyncValue = ref.watch(someProvider);
  /// if (asyncValue.isRefreshingWithData) {
  ///   // Show subtle indicator, keep previous data visible
  /// }
  /// ```
  bool get isRefreshingWithData => isRefreshing && hasValue && value != null;

  /// Returns `true` when the provider is in its initial loading state
  /// with no previous data available.
  ///
  /// This is the ONLY case where a full loading indicator should be shown.
  /// When `isRefreshingWithData` is true, show previous data instead.
  ///
  /// If no data is received within 30 seconds, the provider transitions to
  /// `AsyncError(TimeoutException('Provider timeout after 30s'))` via
  /// `Future.timeout` (see [ProviderTimeoutExtension]).
  bool get isInitialLoading => isLoading && !hasValue;

  /// Returns the previous data if available during refresh, or `null`.
  ///
  /// Useful in `switch` patterns where you want to show stale data
  /// during refresh instead of a loading indicator:
  ///
  /// ```dart
  /// switch (asyncValue) {
  ///   case AsyncData(:final value):
  ///     return DataWidget(value);
  ///   case AsyncLoading():
  ///     final stale = asyncValue.staleData;
  ///     if (stale != null) return DataWidget(stale); // stale-while-revalidate
  ///     return LoadingWidget();
  ///   case AsyncError(:final error):
  ///     final stale = asyncValue.staleData;
  ///     if (stale != null) return DataWidget(stale); // show stale + error toast
  ///     return ErrorWidget(error);
  /// }
  /// ```
  T? get staleData => hasValue ? value : null;
}
