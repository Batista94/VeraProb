import 'dart:typed_data';

abstract interface class IFileHasher {
  Future<String> sha256Hex(Uint8List bytes);
}

final class HasherException implements Exception {
  final String message;
  const HasherException(this.message);
}
