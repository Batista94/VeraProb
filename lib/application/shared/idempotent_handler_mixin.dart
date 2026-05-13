import 'package:veraprob/domain/shared/idempotency_key.dart';
import 'package:veraprob/domain/shared/idempotency_store.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

/// Mixin for Application Handlers to orchestrate resilient, idempotent execution.
///
/// **Clean Architecture:** Orchestration lives in the Application layer,
/// while persistence is delegated to the [IIdempotencyStore] domain port.
///
/// **Forensic Invariants (INV-33):**
/// 1. **Atomic Acquisition**: Uses `tryRegister` result to prevent race conditions.
/// 2. **Self-Healing Recovery**: If a [DomainException] occurs but the business
///    operation succeeded in a previous partial attempt (detectable via
///    [recoverIfAlreadyCompleted]), the key is repaired to 'completed'.
/// 3. **Conflict Guard**: [ConflictException] (Optimistic Locking) is NOT
///    cached as a stable error, allowing the user to refresh and retry.
/// 4. **Error Replay**: 4xx errors are cached and replayed identically.
mixin IdempotentHandlerMixin {
  /// Executes a command with full idempotency support and self-healing.
  Future<T> executeWithIdempotency<T>({
    required IIdempotencyStore idempotencyStore,
    required String idempotencyKey,
    required String userId,
    required String commandPath,
    required String organizationId,
    required Future<T> Function() businessLogic,
    required Map<String, dynamic> Function(T) toIdempotencyDto,
    required Future<T?> Function(Map<String, dynamic>) reloadEntity,
    Future<T?> Function()? recoverIfAlreadyCompleted,
    required IDateTimeProvider clock,
    int staleThresholdMinutes = 5,
  }) async {
    final registrationTemplate = IdempotencyKey.processing(
      id: idempotencyKey,
      userId: userId,
      commandPath: commandPath,
      organizationId: organizationId,
      nowUtc: clock.nowUtc(),
      staleThresholdMinutes: staleThresholdMinutes,
    );

    final result = await idempotencyStore.tryRegister(
      registrationTemplate,
      staleThresholdMinutes: staleThresholdMinutes,
    );

    // ── ACQUIRED = TRUE: Execute Business Logic ─────────────────────────────
    if (result.acquired) {
      try {
        final entity = await businessLogic();
        final dto = toIdempotencyDto(entity);

        await idempotencyStore.markCompleted(
          id: idempotencyKey,
          userId: userId,
          responseCode: 200,
          responseBody: dto,
          nowUtc: clock.nowUtc(),
        );

        return entity;
      } on ConflictException catch (_) {
        // [Conflict Guard] Optimistic locking conflict (409)
        // We do NOT cache the message to allow retry with fresh data.
        await idempotencyStore.markError(
          id: idempotencyKey,
          userId: userId,
          responseCode: 409, // Conflict
          nowUtc: clock.nowUtc(),
        );
        rethrow;
      } on DomainException catch (e) {
        // [Self-Healing Repair] Check if it's already completed as intended (Dual Write survival)
        if (recoverIfAlreadyCompleted != null) {
          final recovered = await recoverIfAlreadyCompleted();
          if (recovered != null) {
            final dto = toIdempotencyDto(recovered);
            await idempotencyStore.markCompleted(
              id: idempotencyKey,
              userId: userId,
              responseCode: 200,
              responseBody: dto,
              nowUtc: clock.nowUtc(),
            );
            return recovered;
          }
        }

        // Cache 4xx errors to avoid redundant execution
        await idempotencyStore.markError(
          id: idempotencyKey,
          userId: userId,
          responseCode: 400,
          responseBody: {'errorMessage': e.message},
          nowUtc: clock.nowUtc(),
        );
        rethrow;
      } catch (e) {
        // [Resilience] Infrastructure error (500)
        // Reset key to error so SQL can reclaim it for retries.
        await idempotencyStore.markError(
          id: idempotencyKey,
          userId: userId,
          responseCode: 500,
          nowUtc: clock.nowUtc(),
        );
        rethrow;
      }
    }

    // ── ACQUIRED = FALSE: Handle Cache Hit (Replay) ─────────────────────────
    final cached = result.key;

    if (cached.isCompleted) {
      final body = cached.responseBody;
      if (body == null) {
        throw StateError('Idempotency hit completed but body is missing.');
      }

      final entity = await reloadEntity(body);
      if (entity == null) {
        // [Forensic Guardrail] Entity existed but was physically deleted
        throw ConflictException.deleted(
          resourceType: commandPath.split('_').first,
          resourceId: body['id']?.toString() ?? 'unknown',
          clientVersion: (body['version'] as num?)?.toInt() ?? 0,
        );
      }
      return entity;
    }

    if (cached.isError) {
      final body = cached.responseBody;
      final responseCode = cached.responseCode ?? 500;

      // If we cached a 4xx error message, throw DomainException
      if (responseCode >= 400 && responseCode < 500 && body != null) {
        final msg =
            body['errorMessage'] as String? ?? 'Cached validation error';
        throw DomainException(msg);
      }

      // For 5xx errors or null bodies, allow retry by falling through to acquire
      // (The RPC handles stale reclamation, but here we likely just want
      // the caller to retry after a short delay or throw to trigger the Notifier's AsyncError).
      throw IdempotencyProcessingException(
        idempotencyKey: idempotencyKey,
        commandPath: commandPath,
      );
    }

    // Still 'processing'
    throw IdempotencyProcessingException(
      idempotencyKey: idempotencyKey,
      commandPath: commandPath,
    );
  }
}
