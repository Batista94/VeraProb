/// Exception thrown when an idempotency key is already being processed
/// by another thread or request.
///
/// This is a **temporary** state — it means the same command (identified by
/// [idempotencyKey]) is currently in-flight and has not yet completed.
///
/// **Client behavior:** The caller should either:
/// - Poll the command status endpoint to check if the original request completed.
/// - Wait and retry after a short delay (e.g., 500ms).
///
/// This exception is NOT an error — it's a concurrency guard to prevent
/// duplicate side-effects (INV-33).
class IdempotencyProcessingException implements Exception {
  /// The idempotency key that is currently in 'processing' state.
  final String idempotencyKey;

  /// The command path being processed (e.g., 'close_contract').
  final String commandPath;

  /// Human-readable explanation.
  final String message;

  const IdempotencyProcessingException({
    required this.idempotencyKey,
    required this.commandPath,
    this.message =
        'Command is already being processed. '
        'Please wait and retry, or check the command status.',
  });

  @override
  String toString() =>
      'IdempotencyProcessingException: $message '
      '(key: $idempotencyKey, command: $commandPath)';
}
