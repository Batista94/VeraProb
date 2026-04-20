import 'idempotency_key.dart';

/// Result of an atomic idempotency key registration attempt (INV-33).
///
/// Wraps the atomic response from the database to distinguish between
/// a successful new registration and a cache hit.
class IdempotencyRegistrationResult {
  /// Whether the key was successfully acquired (locked) for the current attempt.
  ///
  /// - `true`: Key is now in 'processing' state, caller holds the lock.
  /// - `false`: A collision occurred (already completed, processing, or stale).
  final bool acquired;

  /// The current state of the [IdempotencyKey] in the store.
  ///
  /// If [acquired] is `false`, this contains the cached response and metadata.
  final IdempotencyKey key;

  const IdempotencyRegistrationResult({
    required this.acquired,
    required this.key,
  });
}
