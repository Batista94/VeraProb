import 'idempotency_processing_exception.dart';

class ConcurrentModificationException extends IdempotencyProcessingException {
  const ConcurrentModificationException({
    required super.idempotencyKey,
    required super.commandPath,
    super.message =
        'Este cartão já está sendo processado por outra transação. Atualize a fila.',
  });

  @override
  String toString() =>
      'ConcurrentModificationException: $message '
      '(key: $idempotencyKey, command: $commandPath)';
}
