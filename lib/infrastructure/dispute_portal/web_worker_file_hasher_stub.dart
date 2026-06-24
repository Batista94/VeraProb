import 'dart:typed_data';

import 'package:veraprob/application/dispute_portal/i_file_hasher.dart';

/// Stub implementation for platforms where dart:js_interop is not available
/// (e.g., native VM during unit tests).
class WebWorkerFileHasher implements IFileHasher {
  const WebWorkerFileHasher();

  @override
  Future<String> sha256Hex(Uint8List bytes) {
    throw UnsupportedError(
      'WebWorkerFileHasher is only supported on Web platforms.',
    );
  }
}
