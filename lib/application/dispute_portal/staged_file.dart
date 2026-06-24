import 'dart:typed_data';

class StagedFile {
  final String name;
  final int sizeBytes;
  final String mimeType;
  final Uint8List bytes;

  const StagedFile({
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
    required this.bytes,
  });
}
