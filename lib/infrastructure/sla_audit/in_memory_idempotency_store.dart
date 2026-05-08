import 'package:veraprob/domain/shared/idempotency_key.dart';
import 'package:veraprob/domain/shared/idempotency_registration_result.dart';
import 'package:veraprob/domain/shared/idempotency_store.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

/// In-memory implementation of [IIdempotencyStore] for unit testing.
class InMemoryIdempotencyStore implements IIdempotencyStore {
  final Map<String, IdempotencyKey> _keys = {};
  final IDateTimeProvider _clock;

  InMemoryIdempotencyStore({IDateTimeProvider? clock})
    : _clock = clock ?? BrazilDateTimeProvider();

  @override
  Future<IdempotencyRegistrationResult> tryRegister(
    IdempotencyKey key, {
    int staleThresholdMinutes = 5,
  }) async {
    final existing = _keys[key.id];

    if (existing == null) {
      _keys[key.id] = key;
      return IdempotencyRegistrationResult(acquired: true, key: key);
    }

    // [Atomic Simulation] Logic to determine if we acquire or hit
    if (existing.isError ||
        (existing.isProcessing &&
            _clock.nowUtc().difference(existing.createdAtUtc).inMinutes >=
                staleThresholdMinutes)) {
      // Re-acquire stale or error key
      _keys[key.id] = key;
      return IdempotencyRegistrationResult(acquired: true, key: key);
    }

    return IdempotencyRegistrationResult(acquired: false, key: existing);
  }

  @override
  Future<IdempotencyKey?> findById(String id, {required String userId}) async {
    return _keys[id];
  }

  @override
  Future<void> markCompleted({
    required String id,
    required String userId,
    required int responseCode,
    required Map<String, dynamic> responseBody,
    required DateTime nowUtc,
  }) async {
    final existing = _keys[id];
    if (existing != null) {
      _keys[id] = existing.complete(
        responseCode: responseCode,
        responseBody: responseBody,
        nowUtc: nowUtc,
      );
    }
  }

  @override
  Future<void> markError({
    required String id,
    required String userId,
    required int responseCode,
    required DateTime nowUtc,
    Map<String, dynamic>? responseBody,
  }) async {
    final existing = _keys[id];
    if (existing != null) {
      _keys[id] = existing.fail(responseCode: responseCode, nowUtc: nowUtc);
      // In-memory simulation of error message caching
      if (responseBody != null) {
        _keys[id] = IdempotencyKey(
          id: existing.id,
          userId: existing.userId,
          commandPath: existing.commandPath,
          organizationId: existing.organizationId,
          status: 'error',
          responseCode: responseCode,
          responseBody: responseBody,
          createdAtUtc: existing.createdAtUtc,
          completedAtUtc: nowUtc,
          staleThresholdMinutes: existing.staleThresholdMinutes,
        );
      }
    }
  }

  @override
  Future<int> cleanupExpired({int daysThreshold = 30}) async {
    final now = _clock.nowUtc();
    final toRemove = _keys.entries
        .where((e) {
          final age = now.difference(e.value.createdAtUtc).inDays;
          return age >= daysThreshold;
        })
        .map((e) => e.key)
        .toList();

    for (final id in toRemove) {
      _keys.remove(id);
    }
    return toRemove.length;
  }
}
