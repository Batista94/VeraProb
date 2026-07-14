import 'package:meta/meta.dart';
import 'package:veraprob/domain/shared/idempotency_key.dart';
import 'package:veraprob/domain/shared/idempotency_store.dart';
import 'package:veraprob/domain/shared/idempotency_processing_exception.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Immutable bundle of the inputs to [IdempotentHandlerMixin.executeWithIdempotency].
///
/// Library-private: threaded only through the orchestration spine so the
/// atomic-lock guarantee cannot be broken by an override. All fields `final`
/// with a `const` constructor (INV-3 immutability spirit).
class _IdempotencyContext<T> {
  const _IdempotencyContext({
    required this.idempotencyStore,
    required this.idempotencyKey,
    required this.userId,
    required this.commandPath,
    required this.organizationId,
    required this.businessLogic,
    required this.toIdempotencyDto,
    required this.reloadEntity,
    required this.recoverIfAlreadyCompleted,
    required this.clock,
    required this.staleThresholdMinutes,
  });

  final IIdempotencyStore idempotencyStore;
  final String idempotencyKey;
  final String userId;
  final String commandPath;
  final String organizationId;
  final Future<T> Function() businessLogic;
  final Map<String, dynamic> Function(T) toIdempotencyDto;
  final Future<T?> Function(Map<String, dynamic>) reloadEntity;
  final Future<T?> Function()? recoverIfAlreadyCompleted;
  final IDateTimeProvider clock;
  final int staleThresholdMinutes;
}

/// Mixin for Application Handlers to orchestrate resilient, idempotent execution.
///
/// **Clean Architecture:** Orchestration lives in the Application layer,
/// while persistence is delegated to the [IIdempotencyStore] domain port.
///
/// **Forensic Invariants (INV-33):**
/// 1. **Atomic Acquisition**: Uses `tryRegister` result to prevent race conditions.
/// 2. **Self-Healing Recovery**: If a [DomainException] occurs but the business
///    operation succeeded in a previous partial attempt (detectable via
///    [attemptSelfHeal]), the key is repaired to 'completed'.
/// 3. **Conflict Guard**: [ConflictException] (Optimistic Locking) is NOT
///    cached as a stable error, allowing the user to refresh and retry.
/// 4. **Error Replay**: 4xx errors are cached and replayed identically.
///
/// **Structure:** the public entrypoint plus `_executeAcquired` /
/// `_replayCachedResult` form the private orchestration spine — they guard the
/// single-`tryRegister` race invariant and are not overridable. The recording
/// and replay seams are exposed as `@protected` hooks so individual handlers
/// can specialise behaviour without touching the spine.
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
    final ctx = _IdempotencyContext<T>(
      idempotencyStore: idempotencyStore,
      idempotencyKey: idempotencyKey,
      userId: userId,
      commandPath: commandPath,
      organizationId: organizationId,
      businessLogic: businessLogic,
      toIdempotencyDto: toIdempotencyDto,
      reloadEntity: reloadEntity,
      recoverIfAlreadyCompleted: recoverIfAlreadyCompleted,
      clock: clock,
      staleThresholdMinutes: staleThresholdMinutes,
    );

    final result = await idempotencyStore.tryRegister(
      _buildRegistrationTemplate(ctx),
      staleThresholdMinutes: staleThresholdMinutes,
    );

    return result.acquired
        ? _executeAcquired(ctx)
        : _replayCachedResult(ctx, result.key);
  }

  // ───────────────────────────────────────────────────────────────────
  // Private orchestration spine — guards the atomic-lock invariant.
  // ───────────────────────────────────────────────────────────────────

  IdempotencyKey _buildRegistrationTemplate<T>(_IdempotencyContext<T> ctx) {
    return IdempotencyKey.processing(
      id: ctx.idempotencyKey,
      userId: ctx.userId,
      commandPath: ctx.commandPath,
      organizationId: ctx.organizationId,
      nowUtc: ctx.clock.nowUtc(),
      staleThresholdMinutes: ctx.staleThresholdMinutes,
    );
  }

  /// ACQUIRED = TRUE: run the business logic.
  ///
  /// **Rollback integrity (INV-10):** every catch branch transitions the key
  /// out of `processing` (→ `error`) *before* rethrowing — no exception path
  /// may leave a key stuck in eternal `processing`.
  Future<T> _executeAcquired<T>(_IdempotencyContext<T> ctx) async {
    try {
      final entity = await ctx.businessLogic();
      await recordSuccess(
        idempotencyStore: ctx.idempotencyStore,
        idempotencyKey: ctx.idempotencyKey,
        userId: ctx.userId,
        responseBody: ctx.toIdempotencyDto(entity),
        clock: ctx.clock,
      );
      return entity;
    } on ConflictException {
      await recordConflict(
        idempotencyStore: ctx.idempotencyStore,
        idempotencyKey: ctx.idempotencyKey,
        userId: ctx.userId,
        clock: ctx.clock,
      );
      rethrow;
    } on DomainException catch (e) {
      final recovered = await _handleDomainException(ctx, e);
      if (recovered != null) return recovered;
      rethrow;
    } catch (_) {
      await recordInfrastructureError(
        idempotencyStore: ctx.idempotencyStore,
        idempotencyKey: ctx.idempotencyKey,
        userId: ctx.userId,
        clock: ctx.clock,
      );
      rethrow;
    }
  }

  /// Self-heals a [DomainException] or caches it as a 4xx. Returns the
  /// recovered entity on dual-write survival, or `null` to signal `rethrow`.
  Future<T?> _handleDomainException<T>(
    _IdempotencyContext<T> ctx,
    DomainException error,
  ) async {
    final recovered = await attemptSelfHeal(ctx.recoverIfAlreadyCompleted);
    if (recovered != null) {
      await recordSuccess(
        idempotencyStore: ctx.idempotencyStore,
        idempotencyKey: ctx.idempotencyKey,
        userId: ctx.userId,
        responseBody: ctx.toIdempotencyDto(recovered),
        clock: ctx.clock,
      );
      return recovered;
    }
    await recordDomainError(
      idempotencyStore: ctx.idempotencyStore,
      idempotencyKey: ctx.idempotencyKey,
      userId: ctx.userId,
      errorMessage: error.message,
      clock: ctx.clock,
    );
    return null;
  }

  /// ACQUIRED = FALSE: replay the cached outcome (completed / error / processing).
  Future<T> _replayCachedResult<T>(
    _IdempotencyContext<T> ctx,
    IdempotencyKey cached,
  ) {
    if (cached.isCompleted) {
      return replayCompletedResult(
        cached: cached,
        commandPath: ctx.commandPath,
        reloadEntity: ctx.reloadEntity,
      );
    }
    if (cached.isError) {
      return replayCachedError<T>(
        cached: cached,
        idempotencyKey: ctx.idempotencyKey,
        commandPath: ctx.commandPath,
      );
    }
    // Still 'processing' — another worker holds the lock.
    throw IdempotencyProcessingException(
      idempotencyKey: ctx.idempotencyKey,
      commandPath: ctx.commandPath,
    );
  }

  // ───────────────────────────────────────────────────────────────────
  // Protected lifecycle hooks — overridable per handler.
  // ───────────────────────────────────────────────────────────────────

  /// Records a successful execution (HTTP 200) with its replayable body.
  @protected
  Future<void> recordSuccess({
    required IIdempotencyStore idempotencyStore,
    required String idempotencyKey,
    required String userId,
    required Map<String, dynamic> responseBody,
    required IDateTimeProvider clock,
  }) {
    return idempotencyStore.markCompleted(
      id: idempotencyKey,
      userId: userId,
      responseCode: 200,
      responseBody: responseBody,
      nowUtc: clock.nowUtc(),
    );
  }

  /// Records an optimistic-locking conflict (HTTP 409).
  ///
  /// [Conflict Guard] The message is intentionally NOT cached so the caller
  /// can refresh and retry with fresh data.
  @protected
  Future<void> recordConflict({
    required IIdempotencyStore idempotencyStore,
    required String idempotencyKey,
    required String userId,
    required IDateTimeProvider clock,
  }) {
    return idempotencyStore.markError(
      id: idempotencyKey,
      userId: userId,
      responseCode: 409,
      nowUtc: clock.nowUtc(),
    );
  }

  /// Records a domain validation failure (HTTP 400) with a replayable message.
  @protected
  Future<void> recordDomainError({
    required IIdempotencyStore idempotencyStore,
    required String idempotencyKey,
    required String userId,
    required String errorMessage,
    required IDateTimeProvider clock,
  }) {
    return idempotencyStore.markError(
      id: idempotencyKey,
      userId: userId,
      responseCode: 400,
      responseBody: {'errorMessage': errorMessage},
      nowUtc: clock.nowUtc(),
    );
  }

  /// Records an infrastructure failure (HTTP 500) so SQL can reclaim the key.
  @protected
  Future<void> recordInfrastructureError({
    required IIdempotencyStore idempotencyStore,
    required String idempotencyKey,
    required String userId,
    required IDateTimeProvider clock,
  }) {
    return idempotencyStore.markError(
      id: idempotencyKey,
      userId: userId,
      responseCode: 500,
      nowUtc: clock.nowUtc(),
    );
  }

  /// Attempts dual-write self-healing recovery. Returns the recovered entity
  /// when the business operation succeeded in a prior partial attempt, else
  /// `null` (including when no recovery callback was supplied).
  @protected
  Future<T?> attemptSelfHeal<T>(
    Future<T?> Function()? recoverIfAlreadyCompleted,
  ) {
    if (recoverIfAlreadyCompleted == null) return Future<T?>.value();
    return recoverIfAlreadyCompleted();
  }

  /// Replays a previously completed result by reloading the live entity.
  @protected
  Future<T> replayCompletedResult<T>({
    required IdempotencyKey cached,
    required String commandPath,
    required Future<T?> Function(Map<String, dynamic>) reloadEntity,
  }) async {
    final body = cached.responseBody;
    if (body == null) {
      throw const IntegrityException(
        'Idempotency hit completed but body is missing.',
      );
    }

    final entity = await reloadEntity(body);
    if (entity == null) {
      // [Forensic Guardrail] Entity existed but was physically deleted.
      throw ConflictException.deleted(
        resourceType: commandPath.split('_').first,
        resourceId: body['id']?.toString() ?? 'unknown',
        clientVersion: (body['version'] as num?)?.toInt() ?? 0,
      );
    }
    return entity;
  }

  /// Replays a previously cached error: a cached 4xx is thrown identically as
  /// a [DomainException]; 5xx or null bodies fall through to an
  /// [IdempotencyProcessingException] retry signal.
  @protected
  Future<T> replayCachedError<T>({
    required IdempotencyKey cached,
    required String idempotencyKey,
    required String commandPath,
  }) async {
    final body = cached.responseBody;
    final responseCode = cached.responseCode ?? 500;

    if (responseCode >= 400 && responseCode < 500 && body != null) {
      final msg = body['errorMessage'] as String? ?? 'Cached validation error';
      throw DomainException(msg);
    }

    throw IdempotencyProcessingException(
      idempotencyKey: idempotencyKey,
      commandPath: commandPath,
    );
  }
}
