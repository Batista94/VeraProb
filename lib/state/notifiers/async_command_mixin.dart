import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mixin providing the canonical `executeCommand<T>` pattern for async
/// notifiers that manage composite state with a `status` field.
///
/// **INV-15 Compliance:** Every state mutation after an `await` is guarded
/// by `ref.mounted` to prevent mutations on disposed providers.
///
/// **INV-33 Compliance:** Uses `ref.keepAlive()` to prevent premature
/// disposal during in-flight operations, with guaranteed `close()` in
/// the `finally` block.
///
/// ## Usage
///
/// ```dart
/// class MyCommandNotifier extends Notifier<MyState>
///     with AsyncCommandMixin<MyState> {
///   @override
///   MyState build() => const MyState();
///
///   Future<Result?> doSomething() => executeCommand(
///     getStatus: () => state.status,
///     setLoading: () => state = state.copyWith(status: const AsyncLoading()),
///     setData: (result) => state = state.copyWith(status: AsyncData(result)),
///     setError: (e, st) => state = state.copyWith(status: AsyncError(e, st)),
///     operation: () => someAsyncOperation(),
///   );
/// }
/// ```
mixin AsyncCommandMixin<S> on Notifier<S> {
  /// Executes an async command with full lifecycle management:
  ///
  /// 1. Acquires `ref.keepAlive()` to prevent disposal during operation
  /// 2. Sets state to loading via [setLoading]
  /// 3. Awaits [operation]
  /// 4. Guards `ref.mounted` before any post-await state mutation
  /// 5. Sets state to data or error via [setData] / [setError]
  /// 6. Releases keepAlive in `finally` block
  ///
  /// Returns the operation result on success, or `null` if the provider
  /// was disposed during the operation or an error occurred.
  Future<T?> executeCommand<T>({
    required void Function() setLoading,
    required void Function(T result) setData,
    required void Function(Object error, StackTrace stackTrace) setError,
    required Future<T> Function() operation,
  }) async {
    final keepAlive = ref.keepAlive();
    setLoading();

    try {
      final result = await operation();

      // INV-15: Guard before mutating state after await
      if (!ref.mounted) return null;

      setData(result);
      return result;
    } catch (e, st) {
      // INV-15: Guard before mutating state after await
      if (!ref.mounted) return null;

      setError(e, st);
      return null;
    } finally {
      // INV-33: Always release keepAlive to prevent memory leaks
      keepAlive.close();
    }
  }
}

/// Mixin providing a guarded async action pattern for notifiers whose
/// state IS an `AsyncValue<T>` directly (not wrapped in a composite state).
///
/// **INV-15 Compliance:** Every state mutation after an `await` is guarded
/// by `ref.mounted`.
///
/// ## Usage
///
/// ```dart
/// class MyActionNotifier extends Notifier<AsyncValue<void>>
///     with GuardedAsyncActionMixin<void> {
///   @override
///   AsyncValue<void> build() => const AsyncData(null);
///
///   Future<void> doAction() => guardedAction(
///     () => someAsyncOperation(),
///   );
/// }
/// ```
mixin GuardedAsyncActionMixin<T> on Notifier<AsyncValue<T>> {
  /// Executes an async action with `AsyncValue.guard` and `ref.mounted` check.
  ///
  /// 1. Sets state to `AsyncLoading`
  /// 2. Awaits [operation] via `AsyncValue.guard`
  /// 3. Guards `ref.mounted` before assigning the result to state
  ///
  /// This is the canonical pattern for notifiers that use `AsyncValue<T>`
  /// directly as their state type.
  Future<void> guardedAction(Future<T> Function() operation) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(operation);

    // INV-15: Guard before mutating state after await
    if (!ref.mounted) return;

    state = result;
  }
}
