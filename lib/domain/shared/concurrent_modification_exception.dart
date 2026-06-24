class ConcurrentModificationException implements Exception {
  final String message;

  const ConcurrentModificationException([
    this.message =
        'Este cartão já está sendo processado por outra transação. Atualize a fila.',
  ]);

  @override
  String toString() => 'ConcurrentModificationException: $message';
}
