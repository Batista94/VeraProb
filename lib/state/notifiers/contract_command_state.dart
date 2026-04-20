import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Immutable state for contract command operations (INV-33).
///
/// Holds the idempotency key that MUST be passed to all mutating commands,
/// plus the async status of the current operation for UI feedback.
///
/// **INV-33:** The [idempotencyKey] is generated once when the notifier is
/// built and persisted across retries. This ensures that duplicate requests
/// (double-clicks, network retries) never produce duplicate side-effects.
class ContractCommandState {
  /// UUID v4 generated when the notifier is first built.
  /// Persisted across retries so the same key is reused.
  final String idempotencyKey;

  /// Async status of the current command execution.
  /// - `AsyncData(null)` = idle or last command succeeded
  /// - `AsyncLoading` = command in-flight
  /// - `AsyncError` = last command failed
  final AsyncValue<void> status;

  const ContractCommandState({
    required this.idempotencyKey,
    this.status = const AsyncData(null),
  });

  /// Returns a copy with the given [status] updated.
  /// The [idempotencyKey] is preserved.
  ContractCommandState copyWith({AsyncValue<void>? status}) {
    return ContractCommandState(
      idempotencyKey: idempotencyKey,
      status: status ?? this.status,
    );
  }

  /// Returns a new state with a fresh [idempotencyKey].
  ///
  /// Call this when the user changes the command data (e.g., fixes a form field)
  /// to ensure the next submission is treated as a **new intention**, not a
  /// network retry of the previous failed attempt.
  ContractCommandState withNewKey() {
    return ContractCommandState(
      idempotencyKey: const Uuid().v4(),
      status: const AsyncData(null),
    );
  }

  @override
  String toString() =>
      'ContractCommandState(key: $idempotencyKey, status: $status)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContractCommandState &&
          runtimeType == other.runtimeType &&
          idempotencyKey == other.idempotencyKey &&
          status == other.status;

  @override
  int get hashCode => idempotencyKey.hashCode ^ status.hashCode;
}
