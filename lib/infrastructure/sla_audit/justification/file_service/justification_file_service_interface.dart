import 'dart:typed_data';

typedef PickedFile = ({String name, Uint8List bytes});

class PickedFilesResult {
  final List<PickedFile> picked;
  final List<String> oversized;
  const PickedFilesResult({required this.picked, required this.oversized});
}

abstract class JustificationFileService {
  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10 MB

  /// Prompts a native file picker and returns results split into [picked] (≤ maxFileSizeBytes)
  /// and [oversized] file names.
  Future<PickedFilesResult> pickFiles();

  /// HTTP PUT [bytes] to a pre-signed [url]. Throws on non-2xx response.
  Future<void> uploadPut(String url, Uint8List bytes);
}
