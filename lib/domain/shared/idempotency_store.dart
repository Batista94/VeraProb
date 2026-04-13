import 'package:veraprob/domain/shared/idempotency_key.dart';
import 'package:veraprob/domain/shared/idempotency_registration_result.dart';

/// Domain Port: Repository for managing idempotency keys (INV-33).
///
/// This interface defines the contract for persisting and querying
/// idempotency keys. Implementations live in Infrastructure.
///
/// **INV-33 Rules:**
/// - (a) Every mutating command MUST carry an idempotencyKey.
/// - (b) The key is CHECKed before any business logic executes.
/// - (c) If key status = 'completed' → return cached response_body (short-circuit).
/// - (d) If key status = 'processing' → reject (another thread is handling it).
/// - (e) If key is null → register as 'processing', execute, then update to 'completed'.
/// - (f) If the transaction rolls back, the key registration is also rolled back.
abstract class IIdempotencyStore {
  /// Registers a new idempotency key or returns the existing state atomically.
  ///
  /// **Atomic Acquisition (INV-33):** This operation MUST be atomic to prevent
  /// race conditions. It returns an [IdempotencyRegistrationResult] containing
  /// whether the lock was acquired and the current state of the key.
  ///
  /// [staleThresholdMinutes] controls how long a 'processing' key remains 
  /// locked before it can be reclaimed by a retry.
  Future<IdempotencyRegistrationResult> tryRegister(
    IdempotencyKey key, {
    int staleThresholdMinutes = 5,
  });

  /// Looks up an idempotency key by its ID and user ID.
  Future<IdempotencyKey?> findById(String id, {required String userId});

  /// Updates an idempotency key to 'completed' status with the response body.
  Future<void> markCompleted({
    required String id,
    required String userId,
    required int responseCode,
    required Map<String, dynamic> responseBody,
    required DateTime nowUtc,
  });

  /// Updates an idempotency key to 'error' status.
  ///
  /// [responseBody] can be used to cache validation errors (4xx) for replays.
  Future<void> markError({
    required String id,
    required String userId,
    required int responseCode,
    required DateTime nowUtc,
    Map<String, dynamic>? responseBody,
  });

  /// Removes expired idempotency keys.
  Future<int> cleanupExpired({int daysThreshold = 30});
}
