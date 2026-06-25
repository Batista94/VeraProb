import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A widget that correctly implements stale-while-revalidate for [AsyncValue].
///
/// **Validates: Requirements 5.5, 5.6**
///
/// Behavior:
/// - When `isRefreshing == true` AND previous data exists (`value != null`):
///   Shows the previous data with an optional subtle refresh indicator.
///   Zero intermediate rebuilds with Loading state visible to user.
///
/// - When `isRefreshing == true` AND no previous data exists (`value == null`):
///   Shows the loading widget until first data arrives or error occurs.
///   If no data received in 30s, the provider transitions to
///   `AsyncError(TimeoutException('Provider timeout after 30s'))`.
///
/// This widget encapsulates the Riverpod v3 stale-while-revalidate pattern
/// so that consumers don't accidentally show loading spinners during refresh.
class AsyncValueWidget<T> extends StatelessWidget {
  const AsyncValueWidget({
    super.key,
    required this.asyncValue,
    required this.data,
    this.loading,
    this.error,
    this.showRefreshIndicator = true,
  });

  /// The [AsyncValue] to render.
  final AsyncValue<T> asyncValue;

  /// Builder for the data state. Called with the current value.
  /// Also called during refresh when previous data exists (stale-while-revalidate).
  final Widget Function(T data) data;

  /// Optional custom loading widget. Defaults to a centered [CircularProgressIndicator].
  final Widget Function()? loading;

  /// Optional custom error widget. Defaults to a centered error message with retry hint.
  final Widget Function(Object error, StackTrace stackTrace)? error;

  /// Whether to show a subtle [LinearProgressIndicator] at the top during refresh.
  /// Defaults to `true`.
  final bool showRefreshIndicator;

  @override
  Widget build(BuildContext context) {
    // Stale-while-revalidate: if we have previous data, show it even during
    // refresh or error. In Riverpod v3, AsyncValue preserves previous data
    // during refresh automatically.
    final staleData = asyncValue.hasValue ? asyncValue.value : null;

    // Surface errors even while the source still reports loading. A Riverpod
    // StreamProvider whose stream errors before its first emission settles as
    // `AsyncLoading(hasError: true)` — never a terminal `AsyncError` — so the
    // `switch` below would otherwise show the loading widget forever.
    if (asyncValue.hasError && staleData == null) {
      return _buildError(
        asyncValue.error!,
        asyncValue.stackTrace ?? StackTrace.empty,
      );
    }

    return switch (asyncValue) {
      // Data available (includes refresh state with previous data)
      AsyncData(:final value) => _wrapWithRefreshIndicator(
        child: data(value),
        isRefreshing: asyncValue.isRefreshing,
      ),

      // Error state — show stale data if available, otherwise error UI
      AsyncError(:final error, :final stackTrace) =>
        staleData != null
            ? _wrapWithRefreshIndicator(
                child: data(staleData),
                isRefreshing: true,
              )
            : _buildError(error, stackTrace),

      // Loading state — only show loading when NO previous data exists
      // (initial load or refresh without prior data → Requirement 5.6)
      AsyncLoading() =>
        staleData != null
            ? _wrapWithRefreshIndicator(
                child: data(staleData),
                isRefreshing: true,
              )
            : _buildLoading(),
    };
  }

  Widget _wrapWithRefreshIndicator({
    required Widget child,
    required bool isRefreshing,
  }) {
    if (!showRefreshIndicator || !isRefreshing) return child;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LinearProgressIndicator(minHeight: 2),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildLoading() {
    if (loading != null) return loading!();
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildError(Object error, StackTrace stackTrace) {
    if (this.error != null) return this.error!(error, stackTrace);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Erro: $error', textAlign: TextAlign.center),
      ),
    );
  }
}
